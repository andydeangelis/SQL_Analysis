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
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAufGOEfwkOcSB3
# nQzhCp3O2nJyN8AFa/BrglzYnGdELaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCrfCxS215sP6B+zjnOfeA9ogyyIGdRQWbq
# 6+eTnw9MZjANBgkqhkiG9w0BAQEFAASCAQAoY8p7WA9cGqLvrl+nfDvfgRM/W4bt
# jsil2ac9/lcL9qEV+XZEkLqHdkdLsgY3WgSQqJshivjmS/yneJzKBCiEZmFGNr2Y
# vt1ec+W5Hbn0yoJru5FJ709MSkPdXt4L+v6F6lAVTUIROk3GRElNJsRTxJ9MZHeE
# Wtbd143367zjKW/l2LqznXA6j1yafzDlumL+y99BIbk0cpThEPc7aF8VR9SYiCUL
# 26RHl2weFaDxet54S48GZaYa0ka41GGFhYeAYElsfIj7Qk6eC+EfJbu93WVcld/I
# LKgkwYbFbv+xB7isPKENkt1AC9SRSwDf2igCqhhGoM091UP7O95tRFm3oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMyNVowLwYJKoZIhvcNAQkEMSIEIG/V3A7o
# QRxej7FTxlaxvkPGRDJ9ods2oxt6leHMqud1MA0GCSqGSIb3DQEBAQUABIICAFNe
# Gcx0b2XFFm5OVyVld6Qap/xJY5dAfQZMSddLCyxfkhdSYlkmKSNC2I8BfDnAHm2O
# x3ITxSfO8GSm8ab/YbxGKCx2P5p+35HO1ZABKvvsELynYuifZFaaj1IEv4d7W5S4
# QPN5zwJEUjbLznzX00RNro9XnCx/e7prf/5LSi06GaSXFloqqG5ErqZ09S9s1W94
# ig11MRPkTJXmIt0EHBsZX71x6y9BADSkp6iHz9+gzsy/wcGO43wZRJqDnTdtPDl2
# gMmPV7Kytzt/BuJq+ZcL/Yz3Cl06W+4TIOjEy8cPhyzkq8T8ePuZd5J2ctpRWiV/
# DJEa8hEl1fjJWA2vwbQUB6LEEjL6Cb9mIQC1cQIqeQsO8Xufjhtc2R9I7XmaBzZX
# seEkFBOvdvjsUNWhcxA8AwlwA76ccINsWnVJOHN+NMdkCB8EelApNtUT+6V2rUIj
# T9uaLSIo80vw2cpoowc14SMnQAXLG/Jmof3PZowmop2BB8OJ6zjC9SUIktdGasVa
# Tb8tIf4i8jh5WKQcPEAeVGIOGoUz2Ooqzcs0bzgdIGl9gDGMErAKfYrHd83J4Sft
# vAFUCpu7aZ9UNRqdTVd1llA8q21YmkaQjcxbrjxyjZDsj4Q/fQQXxiyFOoXjddFX
# vqTv16GWSKzzEnEL0rTLGKp/cKQ6dVCuiRE75omX
# SIG # End signature block
