function Get-DbaHelp {
    <#
    .SYNOPSIS
        Massages inline help data to a more useful format

    .DESCRIPTION
        Takes the inline help and outputs a more usable object

    .PARAMETER Name
        The function/command to extract help from

    .PARAMETER OutputAs
        Output format (raw PSObject or MDString)

    .NOTES
    Author: Simone Bizzotto (@niphlod)

    Website: https://dbatools.io
    Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaHelp


    .EXAMPLE
        Get-DbaHelp Get-DbaDatabase

        Parses the inline help from Get-DbaDatabase and outputs the massaged object

    .EXAMPLE
        Get-DbaHelp Get-DbaDatabase -OutputAs "PSObject"

        Parses the inline help from Get-DbaDatabase and outputs the massaged object

    .EXAMPLE
        PS C:\> Get-DbaHelp Get-DbaDatabase -OutputAs "MDString" | Out-File Get-DbaDatabase.md
        PS C:\> & code Get-DbaDatabase.md

        Parses the inline help from Get-DbaDatabase as MarkDown, saves the file and opens it
        via VSCode

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]$Name,

        [ValidateSet("PSObject", "MDString")]
        [string]$OutputAs = "PSObject"
    )

    begin {
        function Get-DbaTrimmedString($Text) {
            return $Text.Trim() -replace '(\r\n){2,}', "`n"
        }

        $tagsRex = ([regex]'(?m)^[\s]{0,15}Tags:(.*)$')
        $authorRex = ([regex]'(?m)^[\s]{0,15}Author:(.*)$')
        $minverRex = ([regex]'(?m)^[\s]{0,15}MinimumVersion:(.*)$')
        $maxverRex = ([regex]'(?m)^[\s]{0,15}MaximumVersion:(.*)$')
        $availability = 'Windows, Linux, macOS'

        function Get-DbaDocsMD($doc_to_render) {

            $rtn = New-Object -TypeName "System.Collections.ArrayList"
            $null = $rtn.Add("# $($doc_to_render.CommandName)" )
            if ($doc_to_render.Author -or $doc_to_render.Availability) {
                $null = $rtn.Add('|  |  |')
                $null = $rtn.Add('| - | - |')
                if ($doc_to_render.Author) {
                    $null = $rtn.Add('|  **Author**  | ' + $doc_to_render.Author.replace('|', ',') + ' |')
                }
                if ($doc_to_render.Availability) {
                    $null = $rtn.Add('| **Availability** | ' + $doc_to_render.Availability + ' |')
                }
                $null = $rtn.Add('')
            }
            $null = $rtn.Add("`n" + '&nbsp;' + "`n")
            if ($doc_to_render.Alias) {
                $null = $rtn.Add('')
                $null = $rtn.Add('*Aliases : ' + $doc_to_render.Alias + '*')
                $null = $rtn.Add('')
            }
            $null = $rtn.Add('## Synopsis')
            $null = $rtn.Add($doc_to_render.Synopsis)
            $null = $rtn.Add('')
            $null = $rtn.Add('## Description')
            $null = $rtn.Add($doc_to_render.Description)
            $null = $rtn.Add('')
            if ($doc_to_render.Syntax) {
                $null = $rtn.Add('## Syntax')
                $null = $rtn.Add('```')
                $splitted_paramsets = @()
                foreach ($val in ($doc_to_render.Syntax -split $doc_to_render.CommandName)) {
                    if ($val) {
                        $splitted_paramsets += $doc_to_render.CommandName + $val
                    }
                }
                foreach ($syntax in $splitted_paramsets) {
                    $x = 0
                    foreach ($val in ($syntax.Replace("`r", '').Replace("`n", '') -split ' \[')) {
                        if ($x -eq 0) {
                            $null = $rtn.Add($val)
                        } else {
                            $null = $rtn.Add('    [' + $val.replace("`n", '').replace("`n", ''))
                        }
                        $x += 1
                    }
                    $null = $rtn.Add('')
                }

                $null = $rtn.Add('```')
                $null = $rtn.Add("`n" + '&nbsp;' + "`n")
            }
            $null = $rtn.Add('')
            $null = $rtn.Add('## Examples')
            $null = $rtn.Add("`n" + '&nbsp;' + "`n")
            $examples = $doc_to_render.Examples.Replace("`r`n", "`n") -replace '(\r\n){2,8}', '\n'
            $examples = $examples.replace("`r", '').split("`n")
            $inside = 0
            foreach ($row in $examples) {
                if ($row -like '*----') {
                    $null = $rtn.Add("");
                    $null = $rtn.Add('#####' + ($row -replace '-{4,}([^-]*)-{4,}', '$1').replace('EXAMPLE', 'Example: '))
                } elseif (($row -like 'PS C:\>*') -or ($row -like '>>*')) {
                    if ($inside -eq 0) { $null = $rtn.Add('```') }
                    $null = $rtn.Add(($row.Trim() -replace 'PS C:\\>\s*', "PS C:\> "))
                    $inside = 1
                } elseif ($row.Trim() -eq '' -or $row.Trim() -eq 'Description') {

                } else {
                    if ($inside -eq 1) {
                        $inside = 0
                        $null = $rtn.Add('```')
                    }
                    $null = $rtn.Add("$row<br>")
                }
            }
            if ($inside -eq 1) {
                $inside = 0
                $null = $rtn.Add('```')
            }
            if ($doc_to_render.Params) {
                $dotitle = 0
                $filteredparams = @()
                foreach ($p in $doc_to_render.Params) {
                    if ($p[3] -eq $true) {
                        $filteredparams += , $p
                    }
                }
                $dotitle = 0
                foreach ($el in $filteredparams) {
                    if ($dotitle -eq 0) {
                        $dotitle = 1
                        $null = $rtn.Add('### Required Parameters')
                    }
                    $null = $rtn.Add('##### -' + $el[0])
                    $null = $rtn.Add($el[1] + '<br>')
                    $null = $rtn.Add('')
                    $null = $rtn.Add('|  |  |')
                    $null = $rtn.Add('| - | - |')
                    $null = $rtn.Add('| Alias | ' + $el[2] + ' |')
                    $null = $rtn.Add('| Required | ' + $el[3] + ' |')
                    $null = $rtn.Add('| Pipeline | ' + $el[4] + ' |')
                    $null = $rtn.Add('| Default Value | ' + $el[5] + ' |')
                    if ($el[6]) {
                        $null = $rtn.Add('| Accepted Values | ' + $el[6] + ' |')
                    }
                    $null = $rtn.Add('')
                }
                $dotitle = 0
                $filteredparams = @()
                foreach ($p in $doc_to_render.Params) {
                    if ($p[3] -eq $false) {
                        $filteredparams += , $p
                    }
                }
                foreach ($el in $filteredparams) {
                    if ($dotitle -eq 0) {
                        $dotitle = 1
                        $null = $rtn.Add('### Optional Parameters')
                    }

                    $null = $rtn.Add('##### -' + $el[0])
                    $null = $rtn.Add($el[1] + '<br>')
                    $null = $rtn.Add('')
                    $null = $rtn.Add('|  |  |')
                    $null = $rtn.Add('| - | - |')
                    $null = $rtn.Add('| Alias | ' + $el[2] + ' |')
                    $null = $rtn.Add('| Required | ' + $el[3] + ' |')
                    $null = $rtn.Add('| Pipeline | ' + $el[4] + ' |')
                    $null = $rtn.Add('| Default Value | ' + $el[5] + ' |')
                    if ($el[6]) {
                        $null = $rtn.Add('| Accepted Values | ' + $el[6] + ' |')
                    }
                    $null = $rtn.Add('')
                }
            }
            $null = $rtn.Add('')
            $null = $rtn.Add("`n" + '&nbsp;' + "`n")
            $null = $rtn.Add('Want to see the source code for this command? Check out [' + $doc_to_render.CommandName + '](https://github.com/dataplat/dbatools/blob/master/functions/' + $doc_to_render.CommandName + '.ps1) on GitHub.')
            $null = $rtn.Add("<br>")
            $null = $rtn.Add('Want to see the Bill Of Health for this command? Check out [' + $doc_to_render.CommandName + '](https://dataplat.github.io/boh#' + $doc_to_render.CommandName + ').')
            $null = $rtn.Add('')

            return $rtn
        }


    }
    process {

        if ($Name -in $script:noncoresmo -or $Name -in $script:windowsonly) {
            $availability = 'Windows only'
        }
        try {
            $thishelp = Get-Help $Name -Full
        } catch {
            Stop-Function -Message "Issue getting help for $Name" -Target $Name -ErrorRecord $_ -Continue
        }

        $thebase = @{ }
        $thebase.CommandName = $Name
        $thebase.Name = $thishelp.Name

        $thebase.Availability = $availability

        $alias = Get-Alias -Definition $Name -ErrorAction SilentlyContinue
        $thebase.Alias = $alias.Name -Join ','

        ## fetch the description
        $thebase.Description = $thishelp.Description.Text

        ## fetch examples
        $thebase.Examples = Get-DbaTrimmedString -Text ($thishelp.Examples | Out-String -Width 200)

        ## fetch help link
        $thebase.Links = ($thishelp.relatedLinks).NavigationLink.Uri

        ## fetch the synopsis
        $thebase.Synopsis = $thishelp.Synopsis

        ## fetch the syntax
        $thebase.Syntax = Get-DbaTrimmedString -Text ($thishelp.Syntax | Out-String -Width 600)

        ## store notes
        $as = $thishelp.AlertSet | Out-String -Width 600

        ## fetch the tags
        $tags = $tagsrex.Match($as).Groups[1].Value
        if ($tags) {
            $thebase.Tags = $tags.Split(',').Trim()
        }
        ## fetch the author
        $author = $authorRex.Match($as).Groups[1].Value
        if ($author) {
            $thebase.Author = $author.Trim()
        }

        ## fetch MinimumVersion
        $MinimumVersion = $minverRex.Match($as).Groups[1].Value
        if ($MinimumVersion) {
            $thebase.MinimumVersion = $MinimumVersion.Trim()
        }

        ## fetch MaximumVersion
        $MaximumVersion = $maxverRex.Match($as).Groups[1].Value
        if ($MaximumVersion) {
            $thebase.MaximumVersion = $MaximumVersion.Trim()
        }

        ## fetch Parameters
        $parameters = $thishelp.parameters.parameter
        $command = Get-Command $Name
        $params = @()
        foreach ($p in $parameters) {
            $paramAlias = $command.parameters[$p.Name].Aliases
            $validValues = $command.parameters[$p.Name].Attributes.ValidValues -Join ','
            $paramDescr = Get-DbaTrimmedString -Text ($p.Description | Out-String -Width 200)
            $params += , @($p.Name, $paramDescr, ($paramAlias -Join ','), ($p.Required -eq $true), $p.PipelineInput, $p.DefaultValue, $validValues)
        }

        $thebase.Params = $params

        if ($OutputAs -eq "PSObject") {
            [pscustomobject]$thebase
        } elseif ($OutputAs -eq "MDString") {
            Get-DbaDocsMD -doc_to_render $thebase
        }

    }
    end {

    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDbfSEyF1wGLzTW
# vNOc5LbWTfEM/zE9X+gYUVbHM8XNZaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAec3vS0+FcoRSruvg1f0a9DYvr/SWlogAc
# vkc+fzGmhDANBgkqhkiG9w0BAQEFAASCAQB7svYzVaVC5EXJbXOER5keQeYydeso
# us63Li/XBqCi5tfD7WcEvc6C4aJHCJqhltV61k7kgsLr69tXmpc9hF/7r6Cw6UOp
# B9UDUQ6Fut1LUuM6XguGMbXc/xyzdNP5ieyjAUsZDbVIaJI7Ovs8obUnEtjNzpxh
# TSToucWxh5CaG7rLIJRmSKyG+wnt1lDgdDewQqm0dQJM4b8lFevSoH5cFe2HbtEK
# vzoSYwbVIawm+aNf1vuc8jkCdvQKDLXbw0cz4TVfrxGZmG9cfXq2vBTW0skq2Aeo
# /tdI4Vl98uN5RR5U9lyPMIGjo7ptAw3kYJ5rOZ85wGaf3YTyzg5G9O/FoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQzN1owLwYJKoZIhvcNAQkEMSIEIA86Z9GR
# mQd1KaK5ay2wlnMX4RGAVFhGKIUV7XEO4gObMA0GCSqGSIb3DQEBAQUABIICAKYp
# EjdOlPDamsvghpLoS3V1Hb64pocgQPAZXmC/qVb9aEWHCiLorCZsk+zVZ0rfb9Hk
# VeGdcW1gqz819K+FqFPmdJjlUYEg00bq+0I38Y98Mc5BK5TbHUzaLDIOal3vqI2z
# 0BzWQ5ZJparNK/CSTKnkvUBnu3mEl27q8HSn88NkCdozOjKvOOZ6xkeKEsfM2b+Q
# quG/LyJ1nDQhx1JvEgMVs0wJXxwx7oQbLDcvjaB3NWNGLbLHehi0ZVnBR7//Ne5k
# tO+ipl+hy2M5JJjmxeY3IDCt6m8Y/KH7skIDztw3oc6cF7nDzqbgnkWMFRwN5UK0
# 4rq5jDcAVtBXKAr5ChEpmsdldYg9n8b/YoFWXKvZBFOip3bfhpY66zp5FypTJeqz
# qkm9IhVvwmvDRgOPICBGquLea7eG/jcbts4yA4oF9PnS6uAqnYcDAFcswupB6NF2
# 6ApkWpvmmHa4aADkjZjASzQp/a8elBaroH2R7P+rf+0mXZhxNwHTH2LbSRwdmtfq
# udVMqprogRjyLo7QhDCR5CpTA1en0i1HtXgQAj4yltGAqBVFwkRQWrqKgWs8oR7J
# e4TmZU9KNceQJbyR6s+3uuBEWlhpJ9vItUiLb3Iy6fBh2DZszropxMeGkGDwxvRP
# e5JyS03WazfLWZEp8QJfToQEgsW3qLsD4Oo/ytRI
# SIG # End signature block
