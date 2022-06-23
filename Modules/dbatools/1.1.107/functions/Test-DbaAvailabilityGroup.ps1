function Test-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Tests the health of an Availability Group and prerequisites for changing it.

    .DESCRIPTION
        Tests the health of an Availability Group.

        Can also test whether all prerequisites for Add-DbaAgDatabase are met.

    .PARAMETER SqlInstance
        The primary replica of the Availability Group.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        The name of the Availability Group to test.

    .PARAMETER Secondary
        Not required - the command will figure this out. But use this parameter if secondary replicas listen on a non default port.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AddDatabase
        Test whether all prerequisites for Add-DbaAgDatabase to add these databases to the Availability Group are met.

        Use Secondary, SecondarySqlCredential, SeedingMode, SharedPath and UseLastBackup with the same values that will be used with Add-DbaAgDatabase later.

    .PARAMETER SeedingMode
        Only used when AddDatabase is used. See documentation at Add-DbaAgDatabase for more details.

    .PARAMETER SharedPath
        Only used when AddDatabase is used. See documentation at Add-DbaAgDatabase for more details.

    .PARAMETER UseLastBackup
        Only used when AddDatabase is used. See documentation at Add-DbaAgDatabase for more details.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG, Test
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Test-DbaAvailabilityGroup -SqlInstance SQL2016 -AvailabilityGroup TestAG1

        Test Availability Group TestAG1 with SQL2016 as the primary replica.

    .EXAMPLE
        PS C:\> Test-DbaAvailabilityGroup -SqlInstance SQL2016 -AvailabilityGroup TestAG1 -AddDatabase AdventureWorks -SeedingMode Automatic

        Test if database AdventureWorks can be added to the Availability Group TestAG1 with automatic seeding.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [string]$AvailabilityGroup,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        [string[]]$AddDatabase,
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [string]$SharedPath,
        [switch]$UseLastBackup,
        [switch]$EnableException
    )
    process {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        try {
            $ag = Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $AvailabilityGroup -EnableException
        } catch {
            Stop-Function -Message "Availability Group $AvailabilityGroup not found on $server." -ErrorRecord $_
            return
        }

        if (-not $ag) {
            Stop-Function -Message "Availability Group $AvailabilityGroup not found on $server."
            return
        }

        if ($ag.LocalReplicaRole -ne 'Primary') {
            Stop-Function -Message "LocalReplicaRole of replica $server is not Primary, but $($ag.LocalReplicaRole). Please connect to the current primary replica $($ag.PrimaryReplica)."
            return
        }

        # Test for health of Availability Group

        # Later: Get replica and database states like in SSMS dashboard
        # Now: Just test for ConnectionState -eq 'Connected'

        # Note on further development:
        # As long as there are no databases in the Availability Group, test for RollupSynchronizationState is not useful

        # The primary replica always has the best information about all the replicas.
        # We can maybe also connect to the secondary replicas and test their view of the situation, but then only test the local replica.

        $failure = $false
        foreach ($replica in $ag.AvailabilityReplicas) {
            if ($replica.ConnectionState -ne 'Connected') {
                $failure = $true
                Stop-Function -Message "ConnectionState of replica $replica is not Connected, but $($replica.ConnectionState)." -Continue
            }
        }
        if ($failure) {
            Stop-Function -Message "ConnectionState of one or more replicas is not Connected."
            return
        }


        # For now, just output the base information.

        if (-not $AddDatabase) {
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.AvailabilityGroup
            }
        }


        # Test for Add-DbaAgDatabase

        foreach ($dbName in $AddDatabase) {
            $db = $server.Databases[$dbName]

            if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
                Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above" -Target $server
                return
            }

            if (-not $db) {
                Stop-Function -Message "Database $db is not found on $server." -Continue
            }

            if ($db.RecoveryModel -ne 'Full') {
                Stop-Function -Message "RecoveryModel of database $db is not Full, but $($db.RecoveryModel)." -Continue
            }

            if ($db.Status -ne 'Normal') {
                Stop-Function -Message "Status of database $db is not Normal, but $($db.Status)." -Continue
            }

            $backups = @( )
            if ($UseLastBackup) {
                try {
                    $backups = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -IncludeCopyOnly -Last -EnableException
                } catch {
                    Stop-Function -Message "Failed to get backup history for database $db." -ErrorRecord $_ -Continue
                }
                if ($backups.Type -notcontains 'Log') {
                    Stop-Function -Message "Cannot use last backup for database $db. A log backup must be the last backup taken." -Continue
                }
            }

            if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
                Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above." -Continue
            }

            # Try to connect to secondary replicas as soon as possible to fail the command before making any changes to the Availability Group.
            # Also test if these are really secondary replicas for that availability group. Only needed if -Secondary is used, but will do it anyway to simplify code.
            # Also test if database is already at the secondary and if so if Status is Restoring.
            # We store the server SMO in a hashtable based on the DomainInstanceName of the server as this is equal to the name of the replica in $ag.AvailabilityReplicas.
            if ($Secondary) {
                $secondaryReplicas = $Secondary
            } else {
                $secondaryReplicas = ($ag.AvailabilityReplicas | Where-Object { $_.Role -eq 'Secondary' }).Name
            }

            $replicaServerSMO = @{ }
            $restoreNeeded = @{ }
            $backupNeeded = $false
            $failure = $false
            foreach ($replica in $secondaryReplicas) {
                try {
                    $replicaServer = Connect-DbaInstance -SqlInstance $replica -SqlCredential $SecondarySqlCredential
                } catch {
                    $failure = $true
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $replica -Continue
                }

                try {
                    $replicaAg = Get-DbaAvailabilityGroup -SqlInstance $replicaServer -AvailabilityGroup $AvailabilityGroup -EnableException
                    $replicaName = $replicaAg.Parent.DomainInstanceName
                } catch {
                    $failure = $true
                    Stop-Function -Message "Availability Group $AvailabilityGroup not found on replica $replicaServer." -ErrorRecord $_ -Continue
                }

                if (-not $replicaAg) {
                    $failure = $true
                    Stop-Function -Message "Availability Group $AvailabilityGroup not found on replica $replicaServer." -Continue
                }

                if ($replicaAg.LocalReplicaRole -ne 'Secondary') {
                    $failure = $true
                    Stop-Function -Message "LocalReplicaRole of replica $replicaServer is not Secondary, but $($replicaAg.LocalReplicaRole)." -Continue
                }

                $replicaDb = $replicaAg.Parent.Databases[$db.Name]

                if ($replicaDb) {
                    # Database already present on replica, so test if already joined or if we can use it.
                    if ($replicaDb.AvailabilityGroupName -eq $AvailabilityGroup) {
                        Write-Message -Level Verbose -Message "Database $db is already part of the Availability Group on replica $replicaName."
                    } else {
                        if ($replicaDb.Status -ne 'Restoring') {
                            $failure = $true
                            Stop-Function -Message "Status of database $db on replica $replicaName is not Restoring, but $($replicaDb.Status)" -Continue
                        }
                        if ($UseLastBackup) {
                            $failure = $true
                            Stop-Function -Message "Database $db is already present on $replicaName, so -UseLastBackup must not be used. Please remove database from replica to use -UseLastBackup." -Continue
                        }
                        Write-Message -Level Verbose -Message "Database $db is already present in restoring status on replica $replicaName."
                    }
                } else {
                    # No database on replica, so test if we need a backup.
                    # We need to restore a backup if the desired or the current seeding mode is manual.
                    # To have a detailed verbose message, we test in small steps.
                    if ($SeedingMode -eq 'Automatic') {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic') {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName. The replica is already configured accordingly."
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName. The replica will be configured accordingly."
                        }
                        if ($db.LastBackupDate.Year -eq 1) {
                            # Automatic seeding only works with databases that are really in RecoveryModel Full, so a full backup has been taken.
                            Write-Message -Level Verbose -Message "Database $db will need a backup first. This is ok if one of the other replicas uses manual seeding."
                            $backupNeeded = $true
                        }
                    } elseif ($SeedingMode -eq 'Manual') {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Manual') {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName. The replica is already configured accordingly."
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName. The replica will be configured accordingly."
                        }
                        $restoreNeeded[$replicaName] = $true
                    } else {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic') {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName."
                            if ($db.LastBackupDate.Year -eq 1) {
                                # Automatic seeding only works with databases that are really in RecoveryModel Full, so a full backup has been taken.
                                Write-Message -Level Verbose -Message "Database $db will need a backup first. This is ok if one of the other replicas uses manual seeding."
                                $backupNeeded = $true
                            }
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName."
                            $restoreNeeded[$replicaName] = $true
                        }
                    }
                }
                $replicaServerSMO[$replicaName] = $replicaAg.Parent
            }
            if ($failure) {
                Stop-Function -Message "Availability Group $AvailabilityGroup or database $db not found in suitable state on all secondary replicas." -Continue
            }
            if ($restoreNeeded.Count -gt 0 -and -not $SharedPath -and -not $UseLastBackup) {
                Stop-Function -Message "A restore of database $db is needed on one or more replicas, but -SharedPath or -UseLastBackup are missing." -Continue
            }
            if ($backupNeeded -and $restoreNeeded.Count -eq 0) {
                Stop-Function -Message "All replicas are configured to use automatic seeding, but the database $db was never backed up. Please backup the database or use manual seeding." -Continue
            }

            [PSCustomObject]@{
                ComputerName          = $ag.ComputerName
                InstanceName          = $ag.InstanceName
                SqlInstance           = $ag.SqlInstance
                AvailabilityGroupName = $ag.Name
                DatabaseName          = $db.Name
                AvailabilityGroupSMO  = $ag
                DatabaseSMO           = $db
                PrimaryServerSMO      = $server
                ReplicaServerSMO      = $replicaServerSMO
                RestoreNeeded         = $restoreNeeded
                Backups               = $backups
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBAzdvwskTJ0IzO
# o01bo/I6PczzU1xhEwYr3MJYfa+4gKCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
# Y1+/3q4SBOdtMA0GCSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNV
# BAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcN
# MjAwNTEyMDAwMDAwWhcNMjMwNjA4MTIwMDAwWjBXMQswCQYDVQQGEwJVUzERMA8G
# A1UECBMIVmlyZ2luaWExDzANBgNVBAcTBlZpZW5uYTERMA8GA1UEChMIZGJhdG9v
# bHMxETAPBgNVBAMTCGRiYXRvb2xzMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
# CgKCAQEAvL9je6vjv74IAbaY5rXqHxaNeNJO9yV0ObDg+kC844Io2vrHKGD8U5hU
# iJp6rY32RVprnAFrA4jFVa6P+sho7F5iSVAO6A+QZTHQCn7oquOefGATo43NAadz
# W2OWRro3QprMPZah0QFYpej9WaQL9w/08lVaugIw7CWPsa0S/YjHPGKQ+bYgI/kr
# EUrk+asD7lvNwckR6pGieWAyf0fNmSoevQBTV6Cd8QiUfj+/qWvLW3UoEX9ucOGX
# 2D8vSJxL7JyEVWTHg447hr6q9PzGq+91CO/c9DWFvNMjf+1c5a71fEZ54h1mNom/
# XoWZYoKeWhKnVdv1xVT1eEimibPEfQIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAU
# WsS5eyoKo6XqcQPAYPkt9mV1DlgwHQYDVR0OBBYEFPDAoPu2A4BDTvsJ193ferHL
# 454iMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8E
# cDBuMDWgM6Axhi9odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVk
# LWNzLWcxLmNybDA1oDOgMYYvaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTIt
# YXNzdXJlZC1jcy1nMS5jcmwwTAYDVR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggr
# BgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEw
# gYQGCCsGAQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/
# BAIwADANBgkqhkiG9w0BAQsFAAOCAQEAj835cJUMH9Y2pBKspjznNJwcYmOxeBcH
# Ji+yK0y4bm+j44OGWH4gu/QJM+WjZajvkydJKoJZH5zrHI3ykM8w8HGbYS1WZfN4
# oMwi51jKPGZPw9neGS2PXrBcKjzb7rlQ6x74Iex+gyf8z1ZuRDitLJY09FEOh0BM
# LaLh+UvJ66ghmfIyjP/g3iZZvqwgBhn+01fObqrAJ+SagxJ/21xNQJchtUOWIlxR
# kuUn9KkuDYrMO70a2ekHODcAbcuHAGI8wzw4saK1iPPhVTlFijHS+7VfIt/d/18p
# MLHHArLQQqe1Z0mTfuL4M4xCUKpebkH8rI3Fva62/6osaXLD0ymERzCCBTAwggQY
# oAMCAQICEAQJGBtf1btmdVNDtW+VUAgwDQYJKoZIhvcNAQELBQAwZTELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4X
# DTEzMTAyMjEyMDAwMFoXDTI4MTAyMjEyMDAwMFowcjELMAkGA1UEBhMCVVMxFTAT
# BgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEx
# MC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAPjTsxx/DhGvZ3cH0wsx
# SRnP0PtFmbE620T1f+Wondsy13Hqdp0FLreP+pJDwKX5idQ3Gde2qvCchqXYJawO
# eSg6funRZ9PG+yknx9N7I5TkkSOWkHeC+aGEI2YSVDNQdLEoJrskacLCUvIUZ4qJ
# RdQtoaPpiCwgla4cSocI3wz14k1gGL6qxLKucDFmM3E+rHCiq85/6XzLkqHlOzEc
# z+ryCuRXu0q16XTmK/5sy350OTYNkO/ktU6kqepqCquE86xnTrXE94zRICUj6whk
# PlKWwfIPEvTFjg/BougsUfdzvL2FsWKDc0GCB+Q4i2pzINAPZHM8np+mM6n9Gd8l
# k9ECAwEAAaOCAc0wggHJMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQD
# AgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHkGCCsGAQUFBwEBBG0wazAkBggrBgEF
# BQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRw
# Oi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0Eu
# Y3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8vY3JsNC5kaWdpY2VydC5jb20v
# RGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsME8GA1UdIARI
# MEYwOAYKYIZIAYb9bAACBDAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdp
# Y2VydC5jb20vQ1BTMAoGCGCGSAGG/WwDMB0GA1UdDgQWBBRaxLl7KgqjpepxA8Bg
# +S32ZXUOWDAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzANBgkqhkiG
# 9w0BAQsFAAOCAQEAPuwNWiSz8yLRFcgsfCUpdqgdXRwtOhrE7zBh134LYP3DPQ/E
# r4v97yrfIFU3sOH20ZJ1D1G0bqWOWuJeJIFOEKTuP3GOYw4TS63XX0R58zYUBor3
# nEZOXP+QsRsHDpEV+7qvtVHCjSSuJMbHJyqhKSgaOnEoAjwukaPAJRHinBRHoXpo
# aK+bp1wgXNlxsQyPu6j4xRJon89Ay0BEpRPw5mQMJQhCMrI2iiQC/i9yfhzXSUWW
# 6Fkd6fp0ZGuy62ZD2rOwjNXpDd32ASDOmTFjPQgaGLOBm0/GkxAG/AeB+ova+YJJ
# 92JuoVP6EpQYhS6SkepobEQysmah5xikmmRR7zCCBbEwggSZoAMCAQICEAEkCvse
# OAuKFvFLcZ3008AwDQYJKoZIhvcNAQEMBQAwZTELMAkGA1UEBhMCVVMxFTATBgNV
# BAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIG
# A1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTIyMDYwOTAwMDAw
# MFoXDTMxMTEwOTIzNTk1OVowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGln
# aUNlcnQgVHJ1c3RlZCBSb290IEc0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAv+aQc2jeu+RdSjwwIjBpM+zCpyUuySE98orYWcLhKac9WKt2ms2uexuE
# DcQwH/MbpDgW61bGl20dq7J58soR0uRf1gU8Ug9SH8aeFaV+vp+pVxZZVXKvaJNw
# wrK6dZlqczKU0RBEEC7fgvMHhOZ0O21x4i0MG+4g1ckgHWMpLc7sXk7Ik/ghYZs0
# 6wXGXuxbGrzryc/NrDRAX7F6Zu53yEioZldXn1RYjgwrt0+nMNlW7sp7XeOtyU9e
# 5TXnMcvak17cjo+A2raRmECQecN4x7axxLVqGDgDEI3Y1DekLgV9iPWCPhCRcKtV
# gkEy19sEcypukQF8IUzUvK4bA3VdeGbZOjFEmjNAvwjXWkmkwuapoGfdpCe8oU85
# tRFYF/ckXEaPZPfBaYh2mHY9WV1CdoeJl2l6SPDgohIbZpp0yt5LHucOY67m1O+S
# kjqePdwA5EUlibaaRBkrfsCUtNJhbesz2cXfSwQAzH0clcOP9yGyshG3u3/y1Yxw
# LEFgqrFjGESVGnZifvaAsPvoZKYz0YkH4b235kOkGLimdwHhD5QMIR2yVCkliWzl
# DlJRR3S+Jqy2QXXeeqxfjT/JvNNBERJb5RBQ6zHFynIWIgnffEx1P2PsIV/EIFFr
# b7GrhotPwtZFX50g/KEexcCPorF+CiaZ9eRpL5gdLfXZqbId5RsCAwEAAaOCAV4w
# ggFaMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFOzX44LScV1kTN8uZz/nupiu
# HA9PMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA4GA1UdDwEB/wQE
# AwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB5BggrBgEFBQcBAQRtMGswJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQC
# MAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQwFAAOCAQEAmhYCpQHvgfsNtFiyeK2o
# IxnZczfaYJ5R18v4L0C5ox98QE4zPpA854kBdYXoYnsdVuBxut5exje8eVxiAE34
# SXpRTQYy88XSAConIOqJLhU54Cw++HV8LIJBYTUPI9DtNZXSiJUpQ8vgplgQfFOO
# n0XJIDcUwO0Zun53OdJUlsemEd80M/Z1UkJLHJ2NltWVbEcSFCRfJkH6Gka93rDl
# kUcDrBgIy8vbZol/K5xlv743Tr4t851Kw8zMR17IlZWt0cu7KgYg+T9y6jbrRXKS
# eil7FAM8+03WSHF6EBGKCHTNbBsEXNKKlQN2UVBT1i73SkbDrhAscUywh7YnN0Rg
# RDCCBq4wggSWoAMCAQICEAc2N7ckVHzYR6z9KGYqXlswDQYJKoZIhvcNAQELBQAw
# YjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQ
# d3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290
# IEc0MB4XDTIyMDMyMzAwMDAwMFoXDTM3MDMyMjIzNTk1OVowYzELMAkGA1UEBhMC
# VVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBU
# cnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAMaGNQZJs8E9cklRVcclA8TykTepl1Gh
# 1tKD0Z5Mom2gsMyD+Vr2EaFEFUJfpIjzaPp985yJC3+dH54PMx9QEwsmc5Zt+Feo
# An39Q7SE2hHxc7Gz7iuAhIoiGN/r2j3EF3+rGSs+QtxnjupRPfDWVtTnKC3r07G1
# decfBmWNlCnT2exp39mQh0YAe9tEQYncfGpXevA3eZ9drMvohGS0UvJ2R/dhgxnd
# X7RUCyFobjchu0CsX7LeSn3O9TkSZ+8OpWNs5KbFHc02DVzV5huowWR0QKfAcsW6
# Th+xtVhNef7Xj3OTrCw54qVI1vCwMROpVymWJy71h6aPTnYVVSZwmCZ/oBpHIEPj
# Q2OAe3VuJyWQmDo4EbP29p7mO1vsgd4iFNmCKseSv6De4z6ic/rnH1pslPJSlREr
# WHRAKKtzQ87fSqEcazjFKfPKqpZzQmiftkaznTqj1QPgv/CiPMpC3BhIfxQ0z9JM
# q++bPf4OuGQq+nUoJEHtQr8FnGZJUlD0UfM2SU2LINIsVzV5K6jzRWC8I41Y99xh
# 3pP+OcD5sjClTNfpmEpYPtMDiP6zj9NeS3YSUZPJjAw7W4oiqMEmCPkUEBIDfV8j
# u2TjY+Cm4T72wnSyPx4JduyrXUZ14mCjWAkBKAAOhFTuzuldyF4wEr1GnrXTdrnS
# DmuZDNIztM2xAgMBAAGjggFdMIIBWTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1Ud
# DgQWBBS6FtltTYUvcyl2mi91jGogj57IbzAfBgNVHSMEGDAWgBTs1+OC0nFdZEzf
# Lmc/57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# dwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2Vy
# dC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFRydXN0ZWRSb290RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6
# Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAG
# A1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOC
# AgEAfVmOwJO2b5ipRCIBfmbW2CFC4bAYLhBNE88wU86/GPvHUF3iSyn7cIoNqilp
# /GnBzx0H6T5gyNgL5Vxb122H+oQgJTQxZ822EpZvxFBMYh0MCIKoFr2pVs8Vc40B
# IiXOlWk/R3f7cnQU1/+rT4osequFzUNf7WC2qk+RZp4snuCKrOX9jLxkJodskr2d
# fNBwCnzvqLx1T7pa96kQsl3p/yhUifDVinF2ZdrM8HKjI/rAJ4JErpknG6skHibB
# t94q6/aesXmZgaNWhqsKRcnfxI2g55j7+6adcq/Ex8HBanHZxhOACcS2n82HhyS7
# T6NJuXdmkfFynOlLAlKnN36TU6w7HQhJD5TNOXrd/yVjmScsPT9rp/Fmw0HNT7ZA
# myEhQNC3EyTN3B14OuSereU0cZLXJmvkOHOrpgFPvT87eK1MrfvElXvtCl8zOYdB
# eHo46Zzh3SP9HSjTx/no8Zhf+yvYfvJGnXUsHicsJttvFXseGYs2uJPU5vIXmVnK
# cPA3v5gA3yAWTyf7YGcWoWa63VXAOimGsJigK+2VQbc61RWYMbRiCQ8KvYHZE/6/
# pNHzV9m8BPqC3jLfBInwAM1dwvnQI38AC+R2AibZ8GV2QqYphwlHK+Z/GqSFD/yY
# lvZVVCsfgPrA8g4r5db7qS9EFUrnEw4d2zc4GqEr9u3WfPwwggbGMIIErqADAgEC
# AhAKekqInsmZQpAGYzhNhpedMA0GCSqGSIb3DQEBCwUAMGMxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1
# c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMjIwMzI5
# MDAwMDAwWhcNMzMwMzE0MjM1OTU5WjBMMQswCQYDVQQGEwJVUzEXMBUGA1UEChMO
# RGlnaUNlcnQsIEluYy4xJDAiBgNVBAMTG0RpZ2lDZXJ0IFRpbWVzdGFtcCAyMDIy
# IC0gMjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALkqliOmXLxf1knw
# FYIY9DPuzFxs4+AlLtIx5DxArvurxON4XX5cNur1JY1Do4HrOGP5PIhp3jzSMFEN
# MQe6Rm7po0tI6IlBfw2y1vmE8Zg+C78KhBJxbKFiJgHTzsNs/aw7ftwqHKm9MMYW
# 2Nq867Lxg9GfzQnFuUFqRUIjQVr4YNNlLD5+Xr2Wp/D8sfT0KM9CeR87x5MHaGjl
# RDRSXw9Q3tRZLER0wDJHGVvimC6P0Mo//8ZnzzyTlU6E6XYYmJkRFMUrDKAz200k
# heiClOEvA+5/hQLJhuHVGBS3BEXz4Di9or16cZjsFef9LuzSmwCKrB2NO4Bo/tBZ
# mCbO4O2ufyguwp7gC0vICNEyu4P6IzzZ/9KMu/dDI9/nw1oFYn5wLOUrsj1j6siu
# gSBrQ4nIfl+wGt0ZvZ90QQqvuY4J03ShL7BUdsGQT5TshmH/2xEvkgMwzjC3iw9d
# RLNDHSNQzZHXL537/M2xwafEDsTvQD4ZOgLUMalpoEn5deGb6GjkagyP6+SxIXuG
# Z1h+fx/oK+QUshbWgaHK2jCQa+5vdcCwNiayCDv/vb5/bBMY38ZtpHlJrYt/YYcF
# aPfUcONCleieu5tLsuK2QT3nr6caKMmtYbCgQRgZTu1Hm2GV7T4LYVrqPnqYklHN
# P8lE54CLKUJy93my3YTqJ+7+fXprAgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMC
# B4AwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAE
# GTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3Mp
# dpovdYxqII+eyG8wHQYDVR0OBBYEFI1kt4kh/lZYRIRhp+pvHDaP3a8NMFoGA1Ud
# HwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRy
# dXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUF
# BwEBBIGDMIGAMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20w
# WAYIKwYBBQUHMAKGTGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZI
# hvcNAQELBQADggIBAA0tI3Sm0fX46kuZPwHk9gzkrxad2bOMl4IpnENvAS2rOLVw
# Eb+EGYs/XeWGT76TOt4qOVo5TtiEWaW8G5iq6Gzv0UhpGThbz4k5HXBw2U7fIyJs
# 1d/2WcuhwupMdsqh3KErlribVakaa33R9QIJT4LWpXOIxJiA3+5JlbezzMWn7g7h
# 7x44ip/vEckxSli23zh8y/pc9+RTv24KfH7X3pjVKWWJD6KcwGX0ASJlx+pedKZb
# NZJQfPQXpodkTz5GiRZjIGvL8nvQNeNKcEiptucdYL0EIhUlcAZyqUQ7aUcR0+7p
# x6A+TxC5MDbk86ppCaiLfmSiZZQR+24y8fW7OK3NwJMR1TJ4Sks3KkzzXNy2hcC7
# cDBVeNaY/lRtf3GpSBp43UZ3Lht6wDOK+EoojBKoc88t+dMj8p4Z4A2UKKDr2xpR
# oJWCjihrpM6ddt6pc6pIallDrl/q+A8GQp3fBmiW/iqgdFtjZt5rLLh4qk1wbfAs
# 8QcVfjW05rUMopml1xVrNQ6F1uAszOAMJLh8UgsemXzvyMjFjFhpr6s94c/MfRWu
# FL+Kcd/Kl7HYR+ocheBFThIcFClYzG/Tf8u+wQ5KbyCcrtlzMlkI5y2SoRoR/jKY
# pl0rl+CL05zMbbUNrkdjOEcXW28T2moQbh9Jt0RbtAgKh1pZBHYRoad3AhMcMYIF
# XTCCBVkCAQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQg
# U0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQAwW7hiGwoWNfv96uEgTn
# bTANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkG
# CSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCC6cx9ke4xGgyAkXQDGosLldzVEZUZa8U6x
# j3FP9KLXOTANBgkqhkiG9w0BAQEFAASCAQBOjWvdw4jnuReDjFeLFFGcdEgfsq/v
# kJSHdgxZepAlJ5Crf73fvbPaUAhqhQV5yf29DD5ct38op28ZKpmUDnY2KrzaM7pL
# xbj9dnYWZZKU/GEtAMbJ2bkn9duZnFXUits28/Mk+dv2DYJ6qplYt5kDb2FAOuWp
# fks4OrqlF8SJytZFaBrezMMenJCJiJm2/mn2dvgZ6SyX/YQeIAGfxx7oP+8tj9Zc
# dBenGATjCpUVLt06Y5H7y2VAXJQ7rWUYB5+3FWSJwY7AL6peU2L59IY/jeW6onk1
# wnR3Io2/l0mDy0ekMOVjvS5Y+3LiKcwRObq0kL2rWuw2sumdJDOgX2OtoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQwNFowLwYJKoZIhvcNAQkEMSIEIIIcNA8Q
# FXOnU/mjdwfGrjyex8oFWzsjTWz1iVh7n/BsMA0GCSqGSIb3DQEBAQUABIICAAkX
# LE0E7zz7NRSkIHorqfXVvm6Z5rnWwxo+ZNdyUP/FNxWlrvDDQ8rieIBXUMGXAeQx
# CO2TxunO32EJgmK+gKOyZMBdHyqR7JOLiTpcl8EeqhOWka0pkMZH9UD2QWooySK9
# Fjww2K/wepmAcS2UYD+9yW5mrEmG5/bN4zz8XZYW6pSoDWCchWgDK1adXtx2MeFQ
# r8I421SC4CNwTbIgPls2NgoatwnkXuE+k/8ypwADCiLF+uH9fCZLEY7o3gF6q3Zj
# zsnWv6dYIPH/ZW1je50IoU8ktOQXYI0oKDeEzEfdHCpO8u9+6w6ah+AfQAeXz6z0
# 5ldLi7xMcCGizLKtnQwfSZO9E/23x7594jIYnyKEUiioyHp4XQFC519NlHfkcrFL
# 4jFGRu/eiY+J6BYeNULiIHXi5myyAdxP+lbJlZpT9YTBQ9bfCveTGITS4k6BMw1F
# auJh71ewG6Xs+35BEV7hQYuXZYajPtnZEUbh3w8z9qGqvfP3AE/ZChifAadSKqGA
# EDxE7GsbxduTxvxAMTQWzuqPeIAe3ETRgqRXH032q5ljKwucy3KWEKFRbLWMq2JF
# AhbXtiNNU3vWTVQdzdheg/Y8NaU6XcVE3bqk5OCYuoiXg0jorghogHzS0nfzv0WC
# Fbantz1aBXz0EkL6VIxMCO51CXLA3Xxnh9QfBzro
# SIG # End signature block
