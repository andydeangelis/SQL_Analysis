function Test-DbaBuild {
    <#
    .SYNOPSIS
        Returns SQL Server Build "compliance" level on a build.

    .DESCRIPTION
        Returns info about the specific build of a SQL instance, including the SP, the CU and the reference KB, End Of Support, wherever possible. It adds a Compliance property as true/false, and adds details about the "targeted compliance".
        The build data used can be found here: https://dbatools.io/builds

    .PARAMETER Build
        Instead of connecting to a real instance, pass a string identifying the build to get the info back.

    .PARAMETER MinimumBuild
        This is the build version to test "compliance" against. Anything below this is flagged as not compliant.

    .PARAMETER MaxBehind
        Instead of using a specific MinimumBuild here you can pass "how many service packs and cu back" is the targeted compliance level. You can use xxSP or xxCU or both, where xx is a number. See the Examples for more information.

    .PARAMETER Latest
        Shortcut for specifying the very most up-to-date build available.

    .PARAMETER SqlInstance
        Target any number of instances, in order to return their compliance state.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Update
        Looks online for the most up to date reference, replacing the local one.

    .PARAMETER Quiet
        Makes the function just return $true/$false. It's useful if you use Test-DbaBuild in your own scripts.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlBuild, Version, Utility
        Author: Simone Bizzotto (@niphold) | Friedrich Weinmann (@FredWeinmann)

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaBuild

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -MinimumBuild "12.0.5557"

        Returns information about a build identified by "12.0.5540" (which is SQL 2014 with SP2 and CU4), which is not compliant as the minimum required
        build is "12.0.5557" (which is SQL 2014 with SP2 and CU8).

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -MaxBehind "1SP"

        Returns information about a build identified by "12.0.5540", making sure it is AT MOST 1 Service Pack "behind". For that version,
        that identifies an SP2, means accepting as the lowest compliance version as "12.0.4110", that identifies 2014 with SP1.

        Output column CUTarget is not relevant (empty). SPTarget and BuildTarget are filled in the result.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -MaxBehind "1SP 1CU"

        Returns information about a build identified by "12.0.5540", making sure it is AT MOST 1 Service Pack "behind", plus 1 CU "behind". For that version,
        that identifies an SP2 and CU, rolling back 1 SP brings you to "12.0.4110", but given the latest CU for SP1 is CU13, the target "compliant" build
        will be "12.0.4511", which is 2014 with SP1 and CU12.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -MaxBehind "0CU"

        Returns information about a build identified by "12.0.5540", making sure it is the latest CU release.

        Output columns CUTarget, SPTarget and BuildTarget are relevant. If the latest build is a service pack (not a CU), CUTarget will be empty.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -Latest

        Returns information about a build identified by "12.0.5540", making sure it is the latest build available.

        Output columns CUTarget and SPTarget are not relevant (empty), only the BuildTarget is.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.00.4502" -MinimumBuild "12.0.4511" -Update

        Same as before, but tries to fetch the most up to date index online. When the online version is newer, the local one gets overwritten.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.4502","10.50.4260" -MinimumBuild "12.0.4511"

        Returns information builds identified by these versions strings.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a | Test-DbaBuild -MinimumBuild "12.0.4511"

        Integrate with other cmdlets to have builds checked for all your registered servers on sqlserver2014a.

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [version[]]$Build,
        [version]$MinimumBuild,
        [string]$MaxBehind,
        [switch] $Latest,
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$Update,
        [switch]$Quiet,
        [switch]$EnableException
    )

    begin {
        #region Helper functions
        function Get-DbaBuildReferenceIndex {
            [CmdletBinding()]

            $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
            $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"
            $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
            $result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
        }

        $ComplianceSpec = @()
        $ComplianceSpecExclusiveParams = @('MinimumBuild', 'MaxBehind', 'Latest')
        foreach ($exclParam in $ComplianceSpecExclusiveParams) {
            if (Test-Bound -Parameter $exclParam) { $ComplianceSpec += $exclParam }
        }
        if ($ComplianceSpec.Length -gt 1) {
            Stop-Function -Category InvalidArgument -Message "-MinimumBuild, -MaxBehind and -Latest are mutually exclusive. Please choose only one. Quitting."
            return
        }
        if ($ComplianceSpec.Length -eq 0) {
            Stop-Function -Category InvalidArgument -Message "You need to choose one from -MinimumBuild, -MaxBehind and -Latest. Quitting."
            return
        }
        if ($MaxBehind) {
            $MaxBehindValidator = [regex]'^(?<howmany>[\d]+)(?<what>SP|CU)$'
            $pieces = $MaxBehind.Split(' ')	| Where-Object { $_ }
            try {
                $ParsedMaxBehind = @{ }
                foreach ($piece in $pieces) {
                    $pieceMatch = $MaxBehindValidator.Match($piece)
                    if ($pieceMatch.Success -ne $true) {
                        Stop-Function -Message "MaxBehind has an invalid syntax ('$piece' could not be parsed correctly)" -ErrorRecord $_
                        return
                    } else {
                        $howmany = [int]$pieceMatch.Groups['howmany'].Value
                        $what = $pieceMatch.Groups['what'].Value
                        if ($ParsedMaxBehind.ContainsKey($what)) {
                            Stop-Function -Message "The specifier $what has been already passed" -ErrorRecord $_
                            return
                        } else {
                            $ParsedMaxBehind[$what] = $howmany
                        }
                    }
                }
                if (-not $ParsedMaxBehind.ContainsKey('SP')) {
                    $ParsedMaxBehind['SP'] = 0
                }
            } catch {
                Stop-Function -Message "Error parsing MaxBehind" -ErrorRecord $_
                return
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $hiddenProps = @()
        if (-not $SqlInstance) {
            $hiddenProps += 'SqlInstance'
        }
        if ($MinimumBuild) {
            $hiddenProps += 'MaxBehind', 'SPTarget', 'CUTarget', 'BuildTarget'
        } elseif ($MaxBehind -or $Latest) {
            $hiddenProps += 'MinimumBuild'
        }
        if ($Build) {
            $BuildVersions = Get-DbaBuild -Build $Build -Update:$Update -EnableException:$EnableException
        } elseif ($SqlInstance) {
            $BuildVersions = Get-DbaBuild -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Update:$Update -EnableException:$EnableException
        }
        # Moving it down here to only trigger after -Update was properly called
        if (!$IdxRef) {
            try {
                $IdxRef = Get-DbaBuildReferenceIndex
            } catch {
                Stop-Function -Message "Error loading SQL build reference" -ErrorRecord $_
                return
            }
        }
        foreach ($BuildVersion in $BuildVersions) {
            $inputbuild = $BuildVersion.Build
            $compliant = $false
            $targetSPName = $null
            $targetCUName = $null
            if ($BuildVersion.MatchType -eq 'Approximate') {
                Write-Message -Level Warning -Message "$($BuildVersion.Build) is not recognized as a correct version"
            }
            if ($MinimumBuild) {
                Write-Message -Level Debug -Message "Comparing $MinimumBuild to $inputbuild"
                if ($inputbuild -ge $MinimumBuild) {
                    $compliant = $true
                }
            } elseif ($MaxBehind -or $Latest) {
                $IdxVersion = $IdxRef | Where-Object Version -like "$($inputbuild.Major).$($inputbuild.Minor).*"
                $lastsp = ''
                $SPsAndCUs = @()
                foreach ($el in $IdxVersion) {
                    if ($null -ne $el.SP) {
                        $lastsp = $el.SP | Where-Object { $_ -ne 'LATEST' }
                        $SPsAndCUs += @{
                            VersionObject = $el.VersionObject
                            SP            = $lastsp
                        }
                    }
                    if ($null -ne $el.CU) {
                        $SPsAndCUs += @{
                            VersionObject = $el.VersionObject
                            SP            = $lastsp
                            CU            = $el.CU
                            Retired       = $el.Retired
                        }
                    }
                }
                $targetedBuild = $SPsAndCUs[0]
                if ($Latest) {
                    $targetedBuild = $IdxVersion[$IdxVersion.Length - 1]
                } else {
                    if ($ParsedMaxBehind.ContainsKey('SP')) {
                        [string[]]$AllSPs = $SPsAndCUs.SP | Select-Object -Unique
                        $targetSP = $AllSPs.Length - $ParsedMaxBehind['SP'] - 1
                        if ($targetSP -lt 0) {
                            $targetSP = 0
                        }
                        $targetSPName = $AllSPs[$targetSP]
                        Write-Message -Level Debug -Message "Target SP is $targetSPName - $targetSP on $($AllSPs.Length)"
                        $targetedBuild = $SPsAndCUs | Where-Object SP -eq $targetSPName | Select-Object -First 1
                    }
                    if ($ParsedMaxBehind.ContainsKey('CU')) {
                        [string[]]$AllCUs = ($SPsAndCUs | Where-Object VersionObject -gt $targetedBuild.VersionObject | Where-Object Retired -ne $true).CU | Select-Object -Unique
                        if ($AllCUs.Length -gt 0) {
                            #CU after the targeted build available
                            $targetCU = $AllCUs.Length - $ParsedMaxBehind['CU'] - 1
                            if ($targetCU -lt 0) {
                                $targetCU = 0
                            }
                            $targetCUName = $AllCUs[$targetCU]
                            Write-Message -Level Debug -Message "Target CU is $targetCUName - $targetCU on $($AllCUs.Length)"
                            $targetedBuild = $SPsAndCUs | Where-Object VersionObject -gt $targetedBuild.VersionObject | Where-Object CU -eq $targetCUName | Select-Object -First 1
                        }
                    }
                }
                if ($inputbuild -ge $targetedBuild.VersionObject) {
                    $compliant = $true
                }
            }
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name Compliant -Value $compliant
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name MinimumBuild -Value $MinimumBuild
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name MaxBehind -Value $MaxBehind
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name SPTarget -Value $targetSPName
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name CUTarget -Value $targetCUName
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name BuildTarget -Value $targetedBuild.VersionObject
            if ($Quiet) {
                $BuildVersion.Compliant
            } else {
                $BuildVersion | Select-Object * | Select-DefaultView -ExcludeProperty $hiddenProps
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUEVqKa4JpP8Wy4tWgbrguCdmy
# xfmgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFDQr2Ecb+bERg2iVuHYwkZmBJsZsMA0G
# CSqGSIb3DQEBAQUABIIBAB9pzBRd37h6vY9FeoBPE1HQAgZZ+gMGTUmiswG3zH5r
# qxZ623DHPxFz4Sl392R+BMgE+QcWw0gHcAUZAt3MYhQ4lyKb29so6UVE1U8+XJc6
# 4KMSYlbdJuGaZhxQjlIA8zcXF5LdXpt9oFfY1B01yCn2h0wpyx01lGT+KmfTlKc+
# eaC1invxzh/3o9/g86MaYhTPQJ8aCqSwWHG/emu3SrMyRYDtNMdTl2c3U7+lBS64
# pK0XN/8vHvpzWk18eUhzlkY6h9pfhLI7ccO0oe8+MbfIOUN5xvwLVjuxBJzf8ru9
# hokTQBZl/kPXYQmBhMO7bNmLDr7+IqqBlxXK6fc9BxKhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDI3WjAvBgkqhkiG9w0BCQQxIgQguzYD3pA+5Nim8mhKTk7b
# Nl8/asjKtqi/s7uu8MvITvcwDQYJKoZIhvcNAQEBBQAEggIAYF9fjUFE46GzOu27
# WHFEFL0LF0ENrprS0tNouCZcbF0XtRlfnZosM+9TNBEtdK9rnSEuq6E24STemsRd
# bkhlf7dyhHcibD2r9k2vYX4qDGlmBMQ2hiV22heh3pZdcrhEWnKBlVcGpSG742O/
# 3+XGCazPZ6XW9UsQBABFb3DWSbGqI+SmJ/d1M41pts7CoAPgwdIcL6PROjL2XGIb
# vV2ZWRgvRJI/VZlC/wRG3FZLBBJ4UCLmuMWZvY5uG0pRQFsTkSHHL9LDikgI7qVB
# Gm0OLbqeiYUvyfrzXAc0qXeaHo6i2kd2ZzAQ4GFaPQ8RmibJlbxMzw+sbkOUoC0n
# SwHqh2jI8UOJ7HB5tKDyUsT32C5qV45n0qu+8pYXij1wKvONwPW1Tg/C/IkHsxM0
# iY9GJ+sra9sVEBmd4Jd6UpeUHNrEsYyxhvwueBGW9cD9oQmlD9Aw4UbaHnsD1y5S
# hRf9gcrJGFDoVm1B/I+eS8uL3jMMHAl22Qyl/h15K4RXCSNPo3JuvWCaazSiCUk8
# BGN/ch+Wf9PSfFGINnR/+BBMeRB8rAm/NS4JNsCxlPw0zE2JoCHJjVl1l6VcbWAe
# LiALHYoviecXk+KrgAd7K/WtuaM9x43dHUw4NSRy7X4VNqc3GwE8wr/ilSPZhojN
# UVMOiFHR1vWKeRZmQjYsWEWKuc4=
# SIG # End signature block
