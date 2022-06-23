function Get-DbaBuild {
    <#
    .SYNOPSIS
        Returns SQL Server Build infos on a SQL instance

    .DESCRIPTION
        Returns info about the specific build of a SQL instance, including the SP, the CU and the reference KB, wherever possible.
        It also includes End Of Support dates as specified on Microsoft Life Cycle Policy

    .PARAMETER Build
        Instead of connecting to a real instance, pass a string identifying the build to get the info back.

    .PARAMETER Kb
        Get a KB information based on its number. Supported format: KBXXXXXX, or simply XXXXXX.

    .PARAMETER MajorVersion
        Get a KB information based on SQL Server version. Can be refined further by -ServicePack and -CumulativeUpdate parameters.
        Examples: SQL2008 | 2008R2 | 2016

    .PARAMETER ServicePack
        Get a KB information based on SQL Server Service Pack version. Can be refined further by -CumulativeUpdate parameter.
        Examples: SP0 | 2 | RTM

    .PARAMETER CumulativeUpdate
        Get a KB information based on SQL Server Cumulative Update version.
        Examples: CU0 | CU13 | CU0

    .PARAMETER SqlInstance
        Target any number of instances, in order to return their build state.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Update
        Adding this switch will look online for the most up to date reference, optionally replacing the local one.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlBuild, Utility
        Author: Simone Bizzotto (@niphold) | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaBuild

    .EXAMPLE
        PS C:\> Get-DbaBuild -Build "12.00.4502"

        Returns information about a build identified by  "12.00.4502" (which is SQL 2014 with SP1 and CU11)

    .EXAMPLE
        PS C:\> Get-DbaBuild -Build "12.00.4502" -Update

        Returns information about a build trying to fetch the most up to date index online. When the online version is newer, the local one gets overwritten

    .EXAMPLE
        PS C:\> Get-DbaBuild -Build "12.0.4502","10.50.4260"

        Returns information builds identified by these versions strings

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a | Get-DbaBuild

        Integrate with other cmdlets to have builds checked for all your registered servers on sqlserver2014a

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Build')]
    param (
        [version[]]
        $Build,

        [string[]]
        $Kb,

        [ValidateNotNullOrEmpty()]
        [string]
        $MajorVersion,

        [ValidateNotNullOrEmpty()]
        [string]
        [Alias('SP')]
        $ServicePack = 'RTM',

        [string]
        [Alias('CU')]
        $CumulativeUpdate,

        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance,

        [PsCredential]
        $SqlCredential,

        [switch]
        $Update,

        [switch]$EnableException
    )

    begin {

        #region verifying parameters
        $isPipelineSqlInstance = $PSCmdlet.MyInvocation.ExpectingInput
        $ComplianceSpec = @()
        $ComplianceSpecExclusiveParams = @('Build', 'Kb', @( 'MajorVersion', 'ServicePack', 'CumulativeUpdate'), 'SqlInstance')
        foreach ($exclParamGroup in $ComplianceSpecExclusiveParams) {
            foreach ($exclParam in $exclParamGroup) {
                if ($exclParam -eq 'SqlInstance') {
                    if ($isPipelineSqlInstance -or (Test-Bound -ParameterName 'SqlInstance')) {
                        $ComplianceSpec += $exclParam
                    }
                } else {
                    if (Test-Bound -ParameterName $exclParam) {
                        $ComplianceSpec += $exclParam
                        break
                    }
                }
            }
        }
        if ($ComplianceSpec.Length -eq 0 -and (Test-Bound -Not -ParameterName 'Update') -and (-not($isPipelineSqlInstance))) {
            Stop-Function -Category InvalidArgument -Message "You need to choose at least one parameter."
            return
        }
        if ($ComplianceSpec.Length -gt 1) {
            Stop-Function -Category InvalidArgument -Message "$($ComplianceSpec -join ', ') are mutually exclusive. Please choose one or the other. Quitting."
            return
        }
        if (((Test-Bound -ParameterName 'ServicePack') -or (Test-Bound -ParameterName 'CumulativeUpdate')) -and (Test-Bound -Not -ParameterName 'MajorVersion')) {
            Stop-Function -Category InvalidArgument -Message "-MajorVersion is required when specifying SP or CU."
            return
        }
        if ($MajorVersion) {
            if ($MajorVersion -match '^(SQL)?(\d{4}(R2)?)$') {
                $MajorVersion = $Matches[2]
            } else {
                Stop-Function -Message "Incorrect SQL Server version format: use SQL2XXX or just 2XXXX - SQL2012, SQL2008R2"
                return
            }
            if (!$ServicePack) {
                $ServicePack = 'RTM'
            }
            if ($ServicePack -match '^(SP)?\s*(\d+)$') {
                if ($Matches[2] -eq '0') {
                    $ServicePack = 'RTM'
                } else {
                    $ServicePack = 'SP' + $Matches[2]
                }
            } elseif ($ServicePack -notmatch '^RTM$') {
                Stop-Function -Message "Incorrect SQL Server service pack format: use SPX, X or RTM, where X is a service pack number"
                return
            }
            if ($CumulativeUpdate) {
                if ($CumulativeUpdate -match '^(CU)?\s*(\d+)$') {
                    if ($Matches[2] -eq '0') {
                        $CumulativeUpdate = ''
                    } else {
                        $CumulativeUpdate = 'CU' + $Matches[2]
                    }
                } else {
                    Stop-Function -Message "Incorrect SQL Server cumulative update format: use CUX or X, where X is a cumulative update number"
                    return
                }
            }
        }
        #endregion verifying parameters

        #region Helper functions
        function Get-DbaBuildReferenceIndex {
            [CmdletBinding()]
            param (
                [string]
                $Moduledirectory,

                [bool]
                $Update,

                [bool]
                $EnableException
            )

            $orig_idxfile = Resolve-Path "$Moduledirectory\bin\dbatools-buildref-index.json"
            $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
            $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"

            if (-not (Test-Path $orig_idxfile)) {
                Write-Message -Level Warning -Message "Unable to read local SQL build reference file. Please check your module integrity or reinstall dbatools."
            }

            if ((-not (Test-Path $orig_idxfile)) -and (-not (Test-Path $writable_idxfile))) {
                throw "Build reference file not found, please check module health."
            }

            # If no writable copy exists, create one and return the module original
            if (-not (Test-Path $writable_idxfile)) {
                Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                $result = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
            }

            # Else, if both exist, update the writeable if necessary and return the current version
            elseif (Test-Path $orig_idxfile) {
                $module_content = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
                $data_content = Get-Content $writable_idxfile -Raw | ConvertFrom-Json

                $module_time = Get-Date $module_content.LastUpdated
                $data_time = Get-Date $data_content.LastUpdated

                if ($module_time -gt $data_time) {
                    Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                    $result = $module_content
                } else {
                    $result = $data_content
                }
                # If Update is passed, try to fetch from online resource and store into the writeable
                if ($Update) {
                    Update-DbaBuildReference -EnableException -ErrorAction Stop
                }
            }

            # Else if the module version of the file no longer exists, but the writable version exists, return the writable version
            else {
                $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
            }

            $LastUpdated = Get-Date -Date $result.LastUpdated
            if ($LastUpdated -lt (Get-Date).AddDays(-45)) {
                Write-Message -Level Warning -Message "Index is stale, last update on: $(Get-Date -Date $LastUpdated -Format s), try the -Update parameter to fetch the most up to date index"
            }

            $result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
        }


        function Resolve-DbaBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            [OutputType([System.Collections.Hashtable])]
            param (
                [Parameter(Mandatory, ParameterSetName = 'Build')]
                [version]
                $Build,

                [Parameter(Mandatory, ParameterSetName = 'KB')]
                [string]
                $Kb,

                [Parameter(Mandatory, ParameterSetName = 'HFLevel')]
                [string]
                $MajorVersion,

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('SP')]
                $ServicePack = 'RTM',

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('CU')]
                $CumulativeUpdate,

                $Data,

                [bool]
                $EnableException
            )

            if ($Build) {
                Write-Message -Level Verbose -Message "Looking for $Build"

                $IdxVersion = $Data | Where-Object Version -like "$($Build.Major).$($Build.Minor).*"
            } elseif ($Kb) {
                Write-Message -Level Verbose -Message "Looking for KB $Kb"
                if ($Kb -match '^(KB)?(\d+)$') {
                    $currentKb = $Matches[2]
                    $kbVersion = $Data | Where-Object KBList -contains $currentKb
                    $IdxVersion = $Data | Where-Object Version -like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
                } else {
                    Stop-Function -Message "Wrong KB name $kb"
                    return
                }
            } elseif ($MajorVersion) {
                Write-Message -Level Verbose -Message "Looking for SQL $MajorVersion SP $ServicePack CU $CumulativeUpdate"
                $kbVersion = $Data | Where-Object Name -eq $MajorVersion
                $IdxVersion = $Data | Where-Object Version -like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
            }

            $Detected = @{ }
            $Detected.MatchType = 'Approximate'
            $idxCount = $IdxVersion | Measure-Object | Select-Object -ExpandProperty Count
            Write-Message -Level Verbose -Message "We have $idxCount builds in store for this Release"
            If ($idxCount -eq 0) {
                Write-Message -Level Warning -Message "No info in store for this Release"
                $Detected.Warning = "No info in store for this Release"
            } else {
                $LastVer = $IdxVersion[0]
            }
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.Name) {
                    $Detected.Name = $el.Name
                }
                if ($Build -and $el.VersionObject -gt $Build) {
                    $Detected.MatchType = 'Approximate'
                    $Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
                    break
                }
                $LastVer = $el
                $Detected.BuildLevel = $el.VersionObject
                if ($null -ne $el.SP) {
                    $Detected.SP = $el.SP
                    $Detected.CU = $null
                }
                if ($null -ne $el.CU) {
                    $Detected.CU = $el.CU
                }
                if ($null -ne $el.SupportedUntil) {
                    $Detected.SupportedUntil = (Get-Date -date $el.SupportedUntil)
                }
                $Detected.Build = $el.Version
                $Detected.KB = $el.KBList
                if (($Build -and $el.Version -eq $Build) -or ($Kb -and $el.KBList -eq $currentKb)) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                } elseif ($MajorVersion -and $Detected.SP -contains $ServicePack -and (!$CumulativeUpdate -or ($el.CU -and $el.CU -eq $CumulativeUpdate))) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                }
            }
            return $Detected
        }
        #endregion Helper functions

        $moduledirectory = $script:PSModuleRoot

        try {
            $IdxRef = Get-DbaBuildReferenceIndex -Moduledirectory $moduledirectory -Update $Update -EnableException $EnableException
        } catch {
            Stop-Function -Message "Error loading SQL build reference" -ErrorRecord $_
            return
        }
    }
    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            #region Ensure the connection is established
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $null = $server.Version.ToString()
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            #endregion Ensure the connection is established

            $Detected = Resolve-DbaBuild -Build $server.Version -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $server.DomainInstanceName
                Build          = $server.Version
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            }
        }

        foreach ($buildstr in $Build) {
            $Detected = Resolve-DbaBuild -Build $buildstr -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $buildstr
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }

        foreach ($kbItem in $Kb) {
            $Detected = Resolve-DbaBuild -Kb $kbItem -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $Detected.Build
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }

        if ($MajorVersion) {
            $Detected = Resolve-DbaBuild -MajorVersion $MajorVersion -ServicePack $ServicePack -CumulativeUpdate $CumulativeUpdate -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $Detected.Build
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUpXO/M4duWdE2EwV3DlunArvK
# msKgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFLFSXIONu+6i3s8AO7vuoiaKyLjmMA0G
# CSqGSIb3DQEBAQUABIIBALpvCyjH9B2dT4mA4yh4B9llUn9V7HHDX/yEq7tOUQg1
# nossSG27wVhGh1aMZS2KCkIX258uOV6CFz6tlD1r2pnJAzrBYlVIVziBwo0VqRiz
# TN8u+9Ge/YxywAk49D1LO0t6J9MgH1mG6n35iSho+ud+nDJo++wCnIAJytAYI3h4
# Unz91uRiIP9oIRItmaOgc+xFB4AACET0nfbY7gBn8f5cJ9y3PbveFZJ5wh1eKrH7
# 2cis4KwNyiL58h28zuXcWz2j9ubswYaeftLhHkXrtERfW8A6muQpJu7nffhE50jq
# +cA1t2e2kpUDVcGSfyvAesED9PiNK2cyv9qzDbhxZLKhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzI1WjAvBgkqhkiG9w0BCQQxIgQgUg0Km5es6XEvMWNAMotI
# A+kxGeteS5IoMz/OOiw0fhowDQYJKoZIhvcNAQEBBQAEggIAQHTdhReDrDI+s4wN
# 2kSSrMaY1MGFlwi5rfUYXEoJ279WwsOs/TOMgSBOC8Tqr3YyRg1aSXTzPMTP5G/C
# XizPI4wTGkUHbs76K4OezNfsOB2u+2h5iqYxIdbJ+8wQ0NQ/0tofqKrfrf3waTjR
# WeXiKB0KSE6PJDmYiLRRLrz87J064x3LJPnggJKmfH4poSqjTRCvgw1Oa+TJvZqH
# N0Nwh7fuBNFNFpnm0C0bpXnGsWafuTU24WafhhndAtE10bFgO4fWzHd9lU/057JJ
# rqfYsq2Cvzrp6E61oSqq3Kek8Zy5LNhestMwIN3dCWYpsJQtfAqPcOhDR3vMR40D
# uxjdvZ2lsy24GsC5UnKBsKznrTEaaND7TmMiXhgV0pCP7BS3Mmw1F+Yn0E819yIk
# 1EMCMZBoZjIG/DOIQ/h79vp2dIyaQkbftxJz0qeHa3MzODPgBEd+8Ati9zGAVe8L
# p1+6gtzECy/w006EeenQxsgAQHrcl/R/jlEUtrxBFnVxJ73WxBNBjDNnAGNXkciU
# cspTPfJmay2i+4Ug8U1OsDXWccGOTWz5/qGBTpablyaNJ5dZCyEhJFSCC1naOkFn
# JHmK6gn790d43K38yxrbol3GZixfBOkU1tVBxiFGW89w0pbZSUEyk3qsRFGluK8f
# sh7fMPg0uBhRFmz4EARvx19ORqc=
# SIG # End signature block
