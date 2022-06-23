function Invoke-DbaAdvancedInstall {
    <#
    .SYNOPSIS
        Designed for internal use, implements parallel execution for Install-DbaInstance.

    .DESCRIPTION
        Invokes an install process for a single computer and restarts it if needed

    .PARAMETER ComputerName
        Target computer with SQL instance or instances.

    .PARAMETER Port
        After successful installation, changes SQL Server TCP port to this value. Overrides the port specified in -SqlInstance.

    .PARAMETER InstallationPath
        Path to setup.exe

    .PARAMETER ConfigurationPath
        Path to Configuration.ini on a local machine

    .PARAMETER ArgumentList
        Array of command line arguments for setup.exe

    .PARAMETER Version
        Canonic version of SQL Server, e.g. 10.50, 11.0

    .PARAMETER InstanceName
        Instance name to be used for the installation

    .PARAMETER Configuration
        A hashtable with custom configuration items that you want to use during the installation.
        Overrides all other parameters.
        For example, to define a custom server collation you can use the following parameter:
        PS> Install-DbaInstance -Version 2017 -Configuration @{ SQLCOLLATION = 'Latin1_General_BIN' }

        Full list of parameters can be found here: https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt#Install

    .PARAMETER Restart
        Restart computer automatically after a successful installation of Sql Server and wait until it comes back online.
        Using this parameter is the only way to chain-install more than 1 instance, since every single patch will require a restart of said computer.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if installation media is located on a network folder.

    .PARAMETER Authentication
        Chooses an authentication protocol for remote connections.
        If the protocol fails to establish a connection

        Defaults:
        * CredSSP when -Credential is specified - due to the fact that repository Path is usually a network share and credentials need to be passed to the remote host to avoid the double-hop issue.
        * Default when -Credential is not specified. Will likely fail if a network path is specified.

    .PARAMETER PerformVolumeMaintenanceTasks
        Allow SQL Server service account to perform Volume Maintenance tasks.

    .PARAMETER SaveConfiguration
        Save installation configuration file in a custom location. Will not be preserved otherwise.

    .PARAMETER SaCredential
        Securely provide the password for the sa account when using mixed mode authentication.

    .PARAMETER NoPendingRenameCheck
        Disables pending rename validation when checking for a pending reboot.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deployment, Install, Patching
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Invoke-DbaAdvancedInstall

    .EXAMPLE
    PS C:\> Invoke-DbaAdvancedUpdate -ComputerName SQL1 -Action $actions

    Invokes update actions on SQL1 after restarting it.
    #>
    [CmdletBinding()]
    Param (
        [string]$ComputerName,
        [string]$InstanceName,
        [nullable[int]]$Port,
        [string]$InstallationPath,
        [string]$ConfigurationPath,
        [string[]]$ArgumentList,
        [version]$Version,
        [hashtable]$Configuration,
        [bool]$Restart,
        [bool]$PerformVolumeMaintenanceTasks,
        [string]$SaveConfiguration,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Credssp',
        [pscredential]$Credential,
        [pscredential]$SaCredential,
        [switch]$NoPendingRenameCheck,
        [switch]$EnableException
    )
    Function Get-SqlInstallSummary {
        # Reads Summary.txt from the SQL Server Installation Log folder
        Param (
            [DbaInstanceParameter]$ComputerName,
            [pscredential]$Credential,
            [parameter(Mandatory)]
            [version]$Version
        )
        $getSummary = {
            Param (
                [parameter(Mandatory)]
                [version]$Version
            )
            $versionNumber = "$($Version.Major)$($Version.Minor)".Substring(0, 3)
            $rootPath = "$([System.Environment]::GetFolderPath("ProgramFiles"))\Microsoft SQL Server\$versionNumber\Setup Bootstrap\Log"
            $summaryPath = "$rootPath\Summary.txt"
            $output = [PSCustomObject]@{
                Path              = $null
                Content           = $null
                ExitMessage       = $null
                ConfigurationFile = $null
            }
            if (Test-Path $summaryPath) {
                $output.Path = $summaryPath
                $output.Content = Get-Content -Path $summaryPath
                $output.ExitMessage = ($output.Content | Select-String "Exit message").Line -replace '^ *Exit message: *', ''
                # get last folder created - that's our setup
                $lastLogFolder = Get-ChildItem -Path $rootPath -Directory | Sort-Object -Property Name -Descending | Select-Object -First 1 -ExpandProperty FullName
                if (Test-Path $lastLogFolder\ConfigurationFile.ini) {
                    $output.ConfigurationFile = "$lastLogFolder\ConfigurationFile.ini"
                }
                return $output
            }
        }
        $params = @{
            ComputerName = $ComputerName.ComputerName
            Credential   = $Credential
            ScriptBlock  = $getSummary
            ArgumentList = @($Version.ToString())
            ErrorAction  = 'Stop'
            Raw          = $true
        }
        return Invoke-Command2 @params
    }
    $isLocalHost = ([DbaInstanceParameter]$ComputerName).IsLocalHost
    $output = [pscustomobject]@{
        ComputerName      = $ComputerName
        Version           = $Version
        SACredential      = $SaCredential
        Successful        = $false
        Restarted         = $false
        Configuration     = $Configuration
        InstanceName      = $InstanceName
        Installer         = $InstallationPath
        Port              = $Port
        Notes             = @()
        ExitCode          = $null
        ExitMessage       = $null
        Log               = $null
        LogFile           = $null
        ConfigurationFile = $null

    }
    $restartParams = @{
        ComputerName = $ComputerName
        ErrorAction  = 'Stop'
        For          = 'WinRM'
        Wait         = $true
        Force        = $true
    }
    if ($Credential) {
        $restartParams.Credential = $Credential
        $restartParams.WsmanAuthentication = $Authentication
    }
    $activity = "Installing SQL Server ($Version) components on $ComputerName"
    try {
        $restartNeeded = Test-PendingReboot -ComputerName $ComputerName -Credential $Credential -NoPendingRename:$NoPendingRenameCheck
    } catch {
        $restartNeeded = $false
        Stop-Function -Message "Failed to get reboot status from $computer" -ErrorRecord $_
    }
    if ($restartNeeded -and $Restart) {
        # Restart the computer prior to doing anything
        $msgPending = "Restarting computer $($ComputerName) due to pending restart"
        Write-ProgressHelper -ExcludePercent -Activity $activity -Message $msgPending
        Write-Message -Level Verbose $msgPending
        try {
            $null = Restart-Computer @restartParams
            $output.Restarted = $true
        } catch {
            Stop-Function -Message "Failed to restart computer $($ComputerName)" -ErrorRecord $_
        }
    }
    # save config if needed
    if ($SaveConfiguration) {
        try {
            $null = Copy-Item $ConfigurationPath -Destination $SaveConfiguration -ErrorAction Stop
        } catch {
            $msg = "Could not save configuration file to $SaveConfiguration"
            Stop-Function -Message $msg -ErrorRecord $_
            $output.Notes += $msg
        }
    }
    $connectionParams = @{
        ComputerName = $ComputerName
        ErrorAction  = "Stop"
        UseSSL       = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false)
    }
    if ($Credential) { $connectionParams.Credential = $Credential }
    # need to figure out where to store the config file
    if ($isLocalHost) {
        $remoteConfig = $ConfigurationPath
    } else {
        try {
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Copying configuration file to $ComputerName"
            $session = New-PSSession @connectionParams
            $chosenPath = Invoke-Command -Session $session -ScriptBlock { (Get-Item ([System.IO.Path]::GetTempPath())).FullName } -ErrorAction Stop
            $remoteConfig = Join-DbaPath $chosenPath.TrimEnd('\') (Split-Path $ConfigurationPath -Leaf)
            Write-Message -Level Verbose -Message "Copying $($ConfigurationPath) to remote machine into $chosenPath"
            $null = Send-File -Path $ConfigurationPath -Destination $chosenPath -Session $session -ErrorAction Stop
            $session | Remove-PSSession
        } catch {
            Stop-Function -Message "Failed to copy file $($ConfigurationPath) to $remoteConfig on $($ComputerName), exiting" -ErrorRecord $_
            return
        }
    }
    $installParams = $ArgumentList
    $installParams += "/CONFIGURATIONFILE=`"$remoteConfig`""
    Write-Message -Level Verbose -Message "Setup starting from $($InstallationPath)"
    $execParams = @{
        ComputerName   = $ComputerName
        ErrorAction    = 'Stop'
        Authentication = $Authentication
    }
    if ($Credential) {
        $execParams.Credential = $Credential
    } else {
        if (Test-Bound -Not Authentication) {
            # Use Default authentication instead of CredSSP when Authentication is not specified and Credential is null
            $execParams.Authentication = "Default"
        }
    }
    try {
        Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Installing SQL Server on $ComputerName from $InstallationPath"
        $installResult = Invoke-Program @execParams -Path $InstallationPath -ArgumentList $installParams -Fallback
        $output.ExitCode = $installResult.ExitCode
        # Get setup log summary contents
        try {
            $summary = Get-SqlInstallSummary -ComputerName $ComputerName -Credential $Credential -Version $Version
            $output.ExitMessage = $summary.ExitMessage
            $output.Log = $summary.Content
            $output.LogFile = $summary.Path
            $output.ConfigurationFile = $summary.ConfigurationFile
        } catch {
            Write-Message -Level Warning -Message "Could not get the contents of the summary file from $($ComputerName). Related properties will be empty" -ErrorRecord $_
        }
    } catch {
        Stop-Function -Message "Installation failed" -ErrorRecord $_
        $output.Notes += $_.Exception.Message
        return $output
    } finally {
        try {
            # Cleanup remote temp
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Cleaning up temporary files on $ComputerName"
            if (-not $isLocalHost) {
                $null = Invoke-Command2 @connectionParams -ScriptBlock {
                    if ($args[0] -like '*\Configuration_*.ini' -and (Test-Path $args[0])) {
                        Remove-Item -LiteralPath $args[0] -ErrorAction Stop
                    }
                } -Raw -ArgumentList $remoteConfig
            }
            # cleanup local temp config file
            Remove-Item $ConfigurationPath
        } catch {
            Stop-Function -Message "Temp cleanup failed" -ErrorRecord $_
        }
    }
    if ($installResult.Successful) {
        $output.Successful = $true
    } else {
        $msg = "Installation failed with exit code $($installResult.ExitCode). Expand 'ExitMessage' and 'Log' property to find more details."
        $output.Notes += $msg
        Stop-Function -Message $msg
        return $output
    }
    # perform volume maintenance tasks if requested
    if ($PerformVolumeMaintenanceTasks) {
        $null = Set-DbaPrivilege -ComputerName $ComputerName -Credential $Credential -Type IFI -EnableException:$EnableException
    }
    # change port after the installation
    if ($Port) {
        $null = Set-DbaTcpPort -SqlInstance "$($ComputerName)\$($InstanceName)" -Credential $Credential -Port $Port -EnableException:$EnableException -Confirm:$false
        try {
            $null = Restart-DbaService -ComputerName $ComputerName -InstanceName $InstanceName -Credential $Credential -Type Engine -Force -EnableException:$EnableException -Confirm:$false
        } catch {
            $output.Notes += "Port for $($ComputerName)\$($InstanceName) has been changed, but instance restart failed ($_). Restart of instance is necessary for the new settings to become effective."
        }

    }
    # restart if necessary
    try {
        $restartNeeded = Test-PendingReboot -ComputerName $ComputerName -Credential $Credential -NoPendingRename:$NoPendingRenameCheck
    } catch {
        $restartNeeded = $false
        Stop-Function -Message "Failed to get reboot status from $($ComputerName)" -ErrorRecord $_
    }
    if ($installResult.ExitCode -eq 3010 -or $restartNeeded) {
        if ($Restart) {
            # Restart the computer
            $restartMsg = "Restarting computer $($ComputerName) and waiting for it to come back online"
            Write-ProgressHelper -ExcludePercent -Activity $activity -Message $restartMsg
            Write-Message -Level Verbose -Message $restartMsg
            try {
                $null = Restart-Computer @restartParams
                $output.Restarted = $true
            } catch {
                Stop-Function -Message "Failed to restart computer $($ComputerName)" -ErrorRecord $_
                $output.Notes += "Restart is required for computer $($ComputerName) to finish the installation of Sql Server version $Version"
            }
        } else {
            $output.Notes += "Restart is required for computer $($ComputerName) to finish the installation of Sql Server version $Version"
        }
    }
    $output | Select-DefaultView -Property ComputerName, InstanceName, Version, Port, Successful, Restarted, Installer, ExitCode, LogFile, Notes
    Write-Progress -Activity $activity -Completed
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU/eXGyHkqLzjfMxOAvPz/uxkt
# IjKgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFF0R0PlL8+uEtC+k5b70u7n3Jzl2MA0G
# CSqGSIb3DQEBAQUABIIBADLsGfydJuO847k4C5GGx1KQ8jPkY31yqYyIisxPsmaF
# eH50rc7S54gvdrT8kplG0ziveCeBVJpAK+Sn6U2eDiS43J15c32e3CRIROQ18m5f
# GyFG6WrLpS0JfULHvQV6+ngZvK24PNTYOc0cNG3kZZtPkzfXPDeBQ2lo6gNnplej
# fWjtxlHtGqu21Zq1E0IaaRIxvTQfW/90aYceUIhGTWdWiwFmsUMdOn1J1Ik8/lGU
# liiq09SmecEFv3yv8b/pwFu433zFf44rLD9jntFnn8bCpRhrrcjMgPf132QwCuF+
# ED9F4IG7+rtZp58GuLqOSvhDpnidWpuoUpqrl/vtGi+hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU0WjAvBgkqhkiG9w0BCQQxIgQgxt8ctya5WkAF3rQ2Fmmg
# yKwqxKtO7qfuXpX7xTEl+BIwDQYJKoZIhvcNAQEBBQAEggIAF1qNiK8zdnhGHvYd
# ep7oGjw4Mzi1EkIf0iEQy8LYvLZUObcwADOYaRQsQPFhLpiPXQe/lW6eyXcakbd4
# 7wtedS1He0oWNpmQXbSECRpLBKqAvrv6x4g/MuZAnGEIuaebPPALNWqF0qTgRkTh
# e7NJAfBGKcVNy5F5S+VNZ107MCQ5RYNQYLxz7GopJbdvM/XdlMWUSqxYBcq1avv9
# P6zF8hZrNAgAdDhuv8TaARX+rnVtLqFpViFCMxnoy6CTg1h9PZj/1fAVXv64X5XE
# vXS1Ds4BZT+eQRCv1WcUM7yTdc+akeUdCu9JiHzH1PqLZGI4+QDwmrMuzfzBOMPr
# 0PVkyDfR/cm/IFv+KXeEHnwaLa5pFOOQh4mZb82BjKQn2aaZF2Vm8Iym+YuudjUz
# Svs0ZnTAcLs5mMn3kGFmPCZnFjodi6KX3C1779HwnzI1obg6YJ3hKN0NgCtTkrI/
# vGdavSlsSjcBCMn1cO++TpqPEy0QmiPs5riVsOAYXOk+Ifn0W0e+h8TV60J7iXOm
# yl3qNTDxdkD6MrhR7KLx6rLjvE1Vk1jcynCVvjbONVQcJMr3OHWGUPd3qtPYD6y4
# zXStG0wIEBDEbMDU1gWzUmqxI43NyynXVFPhmp3hdDhGBWIW/B1G1+rU3pft5nTd
# gWanwz5ILPq52z4YEah1D6porvk=
# SIG # End signature block
