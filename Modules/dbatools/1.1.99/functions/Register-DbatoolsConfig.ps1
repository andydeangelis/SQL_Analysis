function Register-DbatoolsConfig {
    <#
    .SYNOPSIS
        Registers an existing configuration object in registry.

    .DESCRIPTION
        Registers an existing configuration object in registry.
        This allows simple persisting of settings across powershell consoles.
        It also can be used to generate a registry template, which can then be used to create policies.

    .PARAMETER Config
        The configuration object to write to registry.
        Can be retrieved using Get-DbatoolsConfig.

    .PARAMETER FullName
        The full name of the setting to be written to registry.

    .PARAMETER Module
        The name of the module, whose settings should be written to registry.

    .PARAMETER Name
        Default: "*"
        Used in conjunction with the -Module parameter to restrict the number of configuration items written to registry.

    .PARAMETER Scope
        Default: UserDefault
        Who will be affected by this export how? Current user or all? Default setting or enforced?
        Legal values: UserDefault, UserMandatory, SystemDefault, SystemMandatory

    .PARAMETER EnableException
        This parameters disables user-friendly warnings and enables the throwing of exceptions.
        This is less user friendly, but allows catching exceptions in calling scripts.

    .NOTES
        Tags: Module
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Register-DbatoolsConfig

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig message.style.* | Register-DbatoolsConfig

        Retrieves all configuration items that that start with message.style. and registers them in registry for the current user.

    .EXAMPLE
        PS C:\> Register-DbatoolsConfig -FullName "message.consoleoutput.disable" -Scope SystemDefault

        Retrieves the configuration item "message.consoleoutput.disable" and registers it in registry as the default setting for all users on this machine.

    .EXAMPLE
        PS C:\> Register-DbatoolsConfig -Module Message -Scope SystemMandatory

        Retrieves all configuration items of the module Message, then registers them in registry to enforce them for all users on the current system.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [Parameter(ParameterSetName = "Default", ValueFromPipeline = $true)]
        [Sqlcollaborative.Dbatools.Configuration.Config[]]
        $Config,

        [Parameter(ParameterSetName = "Default", ValueFromPipeline = $true)]
        [string[]]
        $FullName,

        [Parameter(Mandatory = $true, ParameterSetName = "Name", Position = 0)]
        [string]
        $Module,

        [Parameter(ParameterSetName = "Name", Position = 1)]
        [string]
        $Name = "*",

        [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
        $Scope = "UserDefault",

        [switch]$EnableException
    )

    begin {
        if ($script:NoRegistry -and ($Scope -band 14)) {
            Stop-Function -Message "Cannot register configurations on non-windows machines to registry. Please specify a file-based scope" -Tag 'NotSupported' -Category NotImplemented
            return
        }

        # Linux and MAC default to local user store file
        if ($script:NoRegistry -and ($Scope -eq "UserDefault")) {
            $Scope = [Sqlcollaborative.Dbatools.Configuration.ConfigScope]::FileUserLocal
        }
        # Linux and MAC get redirection for SystemDefault to FileSystem
        if ($script:NoRegistry -and ($Scope -eq "SystemDefault")) {
            $Scope = [Sqlcollaborative.Dbatools.Configuration.ConfigScope]::FileSystem
        }

        $parSet = $PSCmdlet.ParameterSetName

        function Write-Config {
            [CmdletBinding()]
            Param (
                [Sqlcollaborative.Dbatools.Configuration.Config]
                $Config,

                [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
                $Scope,

                [bool]
                $EnableException,

                [string]
                $FunctionName = (Get-PSCallStack)[0].Command
            )

            if (-not $Config -or ($Config.RegistryData -eq "<type not supported>")) {
                Stop-Function -Message "Invalid Input, cannot export $($Config.FullName), type not supported" -EnableException $EnableException -Category InvalidArgument -Tag "config", "fail" -Target $Config -FunctionName $FunctionName
                return
            }

            try {
                Write-Message -Level Verbose -Message "Registering $($Config.FullName) for $Scope" -Tag "Config" -Target $Config -FunctionName $FunctionName
                #region User Default
                if (1 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryUserDefault -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryUserDefault -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion User Default

                #region User Mandatory
                if (2 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryUserEnforced -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryUserEnforced -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion User Mandatory

                #region System Default
                if (4 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryMachineDefault -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryMachineDefault -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion System Default

                #region System Mandatory
                if (8 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryMachineEnforced -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryMachineEnforced -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion System Mandatory
            } catch {
                Stop-Function -Message "Failed to export $($Config.FullName), to scope $Scope" -EnableException $EnableException -Tag "config", "fail" -Target $Config -ErrorRecord $_ -FunctionName $FunctionName
                return
            }
        }

        function Ensure-RegistryPath {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
            [CmdletBinding()]
            Param (
                [string]
                $Path
            )

            if (-not (Test-Path $Path)) {
                $null = New-Item $Path -Force
            }
        }

        # For file based persistence
        $configurationItems = @()
    }
    process {
        if (Test-FunctionInterrupt) { return }

        #region Registry Based
        if ($Scope -band 15) {
            switch ($parSet) {
                "Default" {
                    foreach ($item in $Config) {
                        Write-Config -Config $item -Scope $Scope -EnableException $EnableException
                    }

                    foreach ($item in $FullName) {
                        if ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.ContainsKey($item.ToLowerInvariant())) {
                            Write-Config -Config ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$item.ToLowerInvariant()]) -Scope $Scope -EnableException $EnableException
                        }
                    }
                }
                "Name" {
                    foreach ($item in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object Module -EQ $Module | Where-Object Name -Like $Name)) {
                        Write-Config -Config $item -Scope $Scope -EnableException $EnableException
                    }
                }
            }
        }
        #endregion Registry Based

        #region File Based
        else {
            switch ($parSet) {
                "Default" {
                    foreach ($item in $Config) {
                        if ($configurationItems.FullName -notcontains $item.FullName) { $configurationItems += $item }
                    }

                    foreach ($item in $FullName) {
                        if (($configurationItems.FullName -notcontains $item) -and ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.ContainsKey($item.ToLowerInvariant()))) {
                            $configurationItems += [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$item.ToLowerInvariant()]
                        }
                    }
                }
                "Name" {
                    foreach ($item in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object Module -EQ $Module | Where-Object Name -Like $Name)) {
                        if ($configurationItems.FullName -notcontains $item.FullName) { $configurationItems += $item }
                    }
                }
            }
        }
        #endregion File Based
    }
    end {
        if (Test-FunctionInterrupt) { return }

        #region Finish File Based Persistence
        if ($Scope -band 16) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileUserLocal "psf_config.json")
        }
        if ($Scope -band 32) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileUserShared "psf_config.json")
        }
        if ($Scope -band 64) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileSystem "psf_config.json")
        }
        #endregion Finish File Based Persistence
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQULl6G3I1+nLNqU1BVfgE1ZV/c
# U4ygghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFEALyQr8pJF//8HDPhkbCv7bJBAlMA0G
# CSqGSIb3DQEBAQUABIIBAEudTyI+S8O2qO620BVpXHLMgN72C+9NNIExfQg8XifE
# 34zGmjT8ld2CFEf7W1gguW3K0IchgITtIcrJRAhqrbPtrHJoKzo8TVUgscBwJXDE
# sUjD437qeu06r27FvIBIgvfGyZxB+XMi6iblFUR+VNyfTjq3F5TaqqXFMLUf7Ihv
# 4ALgqLEOQ+e58qNtVO2siegvLwPh5+/XtiVeWS43h/cAt7XCsMT3Hm1cj80wFUR3
# i7Pmqb3iLoBQnRrjGa0IddQX15HJvkB6C5TGkboctDMkEJDNfUCokBlh4wS64Pn5
# cXE3zSRizS18XQVEW9gtzwnsbHiCX47Bk/4ZUazoELuhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDA3WjAvBgkqhkiG9w0BCQQxIgQgJIaLTF/T4IcIrIG9/Law
# 4PixGAozeqI7W9YODwCzKq0wDQYJKoZIhvcNAQEBBQAEggIANUW84v5jcQT6ADd7
# R1dy2y7lR06UAkNBlLLEFy+fxGkWd95tDPH6E6nuoViQ1A3oNHeIYjczU+X63Zu4
# 2jgDHAWkpitRJ8oH3QdvWmUG/k5EQjlsyjOZMbSUtfL3QBG3l/pMV+vW2XHIXTME
# o6RzSWC1AxokpqNxGadTIE/Xwzwzb8OY9rd0VAvYKVGjkdP2SKCTKUp/K4on2Og6
# c33TyQ8P3eI5sd8Wg5uPQGHeSpyhyeFwO59FWSrMqlNWYREgT8ScptMbhotSbKLQ
# lcd234MfpMsIXVJa0iEOvTGmo0pHX5FDhf9e2xWLMK0rrKSnUQiG0EwaJVX4AJKT
# Cy78pJho3bVHT1Ztw0obStDcSQr4pU9TYZV1SmHjKIT9e0X1iLt0xD/c+FiZ1geJ
# NJhUXCdxC1PF9u0UjHF37ZS38QZpUD4pa3+5d9E+cwfKSwxBgHcWD32nRwmyL0vD
# Lpne0cDPCYNy81wKYie4rjWQF3viIam5mYz76rPwG9bvPte8+fzOyF8v2VizB9Il
# Yq7G4NmrPBFlz6XhIJkNDtPx1U9vKoty/+cVwWLv4bqpfJyVK/p2ibAVGhCiiaJU
# 0YU4oZK4gG47Hs+Jx0z2TnaLNe+4CDxHwxk27FIr/y4aaglRhPoalVc/TEFex7S8
# sQTmq3v8paNxtkuOzvClZNKQulc=
# SIG # End signature block
