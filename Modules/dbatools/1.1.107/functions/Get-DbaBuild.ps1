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
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBIfeWYwKDLSfcA
# Pa8hfCAnekt8ASyFcIBYb0H/JF4kNaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBWiQmIEP6DJjvTdBVLscg39CAKDlEtwG1I
# muh8vgqcUTANBgkqhkiG9w0BAQEFAASCAQBGz1S4Py/Es2BFTTXTInSpxoJI60tZ
# tIB1QaVDd+fYA6syMlLcyoDidCxGg64mrIFoTrkDE7DVPyX1lsWa9YaNgnRzX8bG
# SnuhRZZumCj7/i0vENfHKWJQ6atIZqyvMDHwLl2EiZKoUN7skVlUe28geW76BsLf
# yEj2+e6y5dby+S4SADkXaZvhgu0c8jP/EaBm2svfcHAQaGy1Fn0BtO+2YQsdvF3t
# +xqHTh5GchYFwpaAvwZ5QHJ6lzjQw2YXwXNCmtPBCqocJYiLwlo0sjr8GoNw2cFZ
# gwf8cpU58CZoDwBcljcpndbMu6q7owc6Syhc9kaGR/WtNLzZgMxWKykNoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI1MVowLwYJKoZIhvcNAQkEMSIEILAU/1iT
# Ijar8sWD2lBk/nj/7LeEdv7oOqOMRPAcsndRMA0GCSqGSIb3DQEBAQUABIICAEw3
# 9DbccJqhGU9TrTcCSfqZB9cCBfcVU+5Xd+a1L20y8jk7DZPOluWTGLUBG8a7H281
# xm+Nx8pO3U4fLN7OjRX8D8T9CdtRisSSWcyNuQPbv0xRbKixedhjXdrFMIEUUF+m
# ipaPZYnKYND5yE1pJWXDT9emKr9gHU41U1HKOm2NoeAjmD2bTa2q+K1Bnw9hw87/
# g1XLQlw9pB53i3ApCJnwajQi1T0G2iUer1AZTw9ltt11So28ou7HWScENBdKmtXT
# 2y0uh+lwo//vD3wmeOzHJBevWcmbDZv4f4FyVZ6yJtGJ/2L0JSIbd0e1xp0ngP0O
# ExrfdyFsKmxBSCOmpCKtgJ0F0XTbdKHnKryXM73HF5GLPAf0X2CJEubZ68buYJSM
# 4ejGG9AL8PPWkspjhyTm/eLj9CJXWV0VgBlw4io7zIDhLuZy6nQL7fLNQrQAcqr5
# ViCThG4TH+hKoRH7URBHH5HJhJBVbifxmYiyFsKOw9dy5VylXpAIENG8nQM8cA8c
# MI04PnVK/airVKtKUd6+zYIpCk1m7UOn9l/frMnfrkwwxtfDV+OgMTiptKORRpJU
# UcIvNWBTYR4suQX341TaBOBT9hYoQQH270fnYgetDzSta+qie5xHE5xFT75EA2R5
# yePaiuoiQB/wcyRM3BdHfy/N0MVXuyco5WnuTrZ8
# SIG # End signature block
