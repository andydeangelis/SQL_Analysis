function Set-DbaTempDbConfig {
    <#
    .SYNOPSIS
        Sets tempdb data and log files according to best practices.

    .DESCRIPTION
        Calculates tempdb size and file configurations based on passed parameters, calculated values, and Microsoft best practices. User must declare SQL Server to be configured and total data file size as mandatory values. Function then calculates the number of data files based on logical cores on the target host and create evenly sized data files based on the total data size declared by the user.

        Other parameters can adjust the settings as the user desires (such as different file paths, number of data files, and log file size). No functions that shrink or delete data files are performed. If you wish to do this, you will need to resize tempdb so that it is "smaller" than what the function will size it to before running the function.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DataFileCount
        Specifies the number of data files to create. If this number is not specified, the number of logical cores of the host will be used.

    .PARAMETER DataFileSize
        Specifies the total data file size in megabytes. This is distributed across the total number of data files.

    .PARAMETER LogFileSize
        Specifies the log file size in megabytes. If not specified, no change will be made.

    .PARAMETER DataFileGrowth
        Specifies the growth amount for the data file(s) in megabytes. The default is 512 MB.

    .PARAMETER LogFileGrowth
        Specifies the growth amount for the log file in megabytes. The default is 512 MB.

    .PARAMETER DataPath
        Specifies the filesystem path(s) in which to create the tempdb data files. If not specified, current tempdb location will be used.

    .PARAMETER LogPath
        Specifies the filesystem path in which to create the tempdb log file. If not specified, current tempdb location will be used.

    .PARAMETER OutputScriptOnly
        If this switch is enabled, only the T-SQL script to change the tempdb configuration is created and output.

    .PARAMETER OutFile
        Specifies the filesystem path into which the generated T-SQL script will be saved.

    .PARAMETER DisableGrowth
        If this switch is enabled, the tempdb files will be configured to not grow. This overrides -DataFileGrowth and -LogFileGrowth.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Tempdb, Configuration
        Author: Michael Fal (@Mike_Fal), http://mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaTempDbConfig

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000

        Creates tempdb with a number of data files equal to the logical cores where each file is equal to 1000MB divided by the number of logical cores, with a log file of 250MB.

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000 -DataFileCount 8

        Creates tempdb with 8 data files, each one sized at 125MB, with a log file of 250MB.

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000 -OutputScriptOnly

        Provides a SQL script output to configure tempdb according to the passed parameters.

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000 -DisableGrowth

        Disables the growth for the data and log files.

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000 -OutputScriptOnly

        Returns the T-SQL script representing tempdb configuration.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$DataFileCount,
        [Parameter(Mandatory)]
        [int]$DataFileSize,
        [int]$LogFileSize,
        [int]$DataFileGrowth = 512,
        [int]$LogFileGrowth = 512,
        [string[]]$DataPath,
        [string]$LogPath,
        [string]$OutFile,
        [switch]$OutputScriptOnly,
        [switch]$DisableGrowth,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $cores = $server.Processors
            if ($cores -gt 8) {
                $cores = 8
            }

            #Set DataFileCount if not specified. If specified, check against best practices.
            if (-not $DataFileCount) {
                $DataFileCount = $cores
                Write-Message -Message "Data file count set to number of cores: $DataFileCount" -Level Verbose
            } else {
                if ($DataFileCount -gt $cores) {
                    Write-Message -Message "Data File Count of $DataFileCount exceeds the Logical Core Count of $cores. This is outside of best practices." -Level Warning
                }
                Write-Message -Message "Data file count set explicitly: $DataFileCount" -Level Verbose
            }

            $DataFilesizeSingle = $([Math]::Floor($DataFileSize / $DataFileCount))
            Write-Message -Message "Single data file size (MB): $DataFilesizeSingle." -Level Verbose

            if (Test-Bound -ParameterName DataPath) {
                foreach ($dataDirPath in $DataPath) {
                    if ((Test-DbaPath -SqlInstance $server -Path $dataDirPath) -eq $false) {
                        $invalidPathFound = "$dataDirPath does not exist"
                        break
                    }
                }

                if ($invalidPathFound) {
                    Stop-Function -Message $invalidPathFound -Continue
                }
            } else {
                $Filepath = $server.Databases['tempdb'].Query('SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 1').PhysicalName
                $DataPath = Split-Path $Filepath
            }

            Write-Message -Message "Using data path(s): $DataPath." -Level Verbose

            if (Test-Bound -ParameterName LogPath) {
                if ((Test-DbaPath -SqlInstance $server -Path $LogPath) -eq $false) {
                    Stop-Function -Message "$LogPath is an invalid path." -Continue
                }
            } else {
                $Filepath = $server.Databases['tempdb'].Query('SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 2').PhysicalName
                $LogPath = Split-Path $Filepath
            }
            Write-Message -Message "Using log path: $LogPath." -Level Verbose

            # Check if the file growth needs to be disabled
            if ($DisableGrowth) {
                $DataFileGrowth = 0
                $LogFileGrowth = 0
            }

            # Check current tempdb. Throw an error if current tempdb is larger than config.
            $CurrentFileCount = $server.Databases['tempdb'].Query('SELECT count(1) as FileCount FROM sys.database_files WHERE type=0').FileCount
            $TooBigCount = $server.Databases['tempdb'].Query("SELECT TOP 1 (size/128) as Size FROM sys.database_files WHERE size/128 > $DataFilesizeSingle AND type = 0").Size

            if ($CurrentFileCount -gt $DataFileCount) {
                Stop-Function -Message "Current tempdb in $instance is not suitable to be reconfigured. The current tempdb has a greater number of files ($CurrentFileCount) than the calculated configuration ($DataFileCount)." -Continue
            }

            if ($TooBigCount) {
                Stop-Function -Message "Current tempdb in $instance is not suitable to be reconfigured. The current tempdb has files with a size ($TooBigCount MB) larger than the calculated individual file configuration ($DataFilesizeSingle MB)." -Continue
            }

            Write-Message -Message "tempdb configuration validated." -Level Verbose

            $DataFiles = Get-DbaDbFile -SqlInstance $server -Database tempdb | Where-Object Type -eq 0 | Select-Object LogicalName, PhysicalName

            # Used to round-robin the placement of tempdb data files if more than one value for $DataPath was passed in.
            $dataPathIndexToUse = 0

            #Checks passed, process reconfiguration
            for ($i = 0; $i -lt $DataFileCount; $i++) {
                $File = $DataFiles[$i]

                if ($DataPath.Count -gt 1) {
                    $newDataDirPath = $DataPath[$dataPathIndexToUse]

                    $dataPathIndexToUse += 1

                    # reset the round robin index variable
                    if ($dataPathIndexToUse -ge $DataPath.Count ) {
                        $dataPathIndexToUse = 0
                    }
                } else {
                    $newDataDirPath = $DataPath
                }

                if ($File) {
                    $Filename = Split-Path $File.PhysicalName -Leaf
                    $LogicalName = $File.LogicalName
                    $NewPath = "$newDataDirPath\$Filename"
                    $sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$DataFilesizeSingle MB,filegrowth=$DataFileGrowth);"
                } else {
                    $NewName = "tempdev$i.ndf"
                    $NewPath = "$newDataDirPath\$NewName"
                    $sql += "ALTER DATABASE tempdb ADD FILE(name=tempdev$i,filename='$NewPath',size=$DataFilesizeSingle MB,filegrowth=$DataFileGrowth);"
                }
            }

            $logfile = Get-DbaDbFile -SqlInstance $server -Database tempdb | Where-Object Type -eq 1 | Select-Object LogicalName, PhysicalName, @{L = "SizeMb"; E = { $_.Size.Megabyte } }

            if ($LogPath -or $LogFileSize) {
                $Filename = Split-Path $logfile.PhysicalName -Leaf
                $LogicalName = $logfile.LogicalName

                if ($LogPath) {
                    $NewPath = "$LogPath\$Filename"
                } else {
                    $NewPath = $logfile.PhysicalName
                }

                if (-not($LogFileSize)) {
                    $LogFileSize = $logfile.SizeMb
                }

                $sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$LogFileSize MB,filegrowth=$LogFileGrowth);"
            }

            Write-Message -Message "SQL Statement to resize tempdb." -Level Verbose
            Write-Message -Message ($sql -join "`n`n") -Level Verbose

            if ($OutputScriptOnly) {
                return $sql
            } elseif ($OutFile) {
                $sql | Set-Content -Path $OutFile
            } else {
                if ($Pscmdlet.ShouldProcess($instance, "Executing query and informing that a restart is required.")) {
                    try {
                        $server.Databases['master'].ExecuteNonQuery($sql)
                        Write-Message -Level Verbose -Message "tempdb successfully reconfigured."

                        [PSCustomObject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            DataFileCount      = $DataFileCount
                            DataFileSize       = [dbasize]($DataFileSize * 1024 * 1024)
                            SingleDataFileSize = [dbasize]($DataFilesizeSingle * 1024 * 1024)
                            LogSize            = [dbasize]($LogFileSize * 1024 * 1024)
                            DataPath           = $DataPath
                            LogPath            = $LogPath
                            DataFileGrowth     = [dbasize]($DataFileGrowth * 1024 * 1024)
                            LogFileGrowth      = [dbasize]($LogFileGrowth * 1024 * 1024)
                        }

                        Write-Message -Level Output -Message "tempdb reconfigured. You must restart the SQL Service for settings to take effect."
                    } catch {
                        Stop-Function -Message "Unable to reconfigure tempdb. Exception: $_" -Target $sql -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUSxqRI5WNqbFFq37yXXW7Io/e
# Ol2gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFBqoBPYpNCXlqDmyvXZzU2cUhVBzMA0G
# CSqGSIb3DQEBAQUABIIBADUGf+ihemuyG+IpvHyzd7xU3XDXcQ0dXNyOXKMZ8FUY
# 4pZMVarJTJNBvN5IjHXJkp7k5S+K2Jdsa809FU8QOoj3xDi5kp3jWHZp8X3wwU3S
# f410ixIKiuHtG+KFyIJDCwV8oxEYerd/LDC3k0U7tfwhHqwZ2T6vi0bFjgjeS8bS
# rNg6+3J/ywDlUXQmQZMbvhrTSjbd0Gq7DCR2swd7Dx2D/UFkYvO2vZGkKJ4/j3Nq
# xuDQMZiDXYmpdVn/whO91lPal7aAUew2KhpJLi9LNdIkIZO07U+/prlyfmznkd+C
# vQUHBa088pmvRJj1LAI9nhcrVss+CYdj8KVVVd1Lxc2hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDIzWjAvBgkqhkiG9w0BCQQxIgQglV5q0XNS+VaEbKIi9bGm
# At/TP+BH2Pgg0zRrDvojKTgwDQYJKoZIhvcNAQEBBQAEggIAUsJHUc5H5iL+0NrW
# qCyUIWG0sT9gx7wM1c1zxqhRTfe/bVtftZB654Lr9ShMa5eeYZCZaqnEiJQziLeN
# cv7G/BbJ8mnUNixXcn6LaBRKke2bKh7eEbsna+/pggsjt69m8+i+k6LVcJtA3PW4
# jQ8j6H1L1LWYHAv7f4eO2auKwSpXOWNXdGh3vSof7sb0+MEvYJZnSGPAHeDdDzHj
# bBosvVz1VekUBaoTvxGnDsU6ICfsDaKWVlzkDoLWFlyi9mPYbA4j2MWsT68pVSOU
# EQMBng04ALYzleWhhpVunAwFNc/SXbMrfkKsfFEhDF/Zb0gqwQQAbkVuzIoLRQCb
# d3P44HWbvb0cYjcg8ny3NOKh9HyyN6hX/0fkOt9FrdFZMobnNSv9GS8TP3vcqDOg
# E9YGcadFfmu04QdkyMEQU//XYZVacHkj2Zg8pQ/PNfQ2UBT+oHqexweMNBQnfHTs
# wpsee3XnXbR7aPLXGsaA42NHZUyO3tU+5KkUvn0gk6kSoMl9p/KiOWdWIAhYcn0b
# Y6pjsMK38yD0HgbKFiRVYke4SMjmatt+ogBHS69ZZmVK+H5fPl+opjd7PHX3HYlX
# O9Ibmqgs76trUSQOebboKFSQm6E538A9vcwFv//M3TRna2ob1OfG+ImomSshC0V5
# Lq7ivi9pNvlfzlhuXAj3XdZpoY0=
# SIG # End signature block
