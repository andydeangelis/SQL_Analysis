<#

#-------------------------#
# Warning Warning Warning #
#-------------------------#

This is the global configuration management file.

DO NOT EDIT THIS FILE!!!!!
Disobedience shall be answered by the wrath of Fred.
You've been warned.
;)

The purpose of this file is to manage the configuration system.
That means, messing with this may mess with every function using this infrastructure.
Don't, unless you know what you do.

#---------------------------------------#
# Implementing the configuration system #
#---------------------------------------#

The configuration system is designed, to keep as much hard coded configuration out of the functions.
Instead we keep it in a central location: The Configuration store (= this folder).

In Order to put something here, either find a configuration file whose topic suits you and add configuration there,
or create your own file. The configuration system is loaded last during module import process, so you have access to all
that dbatools has to offer (Keep module load times in mind though).

Examples are better than a thousand words:

a) Setting the configuration value
# Put this in a configuration file in this folder
Set-DbatoolsConfig -Name 'Path.DbatoolsLog' -Value "$([System.Environment]::GetFolderPath("ApplicationData"))\PowerShell\dbatools" -Initialize -Description "Sopmething meaningful here"

b) Retrieving the configuration value in your function
# Put this in the function that uses this setting
$path = Get-DbatoolsConfigValue -Name 'Path.DbatoolsLog' -FallBack $env:temp

# Explanation #
#-------------#

In step a), which is run during module import, we assign the configuration of the name 'Path.DbatoolsLog' the value "$([System.Environment]::GetFolderPath("ApplicationData"))\PowerShell\dbatools"
Unless there already IS a value set to this name (that's what the '-Default' switch is doing).
That means, that if a user had a different configuration value in his profile, that value will win. Userchoice over preset.
ALL configurations defined by the module should be 'default' values.

In step b), which will be run whenever the function is called within which it is written, we retrieve the value stored behind the name 'Path.DbatoolsLog'.
If there is nothing there (for example, if the user accidentally removed or nulled the configuration), then it will fall back to using "$($env:temp)\dbatools.log"

#>

#region Paths
$script:path_RegistryUserDefault = "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default"
$script:path_RegistryUserEnforced = "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Enforced"
$script:path_RegistryMachineDefault = "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default"
$script:path_RegistryMachineEnforced = "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Enforced"
$psVersionName = "WindowsPowerShell"
if ($PSVersionTable.PSVersion.Major -ge 6) { $psVersionName = "PowerShell" }

#region User Local
if ($IsLinux -or $IsMacOs) {
    # Defaults to $Env:XDG_CONFIG_HOME on Linux or MacOS ($HOME/.config/)
    $fileUserLocal = $Env:XDG_CONFIG_HOME
    if (-not $fileUserLocal) { $fileUserLocal = Join-Path $HOME .config/ }

    $script:path_FileUserLocal = Join-DbaPath $fileUserLocal $psVersionName "dbatools/"
} else {
    # Defaults to $localappdatapath on Windows
    if ($env:LOCALAPPDATA) {
        $localappdatapath = $env:LOCALAPPDATA
    } else {
        $localappdatapath = [System.Environment]::GetFolderPath("LocalApplicationData")
    }
    $script:path_FileUserLocal = Join-Path $localappdatapath "$psVersionName\dbatools\Config"
    if (-not $script:path_FileUserLocal) { $script:path_FileUserLocal = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "$psVersionName\dbatools\Config" }
}
#endregion User Local

#region User Shared
if ($IsLinux -or $IsMacOs) {
    # Defaults to the first value in $Env:XDG_CONFIG_DIRS on Linux or MacOS (or $HOME/.local/share/)
    # Defaults to $HOME .local/share/
    # It previously was picking the first value in $Env:XDG_CONFIG_DIRS, but was causing and exception with ubuntu and xdg, saying that access to path /etc/xdg/xdg-ubuntu is denied.
    $fileUserShared = Join-Path $HOME .local/share/

    $script:path_FileUserShared = Join-DbaPath $fileUserShared $psVersionName "dbatools/"
    $script:AppData = $fileUserShared
} else {
    # Defaults to [System.Environment]::GetFolderPath("ApplicationData") on Windows
    $script:path_FileUserShared = Join-DbaPath $([System.Environment]::GetFolderPath("ApplicationData")) $psVersionName "dbatools" "Config"
    $script:AppData = [System.Environment]::GetFolderPath("ApplicationData")
    if (-not $([System.Environment]::GetFolderPath("ApplicationData"))) {
        $script:path_FileUserShared = Join-DbaPath $([Environment]::GetFolderPath("ApplicationData")) $psVersionName "dbatools" "Config"
        $script:AppData = [System.Environment]::GetFolderPath("ApplicationData")
    }
}
#endregion User Shared

#region System
if ($IsLinux -or $IsMacOs) {
    # Defaults to /etc/xdg elsewhere
    $XdgConfigDirs = $Env:XDG_CONFIG_DIRS -split ([IO.Path]::PathSeparator) | Where-Object { $_ -and (Test-Path $_) }
    if ($XdgConfigDirs.Count -gt 1) { $basePath = $XdgConfigDirs[1] }
    else { $basePath = "/etc/xdg/" }
    $script:path_FileSystem = Join-DbaPath $basePath $psVersionName "dbatools/"
} else {
    # Defaults to $Env:ProgramData on Windows
    $script:path_FileSystem = Join-DbaPath $Env:ProgramData $psVersionName "dbatools" "Config"
    if (-not $script:path_FileSystem) { $script:path_FileSystem = Join-DbaPath ([Environment]::GetFolderPath("CommonApplicationData")) $psVersionName "dbatools" "Config" }
}
#endregion System

#region Special Paths
# $script:AppData is already OS localized
$script:path_Logging = Join-DbaPath $script:AppData $psVersionName "dbatools" "Logs"
$script:path_typedata = Join-DbaPath $script:AppData $psVersionName "dbatools" "TypeData"
#endregion Special Paths
#endregion Paths

# Determine Registry Availability
$script:NoRegistry = $false
if (($PSVersionTable.PSVersion.Major -ge 6) -and ($PSVersionTable.OS -notlike "*Windows*")) {
    $script:NoRegistry = $true
}

$configpath = Resolve-Path "$script:PSModuleRoot\internal\configurations"

# Import configuration validation
foreach ($file in (Get-ChildItem -Path (Resolve-Path "$configpath\validation"))) {
    if ($script:doDotSource) { . $file.FullName }
    else { . ([scriptblock]::Create([io.file]::ReadAllText($file.FullName))) }
}

# Import other configuration files
foreach ($file in (Get-ChildItem -Path (Resolve-Path "$configpath\settings"))) {
    if ($script:doDotSource) { . $file.FullName }
    else { . ([scriptblock]::Create([io.file]::ReadAllText($file.FullName))) }
}

if (-not [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::ImportFromRegistryDone) {
    # Read config from all settings
    $config_hash = Read-DbatoolsConfigPersisted -Scope 127

    foreach ($value in $config_hash.Values) {
        try {
            if (-not $value.KeepPersisted) { Set-DbatoolsConfig -FullName $value.FullName -Value $value.Value -EnableException }
            else { Set-DbatoolsConfig -FullName $value.FullName -PersistedValue $value.Value -PersistedType $value.Type -EnableException }
            [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$value.FullName.ToLowerInvariant()].PolicySet = $value.Policy
            [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$value.FullName.ToLowerInvariant()].PolicyEnforced = $value.Enforced
        } catch { }
    }

    if ($null -ne $global:dbatools_config) {
        if ($global:dbatools_config.GetType().FullName -eq "System.Management.Automation.ScriptBlock") {
            [System.Management.Automation.ScriptBlock]::Create($global:dbatools_config.ToString()).Invoke()
        }
    }

    [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::ImportFromRegistryDone = $true
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUDVqt4jThtzAUj3NITUrCuDWB
# Q/OgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFOsZAKtzSH6QofpDHpB5+EWTyPzEMA0G
# CSqGSIb3DQEBAQUABIIBABa/cuIS5YiNzKCEgLWZoKbAXWB7VOBLYWQFL+FiM9Rz
# qKjgVtymbJdY/rSwtofyqkBGgAj77EVvaJsdxeTDgsdJCoX7Ej/+6rK5xw5/sQqz
# WC6fTmAqnmNbw/b1DyUXBqxh1DcJIVxbtBgVEu6W7VA9mLbQJa7ZzeRfCrmzgg0i
# SYTPpsPh4I5FsLms49ddQycXj8JOU+llUC9RdIoauUw1d5VMCIJ7MNcEB4eYdQcO
# QzcnJeNFXDcQI3gDneYZ8XiH8lyeqixoy9/qouSyx60aMlLR8MggAz/0eTUYi6Ra
# gFgsXFs4DVmbAHHOimxrA8EdB8xowaPoHEX8Ybuxq/+hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDM2WjAvBgkqhkiG9w0BCQQxIgQgQBpxfQ7OWCYHi8byL0c7
# TCHjFGxBdpVHiJj1dM7MK/EwDQYJKoZIhvcNAQEBBQAEggIAPIxwcCO4WaTbnypZ
# 4+zjlXFj5Otga/jkHAKSxd4u4A4OHjT8QhsSmqJ+wmPgQmT48czTbZNy4BIgTCjC
# c1BuMZXkNlFZw/r4o9c0+FkZvQ2oMb32gz686WF1aKD020Z5LvXUiKizrxrExIrp
# B3BKR7G4yNKosLMtgd3PBB8DIJu+INxsQTL6ACUSBP6l3LplZO6RrG3PbV6qSCdm
# IG40GtQFhuQxn1cm3XSfYxOS7AWCUvBnhT7zHj5QcAHGx3deG0Y+GxvaZ9QG78Pk
# uRV7zmzh1q8P9T9KitnIHaaYCtvLEGrZpFUz6FGaBKaDggerZQZZHJNx536R5Z97
# FnbKa35VGlb//GKQby+BLFZEWdDm5y/k/df8KxjbJPX82cFzl34hymUWxaa5/w9g
# wNMKB0n9y5NonoWssjs5s4xUNDOxNCo0KAykLRIUGRHNhQ0Eg4/uRYBrWXObXSv9
# SqtjuR5WOXYKCMkEpzrH4cDNyW8+1bLPhiCE+u4ckR3HP9VPKTqFNIv6Ont2y/h2
# Wx+Qs2ZkaNAvAr+Z0/O47XrKg/me52yoErDKCFo5NpwZ8rasWUT1NUaCEQO/Xdqp
# Z7ew3twb+yAN57lk2HTVGtIsr+Crm4xVZQ4M1ktyzD+4wZzbO2YWmmr1gv2L3spY
# wknUScgCQA8pCg4gF61o+Mwaz6Q=
# SIG # End signature block
