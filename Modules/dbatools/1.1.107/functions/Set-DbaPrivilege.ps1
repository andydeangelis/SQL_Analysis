function Set-DbaPrivilege {
    <#
    .SYNOPSIS
        Adds the SQL Service account to local privileges on one or more computers.

    .DESCRIPTION
        Adds the SQL Service account to local privileges 'Lock Pages in Memory', 'Instant File Initialization', 'Logon as Batch', 'Logon as a service' on one or more computers.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Use this to choose the privilege(s) to which you want to add the SQL Service account.
        Accepts 'IFI', 'LPIM', 'BatchLogon','SecAudit' and/or 'ServiceLogon' for local privileges 'Instant File Initialization', 'Lock Pages in Memory', 'Logon as Batch','Generate Security Audits' and 'Logon as a service'.

    .PARAMETER User
        If provided, will add requested permissions to this account instead of the the account under which the SQL service is running.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Privilege, Security
        Author: Klaas Vandenberghe ( @PowerDBAKlaas )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaPrivilege

    .EXAMPLE
        PS C:\> Set-DbaPrivilege -ComputerName sqlserver2014a -Type LPIM,IFI

        Adds the SQL Service account(s) on computer sqlserver2014a to the local privileges 'SeManageVolumePrivilege' and 'SeLockMemoryPrivilege'.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Set-DbaPrivilege -Type IFI

        Adds the SQL Service account(s) on computers sql1, sql2 and sql3 to the local privilege 'SeManageVolumePrivilege'.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [dbainstanceparameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [ValidateSet('IFI', 'LPIM', 'BatchLogon', 'SecAudit', 'ServiceLogon')]
        [string[]]$Type,
        [switch]$EnableException,
        [string]$User
    )

    begin {
        $ResolveAccountToSID = @"
function Convert-UserNameToSID ([string] `$Acc ) {
`$objUser = New-Object System.Security.Principal.NTAccount(`"`$Acc`")
`$strSID = `$objUser.Translate([System.Security.Principal.SecurityIdentifier])
`$strSID.Value
}
"@
        $ComputerName = $ComputerName.ComputerName | Select-Object -Unique
    }
    process {
        foreach ($computer in $ComputerName) {
            if ($Pscmdlet.ShouldProcess($computer, "Setting Privilege for SQL Service Account")) {
                try {
                    $null = Test-ElevationRequirement -ComputerName $Computer -Continue
                    if (Test-PSRemoting -ComputerName $Computer) {
                        Write-Message -Level Verbose -Message "Exporting Privileges on $Computer"
                        Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock {
                            $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); secedit /export /cfg $temp\secpolByDbatools.cfg > $NULL;
                        }

                        $SQLServiceAccounts = @();
                        if (Test-Bound 'User') {
                            $SQLServiceAccounts += $User;
                        } else {
                            Write-Message -Level Verbose -Message "Getting SQL Service Accounts on $computer"
                            $SQLServiceAccounts += (Get-DbaService -ComputerName $computer -Type Engine).StartName
                        }
                        if ($SQLServiceAccounts.count -ge 1) {
                            Write-Message -Level Verbose -Message "Setting Privileges on $Computer"
                            Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -Verbose -ArgumentList $ResolveAccountToSID, $SQLServiceAccounts, $Type -ScriptBlock {
                                [CmdletBinding()]
                                param ($ResolveAccountToSID,
                                    $SQLServiceAccounts,
                                    $Type
                                )
                                . ([ScriptBlock]::Create($ResolveAccountToSID))
                                $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                                $tempfile = "$temp\secpolByDbatools.cfg"
                                if ('BatchLogon' -in $Type) {
                                    $BLline = Get-Content $tempfile | Where-Object { $_ -match "SeBatchLogonRight" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $BLline) {
                                            $BLline = "SeBatchLogonRight = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$BLline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Batch Logon Privileges on $env:ComputerName"
                                        } elseif ($BLline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeBatchLogonRight = ", "SeBatchLogonRight = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Batch Logon Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Batch Logon Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('IFI' -in $Type) {
                                    $IFIline = Get-Content $tempfile | Where-Object { $_ -match "SeManageVolumePrivilege" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $IFIline) {
                                            $IFIline = "SeManageVolumePrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$IFIline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Instant File Initialization Privileges on $env:ComputerName"
                                        } elseif ($IFIline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeManageVolumePrivilege = ", "SeManageVolumePrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Instant File Initialization Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Instant File Initialization Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('LPIM' -in $Type) {
                                    $LPIMline = Get-Content $tempfile | Where-Object { $_ -match "SeLockMemoryPrivilege" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $LPIMline) {
                                            $LPIMline = "SeLockMemoryPrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$LPIMline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Lock Pages in Memory Privileges on $env:ComputerName"
                                        } elseif ($LPIMline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeLockMemoryPrivilege = ", "SeLockMemoryPrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Lock Pages in Memory Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Lock Pages in Memory Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('SecAudit' -in $Type) {
                                    $Line = Get-Content $tempfile | Where-Object { $_ -match "SeAuditPrivilege" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $Line) {
                                            $Line = "SeAuditPrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$Line" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Security Log Privileges on $env:ComputerName"
                                        } elseif ($Line -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeAuditPrivilege = ", "SeAuditPrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Write to Security Log Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Write To Security Audit Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('ServiceLogon' -in $Type) {
                                    $SLline = Get-Content $tempfile | Where-Object { $_ -match "SeServiceLogonRight" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SLline) {
                                            $SLline = "SeServiceLogonRight = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$SLline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Service Logon Privileges on $env:ComputerName"
                                        } elseif ($SLline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeServiceLogonRight = ", "SeServiceLogonRight = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Service Logon Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Service Logon Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                $null = secedit /configure /cfg $tempfile /db secedit.sdb /areas USER_RIGHTS /overwrite /quiet
                            } -ErrorAction SilentlyContinue
                            Write-Message -Level Verbose -Message "Removing secpol file on $computer"
                            Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock { $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); Remove-Item $temp\secpolByDbatools.cfg -Force > $NULL }
                        } else {
                            Write-Message -Level Warning -Message "No SQL Service Accounts found on $Computer"
                        }
                    } else {
                        Write-Message -Level Warning -Message "Failed to connect to $Computer"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB3GZkIRexUFvRE
# TNNVFHcbFX3w0a28dgoP/GU/yFiUCqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAztewn/R9KZXnuS8skSDwu49y4i/OPxZUi
# +xGxB6XRJjANBgkqhkiG9w0BAQEFAASCAQBQUXnju+QnnFuAvbvJMM0UvGIHyCFP
# i/ggdDiT1gN/NQPOpIOBRFxGZ6EIwJ3RpmAy0th9jp3HjaO+GZxCqnO0BmltS4/J
# nfzj9hDvCUEqW9vAsTWLW+1mgHGINO4Owe2NunCRMQCaTrLWX0pQjq4D7V7EaDYy
# 3IoDRzewjPlqXW0/ypYTcmmWJg4jFlABpcOmGWGNci/sRlDHAoQGEcrtRTuvI3Ka
# j4DwKLy9h/KBg+GkP2dR15KYkylhSDGVL0DCCZDj7DMQRc3sokODxlgj0nVJDibL
# nv7il2RRaU82wmqOQ1rohLh/YWoVdpKBCTl42UQBIUIsiKaIo2eUlfFmoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDM1OVowLwYJKoZIhvcNAQkEMSIEIOKp2Sak
# PLKrbeutHvzJX3KLhmREZ79nygVKla73rjaWMA0GCSqGSIb3DQEBAQUABIICAFeL
# Q+4xUm6bvYd4Uy1RwrRBE+xaHoWUxfsrsNslyDYzZpMs1I/5cACdNJBSTcImbxC5
# UxP2kdBhXOKDbkPOE/ZcR4c+YKDN9aCUFniFSxDAwmOtO9XrQmM1f3+SNhlw8m7v
# 3qAMejVYfCO6QiwsttwDhZdP4LGE895uDzCfTWyWo/6bwdIHzcljLX4q/ReYi1Yk
# f6NMH0lLpo0mjLs52cyKIlZpzOYfr3JXQwia27nJ5zRLOnyB6efA5jdprciy9rcn
# jqIXJALyG0RMvRIbTCvn9OFZu1LdluakcF4ESae7eEUFT/QYF/TG43KjzP42qv5q
# DYicsVAO1wi5+mRrO5l6wTFdbItSQl2A0Dz+5CAJ6QIUFvbySx+Kug9ZLdw7015+
# FgJaKE/QWdsNL5yyxtSNZGaH9Ib89ghgR8Ev6pr0NiwCo7/UxHszu4XAPe0wUL4i
# EHHTaO8X4zgtuxN6qer9oqFZLzm71bcPxr4aTZ7wzj8TWXnlxPplXQRVMHDT+olQ
# KscXuve5mlHSKxM3IJNojPPuQZql10c+TFaomhlb/yi6F9XYyp8Oh+zMDYf5q/BQ
# bJpqNQidpCLMdsyGSR4TdX8pr7tXE7TDXztQ/Tk6kTjAHK16/FxD6UqUI2HSsipi
# pl9uiAJNYSw+4aBOqOcGiB7QxZRdr7QWknmNQf1Q
# SIG # End signature block
