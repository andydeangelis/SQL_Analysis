function Move-DbaDbFile {
    <#
    .SYNOPSIS
        Moves database files from one local drive or folder to another.

    .DESCRIPTION
        Moves database files from one local drive or folder to another.
        It will put database offline, update metadata and set it online again.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database to be moved.

    .PARAMETER FileToMove
        Pass a hashtable that contains a list of database files and their destination path.
        Key and value should be the logical name and then the path (e.g. 'db1_log' = 'D:\mssql\logs')

    .PARAMETER FileType
        Define the file type to move; accepted values: Data, Log or Both.
        Default value: Both
        Exclusive, cannot be used in conjunction with FileToMove.

    .PARAMETER FileDestination
        Destination directory of the database file(s).

    .PARAMETER DeleteAfterMove
        Remove the source database file(s) after the successful move operation.

    .PARAMETER FileStructureOnly
        Return a hashtable of the Database file structure.
        Modifying the hashtable it can then be utilized with the FileToMove parameter

    .PARAMETER Force
        Database(s) is set offline as part of the move process, this will utilize WITH ROLLBACK IMMEDIATE and rollback any open transaction running against the database(s).

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Move, File
        Author: Cláudio Silva (@claudioessilva), claudioeesilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Move-DbaDbFile

    .EXAMPLE
        PS C:\> Move-DbaDbFile -SqlInstance sql2017 -Database dbatools -FileType Data -FileDestination "D:\DATA2"

        Copy all data files of dbatools database on sql2017 instance to the "D:\DATA2" path.
        Before it puts database offline and after copy each file will update database metadata and it ends by set the database back online

    .EXAMPLE
        PS C:\> $fileToMove=@{
        >> 'dbatools'='D:\DATA3'
        >> 'dbatools_log'='D:\LOG2'
        >> }
        PS C:\> Move-DbaDbFile -SqlInstance sql2019 -Database dbatools -FileToMove $fileToMove

        Declares a hashtable that says for each logical file the new path.
        Copy each dbatools database file referenced on the hashtable on the sql2019 instance from the current location to the new mentioned location (D:\DATA3 and D:\LOG2 paths).
        Before it puts database offline and after copy each file will update database metadata and it ends by set the database back online

    .EXAMPLE
        PS C:\> Move-DbaDbFile -SqlInstance sql2017 -Database dbatools -FileStructureOnly

        Shows the current database file structure (without filenames). Example: 'dbatools'='D:\Data'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [parameter(ParameterSetName = "All")]
        [ValidateSet('Data', 'Log', 'Both')]
        [string]$FileType,
        [parameter(ParameterSetName = "All")]
        [string]$FileDestination,
        [parameter(ParameterSetName = "Detailed")]
        [hashtable]$FileToMove,
        [parameter(ParameterSetName = "All")]
        [parameter(ParameterSetName = "Detailed")]
        [switch]$DeleteAfterMove,
        [parameter(ParameterSetName = "FileStructure")]
        [switch]$FileStructureOnly,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ((Test-Bound -ParameterName FileType) -and (-not(Test-Bound -ParameterName FileDestination))) {
            Stop-Function -Category InvalidArgument -Message "FileDestination parameter is missing. Quitting."
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if ((-not $FileType) -and (-not $FileToMove) -and (-not $FileStructureOnly) ) {
            Stop-Function -Message "You must specify at least one of -FileType or -FileToMove or -FileStructureOnly to continue"
            return
        }

        if ($Database -in @("master", "model", "msdb", "tempdb")) {
            Stop-Function -Message "System database detected as input. The command does not support moving system databases. Quitting."
            return
        }

        try {
            try {
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }

            switch ($FileType) {
                'Data' { $fileTypeFilter = 0 }
                'Log' { $fileTypeFilter = 1 }
                'Both' { $fileTypeFilter = -1 }
                default { $fileTypeFilter = -1 }
            }

            $dbStatus = (Get-DbaDbState -SqlInstance $server -Database $Database).Status
            if ($dbStatus -ne 'ONLINE') {
                Write-Message -Level Verbose -Message "Database $Database is not ONLINE. Getting file strucutre from sys.master_files."
                if ($fileTypeFilter -eq -1) {
                    $DataFiles = Get-DbaDbPhysicalFile -SqlInstance $server | Where-Object Name -eq $Database | Select-Object LogicalName, PhysicalName
                } else {
                    $DataFiles = Get-DbaDbPhysicalFile -SqlInstance $server | Where-Object { $_.Name -eq $Database -and $_.Type -eq $fileTypeFilter } | Select-Object LogicalName, PhysicalName
                }
            } else {
                if ($fileTypeFilter -eq -1) {
                    $DataFiles = Get-DbaDbFile -SqlInstance $server -Database $Database | Select-Object LogicalName, PhysicalName
                } else {
                    $DataFiles = Get-DbaDbFile -SqlInstance $server -Database $Database | Where-Object Type -eq $fileTypeFilter | Select-Object LogicalName, PhysicalName
                }
            }

            if (@($DataFiles).Count -gt 0) {

                if ($FileStructureOnly) {
                    $fileStructure = "`$fileToMove=@{`n"
                    foreach ($file in $DataFiles) {
                        $fileStructure += "`t'$($file.LogicalName)'='$(Split-Path -Path $file.PhysicalName -Parent)'`n"
                    }
                    $fileStructure += "}"
                    Write-Output $fileStructure
                    return
                }

                if ($FileDestination) {
                    $DataFilesToMove = $DataFiles | Select-Object -ExpandProperty LogicalName
                } else {
                    $DataFilesToMove = $FileToMove.Keys
                }

                if ($dbStatus -ne "Offline") {
                    if ($PSCmdlet.ShouldProcess($database, "Setting database $Database offline")) {
                        try {
                            $SetState = Set-DbaDbState -SqlInstance $server -Database $Database -Offline -Force:$Force
                            if ($SetState.Status -ne 'Offline') {
                                Stop-Function -Message "Setting database Offline failed!"
                                return
                            } else {
                                Write-Message -Level Verbose -Message "Database $Database was set to Offline status."
                            }
                        } catch {
                            Stop-Function -Message "Setting database Offline failed!" -ErrorRecord $_ -Target $SqlInstance
                            return
                        }
                    }
                }

                $locally = $false
                if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                    # locally ran so we can just use Start-BitsTransfer
                    $ComputerName = $server.ComputerName
                    $locally = $true
                } else {
                    # let's start checking if we can access .ComputerName
                    $testPS = $false
                    if ($SqlCredential) {
                        # why does Test-PSRemoting require a Credential param ? this is ugly...
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -Credential $SqlCredential -ErrorAction Stop
                    } else {
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -ErrorAction Stop
                    }
                    if (-not ($testPS)) {
                        # let's try to resolve it to a more qualified name, without "cutting" knowledge about the domain (only $server.Name possibly holds the complete info)
                        $Resolved = (Resolve-DbaNetworkName -ComputerName $server.Name).FullComputerName
                        if ($SqlCredential) {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -Credential $SqlCredential -ErrorAction Stop
                        } else {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -ErrorAction Stop
                        }
                        if ($testPS) {
                            $ComputerName = $Resolved
                        }
                    } else {
                        $ComputerName = $server.ComputerName
                    }
                }

                # if we don't have remote access ($ComputerName is null) we can fallback to admin shares if they're available
                if ($null -eq $ComputerName) {
                    $ComputerName = $server.ComputerName
                }

                # Test if defined paths are accesible by the instance
                $testPathResults = @()
                if ($FileDestination) {
                    if (-not (Test-DbaPath -SqlInstance $server -Path $FileDestination)) {
                        $testPathResults += $FileDestination
                    }
                } else {
                    foreach ($filePath in $FileToMove.Keys) {
                        if (-not (Test-DbaPath -SqlInstance $server -Path $FileToMove[$filePath])) {
                            $testPathResults += $FileToMove[$filePath]
                        }
                    }
                }
                if (@($testPathResults).Count -gt 0) {
                    Stop-Function -Message "The path(s):`r`n $($testPathResults -join [Environment]::NewLine)`r`n is/are not accessible by the instance. Confirm if it/they exists."
                    return
                }

                foreach ($LogicalName in $DataFilesToMove) {
                    $physicalName = $DataFiles | Where-Object LogicalName -eq $LogicalName | Select-Object -ExpandProperty PhysicalName

                    if ($FileDestination) {
                        $destinationPath = $FileDestination
                    } else {
                        $destinationPath = $FileToMove[$LogicalName]
                    }
                    $fileName = [IO.Path]::GetFileName($physicalName)
                    $destination = "$destinationPath\$fileName"

                    if ($physicalName -ne $destination) {
                        if ($locally) {
                            if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalName to $destination using Bits locally on $ComputerName")) {
                                try {
                                    Start-BitsTransfer -Source $physicalName -Destination $destination -ErrorAction Stop
                                } catch {
                                    try {
                                        Write-Message -Level Warning -Message "WARN: Could not copy file using Bits transfer. $_"
                                        Write-Message -Level Verbose -Message "Trying with Copy-Item"
                                        Copy-Item -Path $physicalName -Destination $destination -ErrorAction Stop

                                    } catch {
                                        $failed = $true

                                        Write-Message -Level Important -Message "ERROR: Could not copy file. $_"
                                    }
                                }
                            }
                        } else {
                            # Use Remoting PS to run the command on the server
                            try {
                                if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalName to $destination using remote PS on $ComputerName")) {
                                    $scriptBlock = {
                                        $physicalName = $args[0]
                                        $destination = $args[1]

                                        # Version 1 will yield - "The remote use of BITS is not supported." when using Remoting PS
                                        if ((Get-Command -Name Start-BitsTransfer).Version.Major -gt 1) {
                                            Write-Verbose "Try copying using Start-BitsTransfer."
                                            Start-BitsTransfer -Source $physicalName -Destination $destination -ErrorAction Stop
                                        } else {
                                            Write-Verbose "Can't use Bits. Using Copy-Item instead"
                                            Copy-Item -Path $physicalName -Destination $destination -ErrorAction Stop
                                        }

                                        Get-Acl -Path $physicalName | Set-Acl $destination
                                    }
                                    Invoke-Command2 -ComputerName $ComputerName -Credential $SqlCredential -ScriptBlock $scriptBlock -ArgumentList $physicalName, $destination
                                }
                            } catch {
                                # Try using UNC paths
                                try {
                                    $physicalNameUNC = Join-AdminUnc -ServerName $ComputerName -Filepath $physicalName
                                    $destinationUNC = Join-AdminUnc -ServerName $ComputerName -Filepath $destination

                                    if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalNameUNC to $destinationUNC using UNC path for $ComputerName")) {

                                        try {
                                            Write-Message -Level Verbose -Message "Try copying using Start-BitsTransfer with UNC paths."
                                            Start-BitsTransfer -Source $physicalNameUNC -Destination $destinationUNC -ErrorAction Stop
                                        } catch {
                                            Write-Message -Level Warning -Message "Did not work using Start-BitsTransfer. ERROR: $_"
                                            Write-Message -Level Verbose -Message "Trying using Copy-Item with UNC paths instead."
                                            Copy-Item -Path $physicalNameUNC -Destination $destinationUNC -ErrorAction Stop
                                        }

                                        # Force the copy of the file's ACL
                                        Get-Acl -Path $physicalNameUNC | Set-Acl $destinationUNC

                                        Write-Message -Level Verbose -Message "File $fileName was copied successfully"
                                    }
                                } catch {
                                    $failed = $true

                                    Write-Message -Level Important -Message "ERROR: Could not copy file. $_"
                                }
                            }

                            Write-Message -Level Verbose -Message "File $fileName was copied successfully"
                        }

                        if (-not $failed) {
                            $query = "ALTER DATABASE [$Database] MODIFY FILE (name=[$LogicalName], filename='$destination'); "

                            if ($PSCmdlet.ShouldProcess($Database, "Executing ALTER DATABASE query - $query")) {
                                # Change database file path
                                $server.Databases["master"].Query($query)
                            }

                            if ($DeleteAfterMove) {
                                try {
                                    if ($PSCmdlet.ShouldProcess($database, "Deleting source file $physicalName")) {
                                        if ($locally) {
                                            Remove-Item -Path $physicalName -ErrorAction Stop
                                        } else {
                                            $scriptBlock = {
                                                $source = $args[0]
                                                Remove-Item -Path $source -ErrorAction Stop
                                            }
                                            Invoke-Command2 -ComputerName $ComputerName -Credential $SqlCredential -ScriptBlock $scriptBlock -ArgumentList $physicalName
                                        }
                                    }
                                } catch {
                                    [PSCustomObject]@{
                                        Instance             = $SqlInstance
                                        Database             = $Database
                                        LogicalName          = $LogicalName
                                        Source               = $physicalName
                                        Destination          = $destination
                                        Result               = "Success"
                                        DatabaseFileMetadata = "Updated"
                                        SourceFileDeleted    = $false
                                    }

                                    Stop-Function -Message "ERROR:" -ErrorRecord $_
                                }
                            }

                            [PSCustomObject]@{
                                Instance             = $SqlInstance
                                Database             = $Database
                                LogicalName          = $LogicalName
                                Source               = $physicalName
                                Destination          = $destination
                                Result               = "Success"
                                DatabaseFileMetadata = "Updated"
                                SourceFileDeleted    = $true
                            }
                        } else {
                            [PSCustomObject]@{
                                Instance             = $SqlInstance
                                Database             = $Database
                                LogicalName          = $LogicalName
                                Source               = $physicalName
                                Destination          = $destination
                                Result               = "Failed"
                                DatabaseFileMetadata = "N/A"
                                SourceFileDeleted    = "N/A"
                            }
                        }
                    } else {
                        Write-Message -Level Verbose -Message "File $fileName already exists on $destination. Skipping."
                        [PSCustomObject]@{
                            Instance             = $SqlInstance
                            Database             = $Database
                            LogicalName          = $LogicalName
                            Source               = $physicalName
                            Destination          = $destination
                            Result               = "Already exists. Skipping"
                            DatabaseFileMetadata = "N/A"
                            SourceFileDeleted    = "N/A"
                        }
                    }
                }

                if ($PSCmdlet.ShouldProcess($Database, "Setting database Online")) {
                    try {
                        $SetState = Set-DbaDbState -SqlInstance $server -Database $Database -Online -ErrorVariable dbstate
                        if ($SetState.Status -ne 'Online') {
                            Stop-Function -Message "$($SetState.Notes)! : $($dbstate.Exception.InnerException.InnerException.InnerException.InnerException)."
                        } else {
                            Write-Message -Level Verbose -Message "Database is online!"
                        }
                    } catch {
                        Stop-Function -Message "Setting database online failed! : $($_.Exception.InnerException.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                    }
                }
            } else {
                Write-Message -Level Warning -Message "We could not get any files for database $Database!"
            }
        } catch {
            Stop-Function -Message "ERROR:" -ErrorRecord $_
        }
    }
}

# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDpwclO6elc1CXN
# S2Y6t6tQyS0JNdrkMQrJq+5triTN9aCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDbTFeoBVWb9moOs3wUZuC323w3RJccFKgO
# HImDiKrQNjANBgkqhkiG9w0BAQEFAASCAQBKp2acp//UMj2QIbF/6D8e1Y/VzepM
# fGm1kfaqFamenK2qE3l2h23JIZMYRYHWIjshJpChmKViJex/RFdKOvj/2DaRSMP0
# 7H5aawl9sxvAcv+k2FeT6Oi47r0opMWPV7tXEsvViYiADJfc6nQOFs8h76Cp4N+v
# Y01iiwS8lVnxyyXvfkl1mOQU/hmzurgev/AwrRYX3CEKc/4IB3XK6Yt3XAJAzzlm
# pi5pk78SxkKbaF+dAwltNeZQCxJNzWxWI1RRGUPfbi/O4zD6FxBEDj7mqtCY1l1x
# YR2k7lgoS1an2czCg6MYfJFlnapaowQ/naWZPzCx4vbiz3nn/zr2Fej4oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMzMVowLwYJKoZIhvcNAQkEMSIEIOe7E0MK
# fQW1DigpCj1evMq3Ktkp39GhsrhVoVRhNlr/MA0GCSqGSIb3DQEBAQUABIICALHw
# drvxBdXYqnUDVN1M/krOgPAEEAK5kMtuN2S6eC3BUoZUoE5pcaYe1X17isHpHm/A
# XKgNNrIxsVTLQZ3UZaDS99Iax8jw+w58whpUmr4EhYccPIZCK1ltLGRH+I0euDh5
# zlz5v1/vWtJaPmAHGDDTmGJg2oH08zAM/LU2u5LlU8iynCQtKDsK3joOp2r3nF0F
# ucnZzfdbnDKrfI3YvEEdd6ZqzOdkB22suCs70hdFmXi6dodi4Moulqc7KpNllqC0
# HDKivTFEYp3HuNpVlEF2eLcGYvsHeHkguthoH/0qWiNiSWXv8KCbQN9K5q+F65fb
# 4d4eFUF+d9xV5nZ73jHnAtO35NtpF6SLV1b5t2Av90I9y1UqmUYua7VkEgKTlHg2
# xAteqchNHPvgEeQYFOHOCN/ZW8sLOxMBYDDypwx7x4tSWYfodVoJcx6bLW+GpVFR
# Hdkhy+7l/QXChVND1gfY22W6JyjBRvC9jv4wW1ShJcrYbC8xJ27uPJmFEQLo4w/Z
# tSZ+9+SZMkPzbvLV/3KkcJYo0tCvoY55ArZ/nDZuuj3csrHvENjQfjr9wo+6PavA
# Hf+uvSZNCDu496GqJadLyfCieU/ic7cM01aeOhZSCUrjDO6zCqol6s47l04RtnfG
# gswBOBvAFgoDLfL7h27tNts5lQC26izPQoB+rWdu
# SIG # End signature block
