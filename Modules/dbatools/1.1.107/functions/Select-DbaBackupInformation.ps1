function Select-DbaBackupInformation {
    <#
    .SYNOPSIS
        Select a subset of backups from a dbatools backup history object

    .DESCRIPTION
        Select-DbaBackupInformation filters out a subset of backups from the dbatools backup history object with parameters supplied.

    .PARAMETER BackupHistory
        A dbatools.BackupHistory object containing backup history records

    .PARAMETER RestoreTime
        The point in time you want to restore to

    .PARAMETER IgnoreLogs
        This switch will cause Log Backups to be ignored. So will restore to the last Full or Diff backup only

    .PARAMETER IgnoreDiffs
        This switch will cause Differential backups to be ignored. Unless IgnoreLogs is specified, restore to point in time will still occur, just using all available log backups

    .PARAMETER DatabaseName
        A string array of Database Names that you want to filter to

    .PARAMETER ServerName
        A string array of Server Names that you want to filter

    .PARAMETER ContinuePoints
        The Output of Get-RestoreContinuableDatabase while provides 'Database',redo_start_lsn,'FirstRecoveryForkID' values. Used to filter backups to continue a restore on a database
        Sets IgnoreDiffs, and also filters databases to only those within the ContinuePoints object, or the ContinuePoints object AND DatabaseName if both specified

    .PARAMETER LastRestoreType
        The Output of Get-DbaDbRestoreHistory -last
        This is used to check the last type of backup to a database to see if a differential backup can be restored

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup, Restore
        Author:Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Select-DbaBackupInformation

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1)

        Returns all backups needed to restore all the backups in \\server1\backups$ to 1 hour ago

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -DatabaseName ProdFinance

        Returns all the backups needed to restore Database ProdFinance to an hour ago

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreLogs

        Returns all the backups in \\server1\backups$ to restore to as close prior to 1 hour ago as can be managed with only full and differential backups

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreDiffs

        Returns all the backups in \\server1\backups$ to restore to 1 hour ago using only Full and Diff backups.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object]$BackupHistory,
        [DateTime]$RestoreTime = (Get-Date).addmonths(1),
        [switch]$IgnoreLogs,
        [switch]$IgnoreDiffs,
        [string[]]$DatabaseName,
        [string[]]$ServerName,
        [object]$ContinuePoints,
        [object]$LastRestoreType,
        [switch]$EnableException
    )
    begin {
        $InternalHistory = @()
        $IgnoreFull = $false
        if ((Test-Bound -ParameterName ContinuePoints) -and $null -ne $ContinuePoints) {
            Write-Message -Message "ContinuePoints provided so setting up for a continue" -Level Verbose
            $IgnoreFull = $true
            $Continue = $True
            if (Test-Bound -ParameterName DatabaseName) {
                $DatabaseName = $DatabaseName | Where-Object { $_ -in ($ContinuePoints | Select-Object -Property Database).Database }

                $DroppedDatabases = $DatabaseName | Where-Object { $_ -notin ($ContinuePoints | Select-Object -Property Database).Database }
                if ($null -ne $DroppedDatabases) {
                    Write-Message -Message "$($DroppedDatabases.join(',')) filtered out as not in ContinuePoints" -Level Verbose
                }
            } else {
                $DatabaseName = ($ContinuePoints | Select-Object -Property Database).Database
            }
        }
    }
    process {
        $internalHistory += $BackupHistory
    }

    end {
        ForEach ($History in $InternalHistory) {
            if ("RestoreTime" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'RestoreTime' -Type NoteProperty -Value $RestoreTime
            }
        }
        if ((Test-Bound -ParameterName DatabaseName) -and '' -ne $DatabaseName) {
            Write-Message -Message "Filtering by DatabaseName" -Level Verbose
            #  $InternalHistory = $InternalHistory | Where-Object {$_.Database -in $DatabaseName}
        }

        # Check for AGs
        if (Test-Bound -ParameterName ServerName) {
            if (($InternalHistory | Where-Object { $_.AvailabilityGroupName -ne '' }).count -ne 0) {
                Write-Message -Level Verbose -Message 'Dealing with Availabilitygroups'
                $InternalHistory = $InternalHistory | Where-Object { $_.AvailabilityGroupName -in $servername }
            } else {
                Write-Message -Message "Filtering by ServerName" -Level Verbose
                $InternalHistory = $InternalHistory | Where-Object { $_.InstanceName -in $servername }
            }
        }

        $Databases = ($InternalHistory | Select-Object -Property Database -unique).Database
        if ($continue -and $Databases.count -gt 1 -and $DatabaseName.count -gt 1) {
            Stop-Function -Message "Cannot perform continuing restores on multiple databases with renames, exiting"
            return
        }


        ForEach ($Database in $Databases) {
            #Cope with restores renaming the db
            # $database = the name of database in the backups being scanned
            # $databasefilter = the name of the database the backups are being restore to/against
            if ($null -ne $DatabaseName) {
                $databasefilter = $DatabaseName
            } else {
                $databasefilter = $database
            }

            if ($true -eq $Continue) {
                #Test if Database is in a continuing state and the LSN to continue from:
                if ($Databasefilter -in ($ContinuePoints | Select-Object -Property Database).Database) {
                    Write-Message -Message "$Database in ContinuePoints, will attempt to continue" -Level verbose
                    $IgnoreFull = $True
                    #Check what the last backup restored was
                    if (($LastRestoreType | Where-Object { $_.Database -eq $Databasefilter }).RestoreType -eq 'log') {
                        #log Backup last restored, so diffs cannot be used
                        $IgnoreDiffs = $true
                    } else {
                        #Last restore was a diff or full, so can restore diffs or logs
                        $IgnoreDiffs = $false
                    }
                } else {
                    Write-Message -Message "$Database not in ContinuePoints, will attempt normal restore" -Level Warning
                }
            }

            $dbhistory = @()
            $DatabaseHistory = $internalhistory | Where-Object { $_.Database -eq $Database }
            #For a standard restore, work out the full backup
            if ($false -eq $IgnoreFull) {
                $Full = $DatabaseHistory | Where-Object { $_.Type -in ('Full', 'Database') -and $_.End -le $RestoreTime } | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                if ($full.Fullname) {
                    $full.Fullname = ($DatabaseHistory | Where-Object { $_.Type -in ('Full', 'Database') -and $_.BackupSetID -eq $Full.BackupSetID }).Fullname
                } else {
                    Stop-Function -Message "Fullname property not found. This could mean that a full backup could not be found or the command must be re-run with the -Continue switch."
                    return
                }
                $dbHistory += $full
            } elseif ($true -eq $IgnoreFull -and $false -eq $IgnoreDiffs) {
                #Fake the Full backup
                Write-Message -Message "Continuing, so setting a fake full backup from the existing database"
                $Full = [PsCustomObject]@{
                    CheckpointLSN = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).differential_base_lsn
                }
            }

            if ($false -eq $IgnoreDiffs) {
                Write-Message -Message "processing diffs" -Level Verbose
                $Diff = $DatabaseHistory | Where-Object { $_.Type -in ('Differential', 'Database Differential') -and $_.End -le $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN } | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                if ($null -ne $Diff) {
                    if ($Diff.FullName) {
                        $Diff.FullName = ($DatabaseHistory | Where-Object { $_.Type -in ('Differential', 'Database Differential') -and $_.BackupSetID -eq $diff.BackupSetID }).Fullname
                    } else {
                        Stop-Function -Message "Fullname property not found. This could mean that a full backup could not be found or the command must be re-run with the -Continue switch."
                        return
                    }
                    $dbhistory += $Diff
                }
            }

            #Sort out the LSN for the log restores
            if ($null -ne ($dbHistory | Sort-Object -Property LastLsn -Descending | Select-Object -First 1).lastLsn) {
                #We have history so use this
                [bigint]$LogBaseLsn = ($dbHistory | Sort-Object -Property LastLsn -Descending | Select-Object -First 1).lastLsn.ToString()
                $FirstRecoveryForkID = $Full.FirstRecoveryForkID
                Write-Message -Level Verbose -Message "Found LogBaseLsn: $LogBaseLsn and FirstRecoveryForkID: $FirstRecoveryForkID"
            } else {
                Write-Message -Message "No full or diff, so attempting to pull from Continue informmation" -Level Verbose
                try {
                    [bigint]$LogBaseLsn = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).redo_start_lsn
                    $FirstRecoveryForkID = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).FirstRecoveryForkID
                    Write-Message -Level Verbose -Message "Found LogBaseLsn: $LogBaseLsn and FirstRecoveryForkID: $FirstRecoveryForkID from Continue information"
                } catch {
                    Stop-Function -Message "Failed to find LSN or RecoveryForkID for $DatabaseFilter" -Category InvalidOperation -Target $DatabaseFilter
                }
            }

            if ($false -eq $IgnoreLogs) {
                $FilteredLogs = $DatabaseHistory | Where-Object { $_.Type -in ('Log', 'Transaction Log') -and $_.Start -lt $RestoreTime -and $_.LastLSN -ge $LogBaseLsn -and $_.FirstLSN -ne $_.LastLSN } | Sort-Object -Property LastLsn, FirstLsn
                $GroupedLogs = $FilteredLogs | Group-Object -Property BackupSetID
                ForEach ($Group in $GroupedLogs) {
                    $Log = $Group.group[0]
                    $Log.FullName = $Group.group.fullname
                    $dbhistory += $Log
                }
                # Get Last T-log

                $lastLog = $DatabaseHistory | Where-Object { $_.Type -in ('Log', 'Transaction Log') -and $_.End -ge $RestoreTime -and $_.DatabaseBackupLSN -ge $Full.CheckpointLSN } | Sort-Object -Property LastLsn, FirstLsn | Select-Object -First 1
                if ($null -ne $lastlog) {
                    $lastLog.FullName = ($DatabaseHistory | Where-Object { $_.BackupSetID -eq $lastLog.BackupSetID }).Fullname
                }
                $dbHistory += $lastLog
            }
            $dbhistory
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBb2Ak3v7CxV6o6
# LiaPiIihp/8NvIvDBpoeBJuLu1i70KCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDjEWXWtAoei9yYyYp9oxEdKGweaquuac/j
# V/zW79ATfDANBgkqhkiG9w0BAQEFAASCAQBB42jQc+bsRWODa0b7WP6pQDAqDT9j
# 2qWiP3L1RnRN5qcQIElk4ZZ7CkuGWFPr9zvb86AwjdnGiVg5k8tjyYwlFzFkFRYt
# kmvsRjAocAxtkitSRGJ3GzSv3EGKM05fauvdX1tDGm1fnUZIqFGoEd+JQTMftJOH
# juyKl43MD09aDSuaEYX9h18GHYU9Jh7MSP4mYGPLvCy1MNgT9KmsnYdKphN1PBxZ
# ETWEJoDtkt0gNh+n5djIQX1LjWsB7WgG+bql4GHr8KHSxszIR3Osnd365pBzSupb
# tc3bNGCxjs4oT+eoOuuAxbROq9IVThwHioenbMyWOpS+ADjqNA4CM9nGoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDM1M1owLwYJKoZIhvcNAQkEMSIEINt3FCpH
# Zd3oIbfWfHmZpfslkNYiI5BPtB33id37hShWMA0GCSqGSIb3DQEBAQUABIICAIKY
# p53djKh5WGKIXG2nHoWisyaGyDkCPJlRS+qnSkkqj3JbuCY2G9tMy5HglXim+4Ix
# 91QSyhPpBenbaLxbQMKwUb3rW3mSyKqUYcTFx0Eorem5e+QnyVcgwX5jZkbgFCqb
# KDKSAuVHaYbgorSiR1UcNwdrIqRE8o+U4J9RSGWlrncT52gdMDhyPBr5nxKoPQ3C
# 1jk8SU2PNY6GANvAIvtPJsiUtUfkyuJ6kGJqr6R14L0uT6SesACABgVzcP7Bjy52
# zSJMJ8JNqogmusskEtsZRFG/aNcStG9oJ0Ds1eOfS5WTFpNfaBFN1VXVqMFdNvlx
# cwwgUaHuxJ2xHX/ZYXqpxgImJeMjsSpT+pkkhMibVluDJ67u75Llm2V2ySDItPGa
# J027JHy2qv5W0a3QQgQ5Nydk6bukCdnTzIi43VqAp3P8KTJ55XhL6zxg7JkEHZz+
# vY45aehlTmdJLf1gXHNhofcSOCcOUyMfGVL+zE9lzSxY6D8s7i8o/0rm2Z1Ohti2
# gXaNEpCUJiYQeDs3eARajlJRvFSuKdVBlsZlV7za/dJ77bT+8dHNu+XkTvl038X5
# A2uvFaOlK+ieyTowecLLyMhtugV3RCMUUBVwNAdBF2qXI8bWsqJmHq1cqy+wq+Oe
# cmGv8IiE75g9zn2e/cYqLNV0NWuBSIutx302FtNj
# SIG # End signature block
