function New-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Creates database snapshots

    .DESCRIPTION
        Creates database snapshots without hassles

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AllDatabases
        Creates snapshot for all eligible databases

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step.

    .PARAMETER Name
        The specific snapshot name you want to create. Works only if you target a single database. If you need to create multiple snapshot,
        you must use the NameSuffix parameter

    .PARAMETER NameSuffix
        When you pass a simple string, it'll be appended to use it to build the name of the snapshot. By default snapshots are created with yyyyMMdd_HHmmss suffix
        You can also pass a standard placeholder, in which case it'll be interpolated (e.g. '{0}' gets replaced with the database name)

    .PARAMETER Path
        Snapshot files will be created here (by default the file structure will be created in the same folder as the base db)

    .PARAMETER InputObject
        Allows Piping from Get-DbaDatabase

    .PARAMETER Force
        Databases with Filestream FG can be snapshotted, but the Filestream FG is marked offline
        in the snapshot. To create a "partial" snapshot, you need to pass -Force explicitly

        NB: You can't then restore the Database from the newly-created snapshot.
        For details, check https://msdn.microsoft.com/en-us/library/bb895334.aspx

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Snapshot, Restore, Database
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbSnapshot

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Creates snapshot for HR and Accounting, returning a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status, Notes

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR -Name HR_snap

        Creates snapshot named "HR_snap" for HR

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR -NameSuffix 'fool_{0}_snap'

        Creates snapshot named "fool_HR_snap" for HR

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting -Path F:\snapshotpath

        Creates snapshots for HR and Accounting databases, storing files under the F:\snapshotpath\ dir

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database df | New-DbaDbSnapshot

        Creates a snapshot for the database df on sql2016

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [string]$Name,
        [string]$NameSuffix,
        [string]$Path,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $NoSupportForSnap = @('model', 'master', 'tempdb')
        # Evaluate the default suffix here for naming consistency
        $DefaultSuffix = (Get-Date -Format "yyyyMMdd_HHmmss")
        if ($NameSuffix.Length -gt 0) {
            #Validate if Name can be interpolated
            try {
                $null = $NameSuffix -f 'some_string'
            } catch {
                Stop-Function -Message "NameSuffix parameter must be a template only containing one parameter {0}" -ErrorRecord $_
            }
        }

        function Resolve-SnapshotError($server) {
            $errHelp = ''
            $CurrentEdition = $server.Edition.ToLowerInvariant()
            $CurrentVersion = $server.Version.Major * 1000000 + $server.Version.Minor * 10000 + $server.Version.Build
            if ($server.Version.Major -lt 9) {
                $errHelp = 'Not supported before 2005'
            }
            if ($CurrentVersion -lt 12002000 -and $errHelp.Length -eq 0) {
                if ($CurrentEdition -notmatch '.*enterprise.*|.*developer.*|.*datacenter.*') {
                    $errHelp = 'Supported only for Enterprise, Developer or Datacenter editions'
                }
            }
            $message = ""
            if ($errHelp.Length -gt 0) {
                $message += "Please make sure your version supports snapshots : ($errHelp)"
            } else {
                $message += "This module can't tell you why the snapshot creation failed. Feel free to report back to dbatools what happened"
            }
            Write-Message -Level Warning -Message $message
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $Database -and $AllDatabases -eq $false) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue" -EnableException $EnableException
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            #Checks for path existence, left the length test because test-bound wasn't working for some reason
            if ($Path.Length -gt 0) {
                if (!(Test-DbaPath -SqlInstance $server -Path $Path)) {
                    Stop-Function -Message "$instance cannot access the directory $Path" -ErrorRecord $_ -Target $instance -Continue -EnableException $EnableException
                }
            }

            if ($AllDatabases) {
                $dbs = $server.Databases
            }

            if ($Database) {
                $dbs = $server.Databases | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $server.Databases | Where-Object { $ExcludeDatabase -notcontains $_.Name }
            }

            ## double check for gotchas
            foreach ($db in $dbs) {
                if ($db.IsMirroringEnabled) {
                    $InputObject += $db
                } elseif ($db.IsDatabaseSnapshot) {
                    Write-Message -Level Warning -Message "$($db.name) is a snapshot, skipping"
                } elseif ($db.name -in $NoSupportForSnap) {
                    Write-Message -Level Warning -Message "$($db.name) snapshots are prohibited"
                } elseif ($db.IsAccessible -ne $true) {
                    Write-Message -Level Verbose -Message "$($db.name) is not accessible, skipping"
                } else {
                    $InputObject += $db
                }
            }

            if ($InputObject.Count -gt 1 -and $Name) {
                Stop-Function -Message "You passed the Name parameter that is fixed but selected multiple databases to snapshot: use the NameSuffix parameter" -Continue -EnableException $EnableException
            }
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            # In case stuff is piped in
            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "SQL Server version 9 required - $server not supported" -Continue
            }

            if ($NameSuffix.Length -gt 0) {
                $SnapName = $NameSuffix -f $db.Name
                if ($SnapName -eq $NameSuffix) {
                    #no interpolation, just append
                    $SnapName = '{0}{1}' -f $db.Name, $NameSuffix
                }
            } elseif ($Name.Length -gt 0) {
                $SnapName = $Name
            } else {
                $SnapName = "{0}_{1}" -f $db.Name, $DefaultSuffix
            }
            if ($SnapName -in $server.Databases.Name) {
                Write-Message -Level Warning -Message "A database named $SnapName already exists, skipping"
                continue
            }
            $all_FSD = $db.FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup'
            $all_MMO = $db.FileGroups | Where-Object FileGroupType -eq 'MemoryOptimizedDataFileGroup'
            $has_FSD = $all_FSD.Count -gt 0
            $has_MMO = $all_MMO.Count -gt 0
            if ($has_MMO) {
                Write-Message -Level Warning -Message "MEMORY_OPTIMIZED_DATA detected, snapshots are not possible"
                continue
            }
            if ($has_FSD -and $Force -eq $false) {
                Write-Message -Level Warning -Message "Filestream detected, skipping. You need to specify -Force. See Get-Help for details"
                continue
            }
            $snapType = "db snapshot"
            if ($has_FSD) {
                $snapType = "partial db snapshot"
            }
            If ($PSCmdlet.ShouldProcess($server, "Create $snapType $SnapName of $($db.Name)")) {
                $CustomFileStructure = @{ }
                $counter = 0
                foreach ($fg in $db.FileGroups) {
                    $CustomFileStructure[$fg.Name] = @()
                    if ($fg.FileGroupType -eq 'FileStreamDataFileGroup') {
                        Continue
                    }
                    foreach ($file in $fg.Files) {
                        $counter += 1
                        # Linux can't handle windows paths, so split it
                        $basename = [IO.Path]::GetFileNameWithoutExtension((Split-Path $file.FileName -Leaf))
                        $basePath = Split-Path $file.FileName -Parent
                        # change path if specified
                        if ($Path.Length -gt 0) {
                            $basePath = $Path
                        }

                        # we need to avoid cases where basename is the same for multiple FG
                        $fName = [IO.Path]::Combine($basePath, ("{0}_{1}_{2:0000}_{3:000}" -f $basename, $DefaultSuffix, (Get-Date).MilliSecond, $counter))
                        # fixed extension is hardcoded as "ss", which seems a "de-facto" standard
                        $fName = [IO.Path]::ChangeExtension($fName, "ss")
                        Write-Message -Level Debug -Message "$fName"

                        # change slashes for Linux, change slashes for Windows
                        if ($server.HostPlatform -eq 'Linux') {
                            $fName = $fName.Replace("\", "/")
                        } else {
                            $fName = $fName.Replace("/", "\")
                        }
                        $CustomFileStructure[$fg.Name] += @{ 'name' = $file.name; 'filename' = $fName }
                    }
                }

                $SnapDB = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $SnapName
                $SnapDB.DatabaseSnapshotBaseName = $db.Name

                foreach ($fg in $CustomFileStructure.Keys) {
                    $SnapFG = New-Object -TypeName Microsoft.SqlServer.Management.Smo.FileGroup $SnapDB, $fg
                    $SnapDB.FileGroups.Add($SnapFG)
                    foreach ($file in $CustomFileStructure[$fg]) {
                        $SnapFile = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DataFile $SnapFG, $file['name'], $file['filename']
                        $SnapDB.FileGroups[$fg].Files.Add($SnapFile)
                    }
                }

                # we're ready to issue a Create, but SMO is a little uncooperative here
                # there are cases we can manage and others we can't, and we need all the
                # info we can get both from testers and from users

                $sql = $SnapDB.Script()

                try {
                    $SnapDB.Create()
                    $server.Databases.Refresh()
                    Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                } catch {
                    try {
                        $server.Databases.Refresh()
                        if ($SnapName -notin $server.Databases.Name) {
                            # previous creation failed completely, snapshot is not there already
                            $null = $server.Query($sql[0])
                            $server.Databases.Refresh()
                            $SnapDB = Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                        } else {
                            $SnapDB = Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                        }

                        $Notes = @()
                        if ($db.ReadOnly -eq $true) {
                            $Notes += 'SMO is probably trying to set a property on a read-only snapshot, run with -Debug to find out and report back'
                        }
                        if ($has_FSD) {
                            #Variable marked as unused by PSScriptAnalyzer
                            #$Status = 'Partial'
                            $Notes += 'Filestream groups are not viable for snapshot'
                        }
                        $Notes = $Notes -Join ';'

                        $hints = @("Executing these commands led to a partial failure")
                        foreach ($stmt in $sql) {
                            $hints += $stmt
                        }

                        Write-Message -Level Debug -Message ($hints -Join "`n")

                        $SnapDB
                    } catch {
                        # Resolve-SnapshotError $server
                        $hints = @("Executing these commands led to a failure")
                        foreach ($stmt in $sql) {
                            $hints += $stmt
                        }
                        Write-Message -Level Debug -Message ($hints -Join "`n")

                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $SnapDB -Continue
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBgiYijQXyai+M2
# psoPRUBUnYrhl020JSXlTby5FzQkFqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAXctOFDUlWcFwpLCTkQMR7b1vmmonBrmjk
# OX0Yf8i//TANBgkqhkiG9w0BAQEFAASCAQCwD30pxEw7++wOSeMGaDflBjsd7j3/
# JI2eULH7xTzK7PQW0Fd/wUCNTCTe3DQ3e5+hUWDQ4I6Q2O4kGU2OFyrXgljnyuqY
# Ex1pUkcGRHFJ/LT8HP5pcbxFcVyhLW97kB3Xgn/0g2HqQ/lBK2ziLHL9IkrU8MgA
# 1rc2kteEzozL0jVyPc+o24AYBr5yPLCeAZEJ5U1JzY5s8v4uGhIcXs7JPUnsGh5v
# ea26zh1nECXRyNerfLd8UwoALZOwF+r12K3ENDOgBRATxTgQLorQ1oM6P2s8dOMI
# zN5zofUgxF5FMun0n67LQlN5Una6EBtL8OfaUlzyWQxEkH1bxgCJDlDSoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMzNlowLwYJKoZIhvcNAQkEMSIEIGDAgBha
# nbRchCjjiAbw6RxYtVjSS2xey6+a5BfD3JpnMA0GCSqGSIb3DQEBAQUABIICAJUQ
# 1XWpiH972ec7ihQCJKRSCtgCO6EzWfaLl1HSnD8dz5viXnMlMfWcg92a62nXo/S8
# R4opK8oQJ6CCkr5hc2LYlMbgQXyC071hn13D7ilE+WIucRz4dn0PrNL7TiU7ylib
# TtaTLdnfbsgO0WF6GXpnAvNDIkTGJp85lbtXnSCriNYJtvefOv7dbDneeUcHYGIH
# jFVlsJOq4MGoobOScmUVuC/AQtl9uSfwMkIZ61ZVX9CPiP8GGxH19xHfYp94F5K2
# vk60Op09TRxywXI4x7D6GLUDte0zmZv7ZZjCWbqEL7JeBeBiwD+RuITMyP3EBJC0
# G2llJwpIFMvNOpYyCL4V5xkSKB7kmsposZgHRrbsVUTnMluKSIgvo0IU6DiAqhLP
# TY62JQhNhSUOHVqOhe3YoYS85NDs6hFa2oEukFCvJ2mhctLI98vro9oRm3SZgGdX
# eYZXX03q+vIY1HystHD7QPxxU06157TigTIZe8EfkDBwGvKLaw49NwHyVx9exhVX
# xpLfYgV2pT+meWcFKZydRqSbs04AR+LCYWnQVrqV0vTA4eq0IFOgPFesLn3VKPg/
# tqdcq1X3MwRZhG/2FW+aGmPkjm/LhhG1X/bNjwAoZ+4BtzrIKEWym4knKGowVEr/
# qhSc8o9LDp2iRtxOd7+kOew3FySWi7WM4mRdLNlK
# SIG # End signature block
