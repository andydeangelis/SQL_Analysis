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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU6XilRloi52kHyUkk3jwC7Cho
# UqKgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTIwMDUxMjAwMDAwMFoXDTIzMDYw
# ODEyMDAwMFowVzELMAkGA1UEBhMCVVMxETAPBgNVBAgTCFZpcmdpbmlhMQ8wDQYD
# VQQHEwZWaWVubmExETAPBgNVBAoTCGRiYXRvb2xzMREwDwYDVQQDEwhkYmF0b29s
# czCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALy/Y3ur47++CAG2mOa1
# 6h8WjXjSTvcldDmw4PpAvOOCKNr6xyhg/FOYVIiaeq2N9kVaa5wBawOIxVWuj/rI
# aOxeYklQDugPkGUx0Ap+6KrjnnxgE6ONzQGnc1tjlka6N0KazD2WodEBWKXo/Vmk
# C/cP9PJVWroCMOwlj7GtEv2IxzxikPm2ICP5KxFK5PmrA+5bzcHJEeqRonlgMn9H
# zZkqHr0AU1egnfEIlH4/v6lry1t1KBF/bnDhl9g/L0icS+ychFVkx4OOO4a+qvT8
# xqvvdQjv3PQ1hbzTI3/tXOWu9XxGeeIdZjaJv16FmWKCnloSp1Xb9cVU9XhIpomz
# xH0CAwEAAaOCAcUwggHBMB8GA1UdIwQYMBaAFFrEuXsqCqOl6nEDwGD5LfZldQ5Y
# MB0GA1UdDgQWBBTwwKD7tgOAQ077Cdfd33qxy+OeIjAOBgNVHQ8BAf8EBAMCB4Aw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwdwYDVR0fBHAwbjA1oDOgMYYvaHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1jcy1nMS5jcmwwNaAzoDGGL2h0
# dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMEwG
# A1UdIARFMEMwNwYJYIZIAYb9bAMBMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3
# LmRpZ2ljZXJ0LmNvbS9DUFMwCAYGZ4EMAQQBMIGEBggrBgEFBQcBAQR4MHYwJAYI
# KwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBOBggrBgEFBQcwAoZC
# aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJ
# RENvZGVTaWduaW5nQ0EuY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQAD
# ggEBAI/N+XCVDB/WNqQSrKY85zScHGJjsXgXByYvsitMuG5vo+ODhlh+ILv0CTPl
# o2Wo75MnSSqCWR+c6xyN8pDPMPBxm2EtVmXzeKDMIudYyjxmT8PZ3hktj16wXCo8
# 2+65UOse+CHsfoMn/M9WbkQ4rSyWNPRRDodATC2i4flLyeuoIZnyMoz/4N4mWb6s
# IAYZ/tNXzm6qwCfkmoMSf9tcTUCXIbVDliJcUZLlJ/SpLg2KzDu9GtnpBzg3AG3L
# hwBiPMM8OLGitYjz4VU5RYox0vu1XyLf3f9fKTCxxwKy0EKntWdJk37i+DOMQlCq
# Xm5B/KyNxb2utv+qLGlyw9MphEcwggUwMIIEGKADAgECAhAECRgbX9W7ZnVTQ7Vv
# lVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0Rp
# Z2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBaFw0yODEw
# MjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNI
# QTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/lqJ3bMtdx
# 6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fTeyOU5JEj
# lpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqHCN8M9eJN
# YBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+bMt+dDk2
# DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLoLFH3c7y9
# hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIByTASBgNV
# HRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEF
# BQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRp
# Z2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDig
# NoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwAAgQwKjAo
# BggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAKBghghkgB
# hv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0jBBgwFoAU
# Reuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7sDVoks/Mi
# 0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGSdQ9RtG6l
# jlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6r7VRwo0k
# riTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo+MUSaJ/P
# QMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qzsIzV6Q3d
# 9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHqaGxEMrJm
# oecYpJpkUe8wggauMIIElqADAgECAhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3
# DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0
# ZWQgUm9vdCBHNDAeFw0yMjAzMjMwMDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJ
# BgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGln
# aUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0Ew
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE
# 8pE3qZdRodbSg9GeTKJtoLDMg/la9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBML
# JnOWbfhXqAJ9/UO0hNoR8XOxs+4rgISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU
# 5ygt69OxtXXnHwZljZQp09nsad/ZkIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLy
# dkf3YYMZ3V+0VAshaG43IbtArF+y3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFk
# dECnwHLFuk4fsbVYTXn+149zk6wsOeKlSNbwsDETqVcplicu9Yemj052FVUmcJgm
# f6AaRyBD40NjgHt1biclkJg6OBGz9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9a
# bJTyUpURK1h0QCirc0PO30qhHGs4xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwY
# SH8UNM/STKvvmz3+DrhkKvp1KCRB7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80Vg
# vCONWPfcYd6T/jnA+bIwpUzX6ZhKWD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5
# FBASA31fI7tk42PgpuE+9sJ0sj8eCXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9
# Rp6103a50g5rmQzSM7TNsQIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAdBgNVHQ4EFgQUuhbZbU2FL3MpdpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7Nfj
# gtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0
# hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0
# LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcN
# AQELBQADggIBAH1ZjsCTtm+YqUQiAX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp
# +3CKDaopafxpwc8dB+k+YMjYC+VcW9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9
# qVbPFXONASIlzpVpP0d3+3J0FNf/q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8
# ZCaHbJK9nXzQcAp876i8dU+6WvepELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6Z
# JxurJB4mwbfeKuv2nrF5mYGjVoarCkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnE
# tp/Nh4cku0+jSbl3ZpHxcpzpSwJSpzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fx
# ZsNBzU+2QJshIUDQtxMkzdwdeDrknq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV7
# 7QpfMzmHQXh6OOmc4d0j/R0o08f56PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT
# 1ObyF5lZynDwN7+YAN8gFk8n+2BnFqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkP
# Cr2B2RP+v6TR81fZvAT6gt4y3wSJ8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvm
# fxqkhQ/8mJb2VVQrH4D6wPIOK+XW+6kvRBVK5xMOHds3OBqhK/bt1nz8MIIGxjCC
# BK6gAwIBAgIQCnpKiJ7JmUKQBmM4TYaXnTANBgkqhkiG9w0BAQsFADBjMQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lD
# ZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4X
# DTIyMDMyOTAwMDAwMFoXDTMzMDMxNDIzNTk1OVowTDELMAkGA1UEBhMCVVMxFzAV
# BgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMSQwIgYDVQQDExtEaWdpQ2VydCBUaW1lc3Rh
# bXAgMjAyMiAtIDIwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC5KpYj
# ply8X9ZJ8BWCGPQz7sxcbOPgJS7SMeQ8QK77q8TjeF1+XDbq9SWNQ6OB6zhj+TyI
# ad480jBRDTEHukZu6aNLSOiJQX8Nstb5hPGYPgu/CoQScWyhYiYB087DbP2sO37c
# KhypvTDGFtjavOuy8YPRn80JxblBakVCI0Fa+GDTZSw+fl69lqfw/LH09CjPQnkf
# O8eTB2ho5UQ0Ul8PUN7UWSxEdMAyRxlb4pguj9DKP//GZ888k5VOhOl2GJiZERTF
# KwygM9tNJIXogpThLwPuf4UCyYbh1RgUtwRF8+A4vaK9enGY7BXn/S7s0psAiqwd
# jTuAaP7QWZgmzuDtrn8oLsKe4AtLyAjRMruD+iM82f/SjLv3QyPf58NaBWJ+cCzl
# K7I9Y+rIroEga0OJyH5fsBrdGb2fdEEKr7mOCdN0oS+wVHbBkE+U7IZh/9sRL5ID
# MM4wt4sPXUSzQx0jUM2R1y+d+/zNscGnxA7E70A+GToC1DGpaaBJ+XXhm+ho5GoM
# j+vksSF7hmdYfn8f6CvkFLIW1oGhytowkGvub3XAsDYmsgg7/72+f2wTGN/GbaR5
# Sa2Lf2GHBWj31HDjQpXonrubS7LitkE956+nGijJrWGwoEEYGU7tR5thle0+C2Fa
# 6j56mJJRzT/JROeAiylCcvd5st2E6ifu/n16awIDAQABo4IBizCCAYcwDgYDVR0P
# AQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# IAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMB8GA1UdIwQYMBaAFLoW
# 2W1NhS9zKXaaL3WMaiCPnshvMB0GA1UdDgQWBBSNZLeJIf5WWESEYafqbxw2j92v
# DTBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkRzRSU0E0MDk2U0hBMjU2VGltZVN0YW1waW5nQ0EuY3JsMIGQ
# BggrBgEFBQcBAQSBgzCBgDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tMFgGCCsGAQUFBzAChkxodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkRzRSU0E0MDk2U0hBMjU2VGltZVN0YW1waW5nQ0EuY3J0
# MA0GCSqGSIb3DQEBCwUAA4ICAQANLSN0ptH1+OpLmT8B5PYM5K8WndmzjJeCKZxD
# bwEtqzi1cBG/hBmLP13lhk++kzreKjlaOU7YhFmlvBuYquhs79FIaRk4W8+JOR1w
# cNlO3yMibNXf9lnLocLqTHbKodyhK5a4m1WpGmt90fUCCU+C1qVziMSYgN/uSZW3
# s8zFp+4O4e8eOIqf7xHJMUpYtt84fMv6XPfkU79uCnx+196Y1SlliQ+inMBl9AEi
# ZcfqXnSmWzWSUHz0F6aHZE8+RokWYyBry/J70DXjSnBIqbbnHWC9BCIVJXAGcqlE
# O2lHEdPu6cegPk8QuTA25POqaQmoi35komWUEftuMvH1uzitzcCTEdUyeEpLNypM
# 81zctoXAu3AwVXjWmP5UbX9xqUgaeN1Gdy4besAzivhKKIwSqHPPLfnTI/KeGeAN
# lCig69saUaCVgo4oa6TOnXbeqXOqSGpZQ65f6vgPBkKd3wZolv4qoHRbY2beayy4
# eKpNcG3wLPEHFX41tOa1DKKZpdcVazUOhdbgLMzgDCS4fFILHpl878jIxYxYaa+r
# PeHPzH0VrhS/inHfypex2EfqHIXgRU4SHBQpWMxv03/LvsEOSm8gnK7ZczJZCOct
# kqEaEf4ymKZdK5fgi9OczG21Da5HYzhHF1tvE9pqEG4fSbdEW7QICodaWQR2EaGn
# dwITHDGCBUwwggVIAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERp
# Z2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFj
# X7/erhIE520wCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFN+Gczx3PUVlcXtWvUF6oe1gLDODMA0G
# CSqGSIb3DQEBAQUABIIBAAdPt6ZrrtmStO+zuyXPU0i/oRw9mL6zFBf+7n0dUX5u
# H5ssumOk0LeW96sYSKBtcG3yGYakcox/cxohP8AkC4Arbdj/Hxx0L0CpnG4yKyRS
# lR1DZjtVQUG8roMdiIp4Imv0eBRdCRhvkKIRVfytW0M8FBBHOhRuyZBWm11LM0AT
# Q3z74hfg4IFA4MselWe69BOCzeaSlKT/6SYRWZTUKF9KniNP2cqOECgpzPeUQotw
# 6MiudAc6qKUFbMPOfumVHq0nIRy4zTTO2X+5gdzPWe0doMrVKeUGau1IzJWTZ2hF
# 61uQAzj4oPRilSjcMivDWN+/YgReYzlJL9gas0o8z4uhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU4WjAvBgkqhkiG9w0BCQQxIgQgoPSFZ4CnuE/Y1Xkvkb/V
# MeFwtK/2n0bsjkBp4Kti/WowDQYJKoZIhvcNAQEBBQAEggIACLP2xJU5yTa4IWM7
# gHQpwhLM4L5UFCA1xrRzN2hWuXTI7zjzh1Zhpx3qb/TsNTeM/qo5dlRnAAMcHsjF
# Hrr2klm9RsfDwpuGSNDahQqME727Xpmqa3n2Picu0hBboWR1mb0XtKbsgHu1TmbP
# qxkcLHcIYPtyWAwArtK/RxQxhZS8dJE48cMf2r2rs9hi4RJoV/UQYhtaQY8vnCD9
# UG68Vp0Uzx62SVPssXdgj3BeO1UguI4A1xIfxINYPSUloTFhFIeY3t1iMHkXgUZX
# QslNcN1lZsmz7OogJey7W1u0tj0MiZexb1KnxzdYDzwWCXd6h2A3RkdVWbSVXQar
# Dzk/5DHvuuRDOKZ/npSMaQzW6xbmV2iH/N6pWQUlZWGpilSnvr2D0CAW65masTom
# VYnEPuMsHQH4g+btLhtEqCGgX3IUrV0NA6jryH9b2xxnD1kXaC8njhWqFtdfFLU7
# 7QEeYBllRIaQtsSo4To8gUKd9scEuYs8fJwFvWW554sfQwdnPpj+mNjrOvivoRCY
# JKkmtbSLigBij/pJROHoy3RVx2kuG8E2Z0Cwb9QPxKpPv5uU6Dl0Ntgno/lLBv+J
# w4hoPogB9/slOJSuc0TbYq2Zi8eIGTOqBdAM+fOBpU/KlRIfsxxjXtNvmYc6+hOe
# Yl1xisthV0YEOgnZmnE2R0fbJQ0=
# SIG # End signature block
