function Test-DbaCmConnection {
    <#
    .SYNOPSIS
        Tests over which paths a computer can be managed.

    .DESCRIPTION
        Tests over which paths a computer can be managed.

        This function tries out the connectivity for:
        - Cim over WinRM
        - Cim over DCOM
        - Wmi
        - PowerShellRemoting
        Results will be written to the connectivity cache and will cause Get-DbaCmObject and Invoke-DbaCmMethod to connect using the way most likely to succeed. This way, it is likely the other commands will take less time to execute. These others too cache their results, in order to dynamically update connection statistics.

        This function ignores global configuration settings limiting which protocols may be used.

    .PARAMETER ComputerName
        The computer to test against.

    .PARAMETER Credential
        The credentials to use when running the test. Bad credentials are automatically cached as non-working. This behavior can be disabled by the 'Cache.Management.Disable.BadCredentialList' configuration.

    .PARAMETER Type
        The connection protocol types to test.
        By default, all types are tested.

        Note that this function will ignore global configurations limiting the types of connections available and test all connections specified here instead.

        Available connection protocol types: "CimRM", "CimDCOM", "Wmi", "PowerShellRemoting"

    .PARAMETER Force
        If this switch is enabled, the Alert will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ComputerManagement, CIM
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        **This function should not be called from within dbatools. It is meant as a tool for users only.**

    .LINK
        https://dbatools.io/Test-DbaCmConnection

    .EXAMPLE
        PS C:\> Test-DbaCmConnection -ComputerName sql2014

        Performs a full-spectrum connection test against the computer sql2014. The results will be reported and registered. Future calls from Get-DbaCmObject will recognize the results and optimize the query.

    .EXAMPLE
        PS C:\> Test-DbaCmConnection -ComputerName sql2014 -Credential $null -Type CimDCOM, CimRM

        This test will run a connectivity test of CIM over DCOM and CIM over WinRM against the computer sql2014 using Windows Authentication.

        The results will be reported and registered. Future calls from Get-DbaCmObject will recognize the results and optimize the query.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWMICmdlet", "", Justification = "Using Get-WmiObject is used as a fallback for testing connections")]
    param (
        [Parameter(ValueFromPipeline)]
        [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Sqlcollaborative.Dbatools.Connection.ManagementConnectionType[]]$Type = @("CimRM", "CimDCOM", "Wmi", "PowerShellRemoting"),
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        #region Configuration Values
        $disable_cache = Get-DbatoolsConfigValue -Name "ComputerManagement.Cache.Disable.All" -Fallback $false
        #Variable marked as unused by PSScriptAnalyzer
        #$disable_badcredentialcache = Get-DbatoolsConfigValue -Name "ComputerManagement.Cache.Disable.BadCredentialList" -Fallback $false
        #endregion Configuration Values

        #region Helper Functions
        function Test-ConnectionCimRM {
            [CmdletBinding()]
            param (
                [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter]
                $ComputerName,

                [System.Management.Automation.PSCredential]
                $Credential
            )

            try {
                #Variable $os marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = $ComputerName.Connection.GetCimRMInstance($Credential, "Win32_OperatingSystem", "root\cimv2")

                New-Object PSObject -Property @{
                    Success       = "Success"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            } catch {
                if (($_.Exception.InnerException -eq 0x8007052e) -or ($_.Exception.InnerException -eq 0x80070005)) {
                    New-Object PSObject -Property @{
                        Success       = "Error"
                        Timestamp     = Get-Date
                        Authenticated = $false
                    }
                } else {
                    New-Object PSObject -Property @{
                        Success       = "Error"
                        Timestamp     = Get-Date
                        Authenticated = $true
                    }
                }
            }
        }

        function Test-ConnectionCimDCOM {
            [CmdletBinding()]
            param (
                [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter]
                $ComputerName,

                [System.Management.Automation.PSCredential]
                $Credential
            )

            try {
                #Variable $os marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = $ComputerName.Connection.GetCimDComInstance($Credential, "Win32_OperatingSystem", "root\cimv2")

                New-Object PSObject -Property @{
                    Success       = "Success"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            } catch {
                if (($_.Exception.InnerException -eq 0x8007052e) -or ($_.Exception.InnerException -eq 0x80070005)) {
                    New-Object PSObject -Property @{
                        Success       = "Error"
                        Timestamp     = Get-Date
                        Authenticated = $false
                    }
                } else {
                    New-Object PSObject -Property @{
                        Success       = "Error"
                        Timestamp     = Get-Date
                        Authenticated = $true
                    }
                }
            }
        }

        function Test-ConnectionWmi {
            [CmdletBinding()]
            param (
                [string]
                $ComputerName,

                [System.Management.Automation.PSCredential]
                $Credential
            )

            try {
                #Variable $os marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = Get-WmiObject -ComputerName $ComputerName -Credential $Credential -Class Win32_OperatingSystem -ErrorAction Stop
                New-Object PSObject -Property @{
                    Success       = "Success"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            } catch [System.UnauthorizedAccessException] {
                New-Object PSObject -Property @{
                    Success       = "Error"
                    Timestamp     = Get-Date
                    Authenticated = $false
                }
            } catch {
                New-Object PSObject -Property @{
                    Success       = "Error"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            }
        }

        function Test-ConnectionPowerShellRemoting {
            [CmdletBinding()]
            param (
                [string]
                $ComputerName,

                [System.Management.Automation.PSCredential]
                $Credential
            )

            try {
                $parameters = @{
                    ScriptBlock  = { Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop }
                    ComputerName = $ComputerName
                    ErrorAction  = 'Stop'
                }
                if ($Credential) { $parameters["Credential"] = $Credential }
                #Variable $os marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = Invoke-Command @parameters

                New-Object PSObject -Property @{
                    Success       = "Success"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            } catch {
                # Will always consider authenticated, since any call with credentials to a server that doesn't exist will also carry invalid credentials error.
                # There simply is no way to differentiate between actual authentication errors and server not reached
                New-Object PSObject -Property @{
                    Success       = "Error"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            }
        }
        #endregion Helper Functions
    }
    process {
        foreach ($ConnectionObject in $ComputerName) {
            if (-not $ConnectionObject.Success) { Stop-Function -Message "Failed to interpret input: $($ConnectionObject.Input)" -Category InvalidArgument -Target $ConnectionObject.Input -Continue }

            $Computer = $ConnectionObject.Connection.ComputerName.ToLowerInvariant()
            Write-Message -Level VeryVerbose -Message "[$Computer] Testing management connection"

            #region Setup connection object
            $con = $ConnectionObject.Connection
            #endregion Setup connection object

            #region Handle credentials
            #Variable marked as unused by PSScriptAnalyzer
            #$BadCredentialsFound = $false
            if ($con.DisableBadCredentialCache) { $con.KnownBadCredentials.Clear() }
            elseif ($con.IsBadCredential($Credential) -and (-not $Force)) {
                Stop-Function -Message "[$Computer] The credentials supplied are on the list of known bad credentials, skipping. Use -Force to override this." -Continue -Category InvalidArgument -Target $Computer
            } elseif ($con.IsBadCredential($Credential) -and $Force) {
                $con.RemoveBadCredential($Credential)
            }
            #endregion Handle credentials

            #region Connectivity Tests
            :types foreach ($ConnectionType in $Type) {
                switch ($ConnectionType) {
                    #region CimRM
                    "CimRM" {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using CIM over WinRM"
                        $res = Test-ConnectionCimRM -ComputerName $con -Credential $Credential
                        $con.LastCimRM = $res.Timestamp
                        $con.CimRM = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] CIM over WinRM Results | Success: $($res.Success), Authentication: $($res.Authenticated)"

                        if (-not $res.Authenticated) {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests"
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion CimRM

                    #region CimDCOM
                    "CimDCOM" {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using CIM over DCOM."
                        $res = Test-ConnectionCimDCOM -ComputerName $con -Credential $Credential
                        $con.LastCimDCOM = $res.Timestamp
                        $con.CimDCOM = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] CIM over DCOM Results | Success: $($res.Success), Authentication: $($res.Authenticated)"

                        if (-not $res.Authenticated) {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests."
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion CimDCOM

                    #region Wmi
                    "Wmi" {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using WMI."
                        $res = Test-ConnectionWmi -ComputerName $Computer -Credential $Credential
                        $con.LastWmi = $res.Timestamp
                        $con.Wmi = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] WMI Results | Success: $($res.Success), Authentication: $($res.Authenticated)"

                        if (-not $res.Authenticated) {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests"
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion Wmi

                    #region PowerShell Remoting
                    "PowerShellRemoting" {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using PowerShell Remoting."
                        $res = Test-ConnectionPowerShellRemoting -ComputerName $Computer -Credential $Credential
                        $con.LastPowerShellRemoting = $res.Timestamp
                        $con.PowerShellRemoting = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] PowerShell Remoting Results | Success: $($res.Success)"
                    }
                    #endregion PowerShell Remoting
                }
            }
            #endregion Connectivity Tests

            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$Computer] = $con }
            $con
        }
    }
    end {

    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUs0IIqmM2ZQH5l7RwWLMteXRd
# wbGgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPygIRVJ69Lw3v3V/Kfmkw8fdfvNMA0G
# CSqGSIb3DQEBAQUABIIBAAxdgF2BsDXJn0yIhqMr7Btf222bnFRXnHGTOyMhD+Iw
# 47f4SWLUEMIDmJQZfU0743dIcMjaR/tZtr9s+vrahdYTK5oQAbm/U8F/9ckNNTJz
# s1fo+BDFTQhs8vWxUZ9+c+c3K7yOqzZZGjgDVspAwceZZrO63EYyh3dXg7IPPoEQ
# XwZV5wzlXdiDvIB61BRmG0kcYrpFOotRFFfkGQ1GyNlkWWJLPbCUzu1cWLO7fM3a
# Hhy2+q/fM4zeP/LPaTs0oHEA/+fxEmI3OZr7daPOmRSGLoWyZhmLxbJcdyfLgXpp
# IqpxEoxUafAqiWIQesPFW2jUEM33BwV5qpMb3zvRP02hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDI3WjAvBgkqhkiG9w0BCQQxIgQgyEQQ2B2bgPrLldl9Fx4y
# e5tm5jY+26AZc9nS2B7JM94wDQYJKoZIhvcNAQEBBQAEggIAIJY0E+Q6NsB50C23
# pPj/SmVa6TVl2x30o+N5AK09SCKbK71dgNT7AE7ZLfeZEeiUebW5RNr3r3CxDHf2
# cQ5gM3zjIdUyecRTPvubOknVUFmAnYRu2EMBtJQ7sg7ZjvLyombqK9ovR+OnRD14
# lK/XnH4vcJmrCOxwjsM6wUb6Pjz6HfRnv6WicHLrNSs9BdBdUobfYU5dRMB1kq6G
# 2BWBfW13oH36rr1Inw6a9xYSKpXLuGrBZVptOHSWOT9uHdKEk5d8de8RNdJPaK8R
# Qvz4SZejzx0g3zOZrwh22sSHUEAMHYwy6Z4xFciTGBPgffqGCvJob8viHxOZ8pn3
# jb2NIEJjJq5kO68VBYxM6oDjpSzEJTv2UJXkC+QorD7ABHNUWT9OssqzHQ6UQbj7
# skAHohPwS1Ak9HL7HRK/0eip2vCvSO3Vqz5GeGQsm0TGes+MMIJyL+q3gC3uIWFo
# eJ/wYFNcNC2yHMABA6E1Vuzrw6p6zDPRanTAjuR6V6pz5rZv+nWqcb0blGu/Ha+d
# 4xh8YIDAIi2e33H7z8kMBIZ7+jC7eKpSHjKvKGua9br9BlZ8ba/YOYIEFSEwjicY
# 7sJpECB/fo6BLvKZ5H/8IomzBk+oeB8oWi1xrXpfcfYO/j89YtAaWBPOAffWo7oG
# UVR5rOgdNMi+Q1nlInidlpSXQe8=
# SIG # End signature block
