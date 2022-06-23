function Save-DbaCommunitySoftware {
    <#
    .SYNOPSIS
        Download and extract software from Github to update the local cached version of that software.

    .DESCRIPTION
        Download and extract software from Github to update the local cached version of that software.
        This command is run from inside of Install-Dba* and Update-Dba* commands to update the local cache if needed.

        In case you don't have internet access on the target computer, you can download the zip files from the following URLs
        at another computer, transfer them to the target computer or place them on a network share and then use -LocalFile
        to update the local cache:
        * MaintenanceSolution: https://github.com/olahallengren/sql-server-maintenance-solution
        * FirstResponderKit: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/releases
        * DarlingData: https://github.com/erikdarlingdata/DarlingData
        * SQLWATCH: https://github.com/marcingminski/sqlwatch/releases
        * WhoIsActive: https://github.com/amachanic/sp_whoisactive/releases
        * DbaMultiTool: https://github.com/LowlyDBA/dba-multitool/releases

    .PARAMETER Software
        Name of the software to download.
        Options include:
        * MaintenanceSolution: SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)
        * FirstResponderKit: First Responder Kit created by Brent Ozar (http://FirstResponderKit.org)
        * DarlingData: Erik Darling's stored procedures (https://www.erikdarlingdata.com)
        * SQLWATCH: SQL Server Monitoring Solution created by Marcin Gminski (https://sqlwatch.io/)
        * WhoIsActive: Adam Machanic's comprehensive activity monitoring stored procedure sp_WhoIsActive (https://github.com/amachanic/sp_whoisactive)
        * DbaMultiTool: John McCall's T-SQL scripts for the long haul: optimizing storage, on-the-fly documentation, and general administrative needs (https://dba-multitool.org)

    .PARAMETER Branch
        Specifies the branch. Defaults to master or main. Can only be used if Software is used.

    .PARAMETER LocalFile
        Specifies the path to a local file to install from instead of downloading from Github.

    .PARAMETER Url
        Specifies the URL to download from. Is not needed if Software is used.

    .PARAMETER LocalDirectory
        Specifies the local directory to extract the downloaded file to. Is not needed if Software is used.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community
        Author: Andreas Jordan, @JordanOrdix

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
         https://dbatools.io/Save-DbaCommunitySoftware

    .EXAMPLE
        PS C:\> Save-DbaCommunitySoftware -Software MaintenanceSolution

        Updates the local cache of Ola Hallengren's Solution objects.

    .EXAMPLE
        PS C:\> Save-DbaCommunitySoftware -Software FirstResponderKit -LocalFile \\fileserver\Software\SQL-Server-First-Responder-Kit-20211106.zip

        Updates the local cache of the First Responder Kit based on the given file.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [ValidateSet('MaintenanceSolution', 'FirstResponderKit', 'DarlingData', 'SQLWATCH', 'WhoIsActive', 'DbaMultiTool')]
        [string]$Software,
        [string]$Branch,
        [string]$LocalFile,
        [string]$Url,
        [string]$LocalDirectory,
        [switch]$EnableException
    )

    process {
        $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"

        # Set Branch, Url and LocalDirectory for known Software
        if ($Software -eq 'MaintenanceSolution') {
            if (-not $Branch) {
                $Branch = 'master'
            }
            if (-not $Url) {
                $Url = "https://github.com/olahallengren/sql-server-maintenance-solution/archive/$Branch.zip"
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "sql-server-maintenance-solution-$Branch"
            }
        } elseif ($Software -eq 'FirstResponderKit') {
            if (-not $Branch) {
                $Branch = 'main'
            }
            if (-not $Url) {
                $Url = "https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/$Branch.zip"
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQL-Server-First-Responder-Kit-$Branch"
            }
        } elseif ($Software -eq 'DarlingData') {
            if (-not $Branch) {
                $Branch = 'main'
            }
            if (-not $Url) {
                $Url = "https://github.com/erikdarlingdata/DarlingData/archive/$Branch.zip"
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "DarlingData-$Branch"
            }
        } elseif ($Software -eq 'SQLWATCH') {
            if ($Branch -in 'prerelease', 'pre-release') {
                $preRelease = $true
            } else {
                $preRelease = $false
            }
            if (-not $Url -and -not $LocalFile) {
                $releasesUrl = "https://api.github.com/repos/marcingminski/sqlwatch/releases"
                try {
                    try {
                        $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                    } catch {
                        # Try with default proxy and usersettings
                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                        $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Unable to get release information from $releasesUrl." -ErrorRecord $_
                    return
                }
                $latestRelease = ($releasesJson | ConvertFrom-Json) | Where-Object prerelease -eq $preRelease | Select-Object -First 1
                if ($null -eq $latestRelease) {
                    Stop-Function -Message "No release found." -ErrorRecord $_
                    return
                }
                $Url = $latestRelease.assets[0].browser_download_url
            }
            if (-not $LocalDirectory) {
                if ($preRelease) {
                    $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQLWATCH-prerelease"
                } else {
                    $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQLWATCH"
                }
            }
        } elseif ($Software -eq 'WhoIsActive') {
            # We currently ignore -Branch as there is only one branch and there are no pre-releases.
            if (-not $Url -and -not $LocalFile) {
                $releasesUrl = "https://api.github.com/repos/amachanic/sp_whoisactive/releases"
                try {
                    try {
                        $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                    } catch {
                        # Try with default proxy and usersettings
                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                        $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Unable to get release information from $releasesUrl." -ErrorRecord $_
                    return
                }
                $latestRelease = ($releasesJson | ConvertFrom-Json) | Select-Object -First 1
                if ($null -eq $latestRelease) {
                    Stop-Function -Message "No release found." -ErrorRecord $_
                    return
                }
                $Url = $latestRelease.zipball_url
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "WhoIsActive"
            }
        } elseif ($Software -eq 'DbaMultiTool') {
            if (-not $Branch) {
                $Branch = 'master'
            }
            if (-not $Url) {
                $Url = "https://github.com/LowlyDBA/dba-multitool/archive/$Branch.zip"
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "dba-multitool-$Branch"
            }
        }

        # Test if we now have source and destination for the following actions.
        if (-not ($Url -or $LocalFile)) {
            Stop-Function -Message 'Url or LocalFile is missing.'
            return
        }
        if (-not $LocalDirectory) {
            Stop-Function -Message 'LocalDirectory is missing.'
            return
        }

        # First part is download and extract and we use the temp directory for that and clean up afterwards.
        # So we use a file and a folder with a random name to reduce potential conflicts,
        # but name them with dbatools to be able to recognize them.
        $temp = [System.IO.Path]::GetTempPath()
        $random = Get-Random
        $zipFile = Join-DbaPath -Path $temp -Child "dbatools_software_download_$random.zip"
        $zipFolder = Join-DbaPath -Path $temp -Child "dbatools_software_download_$random"

        if ($Software -eq 'WhoIsActive' -and $LocalFile.EndsWith('.sql')) {
            # For WhoIsActive, we allow to pass in the sp_WhoIsActive.sql file or any other sql file with the source code.
            # We create the zip folder with a subfolder named WhoIsActive and copy the LocalFile there as sp_WhoIsActive.sql.
            $appFolder = Join-DbaPath -Path $zipFolder -Child 'WhoIsActive'
            $appFile = Join-DbaPath -Path $appFolder -Child 'sp_WhoIsActive.sql'
            $null = New-Item -Path $zipFolder -ItemType Directory
            $null = New-Item -Path $appFolder -ItemType Directory
            Copy-Item -Path $LocalFile -Destination $appFile
        } elseif ($LocalFile) {
            # No download, so we just extract the given file if it exists and is a zip file.
            if (-not (Test-Path $LocalFile)) {
                Stop-Function -Message "$LocalFile doesn't exist"
                return
            }
            if (-not ($LocalFile.EndsWith('.zip'))) {
                Stop-Function -Message "$LocalFile has to be a zip file"
                return
            }
            if ($PSCmdlet.ShouldProcess($LocalFile, "Extracting archive to $zipFolder path")) {
                try {
                    Unblock-File $LocalFile -ErrorAction SilentlyContinue
                    Expand-Archive -LiteralPath $LocalFile -DestinationPath $zipFolder -Force -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Unable to extract $LocalFile to $zipFolder." -ErrorRecord $_
                    return
                }
            }
        } else {
            # Download and extract.
            if ($PSCmdlet.ShouldProcess($Url, "Downloading to $zipFile")) {
                try {
                    try {
                        Invoke-TlsWebRequest -Uri $Url -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
                    } catch {
                        # Try with default proxy and usersettings
                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                        Invoke-TlsWebRequest -Uri $Url -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Unable to download $Url to $zipFile." -ErrorRecord $_
                    return
                }
            }
            if ($PSCmdlet.ShouldProcess($zipFile, "Extracting archive to $zipFolder path")) {
                try {
                    Unblock-File $zipFile -ErrorAction SilentlyContinue
                    Expand-Archive -Path $zipFile -DestinationPath $zipFolder -Force -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Unable to extract $zipFile to $zipFolder." -ErrorRecord $_
                    Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                    return
                }
            }
        }

        # As a safety net, we test whether the archive contained exactly the desired destination directory.
        # But inside of zip files that are downloaded by the user via a webbrowser and not the api,
        # the directory name is the name of the zip file. So we have to test for that as well.
        if ($PSCmdlet.ShouldProcess($zipFolder, "Testing for correct content")) {
            $localDirectoryBase = Split-Path -Path $LocalDirectory
            $localDirectoryName = Split-Path -Path $LocalDirectory -Leaf
            $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
            $sourceDirectoryName = $sourceDirectory.Name
            if ($Software -eq 'SQLWATCH') {
                # As this software is downloaded as a release, the directory has a different name.
                # Rename the directory from like 'SQLWATCH 4.3.0.23725 20210721131116' to 'SQLWATCH' to be able to handle this like the other software.
                if ($sourceDirectoryName -like 'SQLWATCH*') {
                    # Write a file with version info, to be able to check if version is outdated
                    Set-Content -Path "$($sourceDirectory.FullName)\version.txt" -Value $sourceDirectoryName
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'SQLWATCH'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            } elseif ($Software -eq 'WhoIsActive') {
                # As this software is downloaded as a release, the directory has a different name.
                # Rename the directory from like 'amachanic-sp_whoisactive-459d2bc' to 'WhoIsActive' to be able to handle this like the other software.
                if ($sourceDirectoryName -like '*sp_whoisactive-*') {
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'WhoIsActive'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            } elseif ($Software -eq 'FirstResponderKit') {
                # As this software is downloadable as a release, the directory might have a different name.
                # Rename the directory from like 'SQL-Server-First-Responder-Kit-20211106' to 'SQL-Server-First-Responder-Kit-main' to be able to handle this like the other software.
                if ($sourceDirectoryName -like 'SQL-Server-First-Responder-Kit-20*') {
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'SQL-Server-First-Responder-Kit-main'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            } elseif ($Software -eq 'DbaMultiTool') {
                # As this software is downloadable as a release, the directory might have a different name.
                # Rename the directory from like 'dba-multitool-1.7.5' to 'dba-multitool-master' to be able to handle this like the other software.
                if ($sourceDirectoryName -like 'dba-multitool-[0-9]*') {
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'dba-multitool-master'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            }
            if ((Get-ChildItem -Path $zipFolder).Count -gt 1 -or $sourceDirectoryName -ne $localDirectoryName) {
                Stop-Function -Message "The archive does not contain the desired directory $localDirectoryName but $sourceDirectoryName."
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
                return
            }
        }

        # Replace the target directory by the extracted directory.
        if ($PSCmdlet.ShouldProcess($zipFolder, "Copying content to $LocalDirectory")) {
            try {
                if (Test-Path -Path $LocalDirectory) {
                    Remove-Item -Path $LocalDirectory -Recurse -ErrorAction Stop
                }
            } catch {
                Stop-Function -Message "Unable to remove the old target directory $LocalDirectory." -ErrorRecord $_
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
                return
            }
            try {
                Copy-Item -Path $sourceDirectory.FullName -Destination $localDirectoryBase -Recurse -ErrorAction Stop
            } catch {
                Stop-Function -Message "Unable to copy the directory $sourceDirectory to the target directory $localDirectoryBase." -ErrorRecord $_
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($zipFile, "Removing temporary file")) {
            Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
        }
        if ($PSCmdlet.ShouldProcess($zipFolder, "Removing temporary folder")) {
            Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUOQHSs1T/LKVsRXqyC0Kp2Bfj
# VPWgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFM0xQIDnllCmSCqVeRefocQr2H0bMA0G
# CSqGSIb3DQEBAQUABIIBALq1OlfffYkSTOArJLBik4Au2kW+1MCw93oIYjsUIzFi
# KhGJ4gOCHmNEqtk61kMKJLGMvDHu/+RxtxHv3DCYOZDLF6g9D/JWRRbxs5Ke0wlN
# oS4RHHyhhseB0m16U/w6MhLj0nZX0F+5f7ZotwqRQxVtXHwmMmbQNEKn4pa95MGl
# MJbXXdaEsi4o1Q0V5fAi84uS8QxGJRxHZybjdEpK/lPKQOgqflFflgWDT2vSq+E5
# D/rQcDtYDG6g9bKet8iOzV5yD4jpD/+VmqOTj+lwgL9t5PkkSv0XDEnRJCIBA5CB
# Z7x5JSFjT8H0/ZytssOvbzXcptj+kWPrWxNXEAZVL/yhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDE3WjAvBgkqhkiG9w0BCQQxIgQgPqByO2jUrgzvQGQ9vrp4
# zZamBVlXSN82Rtj9pSBIrJ0wDQYJKoZIhvcNAQEBBQAEggIAjnGquxt4N7jZyJ5d
# Am9zJcCweQ6/lXoPly351DBqADId+w/Pbk2e+KehUC0CWarO2ueMNfzgzgOwjjNp
# q2146zvFjlWlbWAG58x9lUapKUJhu8dsgX29VApPE9niAOYU3FBizBLkL2KUKUH2
# l20ybOmGM2y2ZRUr5l9ndKeli9z0/Tq31aZqBs7f5aSFjvzuAxIDLkk4ecdLpMPz
# nf3rDHdFx3tr8FkswxL1RQrsUQ77YCuy3Ossdzwch/hBGw99xGfImy6B4VofWqAb
# pBk/xx50eaxsQG05RlXVAWTTl3KjyYQsKDmxjNPnsD7bQsLjoB+TG9ri+v+IeDhl
# YHMUxrP0/6ZaIjIDwnNVaK8bB/AXl+Pj8s5LERlqNTfzWOPCuDQPxrlBXWSL4SbN
# HteHnxccN5AslEGsPeANd8AEw9F3TNLSks7kMHfi7yW9ufG4Z9awoUl+Jw99rl0f
# ywc1FsRhTGmCV1nlN8oDy8dDxeaWbolgHaE15PUjxFD9OoRrrwG1NSox30tUG128
# JdoEf9Og/auheiGIrwcL3MXvQEOvPsMr9rqWt7RlyYWgv3gmdeQ/zpRCTa9ILh9m
# WC2VZcKGZhxzQX2aMXKpxKJyftnSXaaoYayfTLmiqmlu5PHQ5g1cIfmKwccuBUTp
# ZJTaB0DZjGRO5qdkFzG6NS9yMVM=
# SIG # End signature block
