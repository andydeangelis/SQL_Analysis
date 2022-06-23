function Test-DbaSpn {
    <#
    .SYNOPSIS
        Test-DbaSpn will determine what SPNs *should* be set for a given server (and any instances of SQL running on it) and return
        whether the SPNs are set or not.

    .DESCRIPTION
        This function is designed to take in a server name(s) and attempt to determine required SPNs. It was initially written to mimic the (previously) broken functionality of the Microsoft Kerberos Configuration manager and SQL Server 2016.

        - For any instances with TCP/IP enabled, the script will determine which port(s) the instances are listening on and generate the required SPNs.
        - For named instances NOT using dynamic ports, the script will generate a port-based SPN for those instances as well.
        - At a minimum, the script will test a base, port-less SPN for each instance discovered.

        Once the required SPNs are generated, the script will connect to Active Directory and search for any of the SPNs (if any) that are already set. The function will return a custom object(s) that contains the server name checked, the instance name discovered, the account the service is running under, and what the "required" SPN should be. It will also return a boolean property indicating if the SPN is set in Active Directory or not.

    .PARAMETER ComputerName
        The computer you want to discover any SQL Server instances on. This parameter is required.

    .PARAMETER Credential
        The credential you want to use to connect to the remote server and active directory.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SPN
        Author: Drew Furgiuele (@pittfurg), http://www.port1433.com | niphlod

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaSpn

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERA -Credential ad\sqldba

        Connects to a computer (SQLSERVERA) and queries WMI for all SQL instances and return "required" SPNs. It will then take each SPN it generates
        and query Active Directory to make sure the SPNs are set.

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERA,SQLSERVERB -Credential ad\sqldba

        Connects to multiple computers (SQLSERVERA, SQLSERVERB) and queries WMI for all SQL instances and return "required" SPNs.
        It will then take each SPN it generates and query Active Directory to make sure the SPNs are set.

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERC -Credential ad\sqldba

        Connects to a computer (SQLSERVERC) on a specified and queries WMI for all SQL instances and return "required" SPNs.
        It will then take each SPN it generates and query Active Directory to make sure the SPNs are set. Note that the credential you pass must have be a valid login with appropriate rights on the domain

    #>
    [cmdletbinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    begin {
        # spare the cmdlet to search for the same account over and over
        $resultCache = @{ }
    }
    process {
        foreach ($computer in $ComputerName) {
            try {
                $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential -ErrorAction Stop
            } catch {
                $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Turbo
            }

            if ($null -eq $resolved.IPAddress) {
                Write-Message -Level Warning -Message "Cannot resolve IP address, moving on."
                continue
            }

            $hostEntry = $resolved.FullComputerName

            Write-Message -Message "Resolved ComputerName to FQDN: $hostEntry" -Level Verbose

            $Scriptblock = {

                function Convert-SqlVersion {
                    [cmdletbinding()]
                    param (
                        [version]$version
                    )

                    switch ($version.Major) {
                        9 { "SQL Server 2005" }
                        10 {
                            if ($version.Minor -eq 0) {
                                "SQL Server 2008"
                            } else {
                                "SQL Server 2008 R2"
                            }
                        }
                        11 { "SQL Server 2012" }
                        12 { "SQL Server 2014" }
                        13 { "SQL Server 2016" }
                        14 { "SQL Server 2017" }
                        15 { "SQL Server 2019" }
                        default { $version }
                    }
                }

                $spns = @()
                $servereName = $args[0]
                $hostEntry = $args[1]
                $instanceName = $args[2]
                $instanceCount = $wmi.ServerInstances.Count

                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose "Found $instanceCount instances"

                foreach ($instance in $wmi.ServerInstances) {
                    $spn = [pscustomobject] @{
                        ComputerName           = $servereName
                        InstanceName           = $instanceName
                        #SKUNAME
                        SqlProduct             = $null
                        InstanceServiceAccount = $null
                        RequiredSPN            = $null
                        IsSet                  = $false
                        Cluster                = $false
                        TcpEnabled             = $false
                        Port                   = $null
                        DynamicPort            = $false
                        Warning                = "None"
                        Error                  = "None"
                        # for piping
                        Credential             = $Credential
                    }

                    $spn.InstanceName = $instance.Name
                    $instanceName = $spn.InstanceName

                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Parsing $instanceName"

                    $services = $wmi.Services | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                    $spn.InstanceServiceAccount = $services.ServiceAccount
                    $spn.Cluster = ($services.advancedproperties | Where-Object Name -EQ 'Clustered').Value

                    if ($spn.Cluster) {
                        $hostEntry = ($services.advancedproperties | Where-Object Name -EQ 'VSNAME').Value.ToLowerInvariant()
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose "Found cluster $hostEntry"
                        $hostEntry = ([System.Net.Dns]::GetHostEntry($hostEntry)).HostName
                        $spn.ComputerName = $hostEntry
                    }

                    $rawVersion = [version]($services.AdvancedProperties | Where-Object Name -EQ 'VERSION').Value

                    $version = Convert-SqlVersion $rawVersion
                    $skuName = ($services.AdvancedProperties | Where-Object Name -EQ 'SKUNAME').Value

                    $spn.SqlProduct = "$version $skuName"

                    #is tcp enabled on this instance? If not, we don't need an spn, son
                    if ((($instance.ServerProtocols | Where-Object { $_.Displayname -eq "TCP/IP" }).ProtocolProperties | Where-Object { $_.Name -eq "Enabled" }).Value -eq $true) {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose "TCP is enabled, gathering SPN requirements"
                        $spn.TcpEnabled = $true
                        #Each instance has a default SPN of MSSQLSvc\<fqdn> or MSSSQLSvc\<fqdn>:Instance
                        if ($instance.Name -eq "MSSQLSERVER") {
                            $spn.RequiredSPN = "MSSQLSvc/$hostEntry"
                        } else {
                            $spn.RequiredSPN = "MSSQLSvc/" + $hostEntry + ":" + $instance.Name
                        }
                    }

                    $spns += $spn
                }
                # Now, for each spn, do we need a port set? Only if TCP is enabled and NOT DYNAMIC!
                foreach ($spn in $spns) {
                    $ports = @()

                    $ips = (($wmi.ServerInstances | Where-Object { $_.Name -eq $spn.InstanceName }).ServerProtocols | Where-Object { $_.DisplayName -eq "TCP/IP" -and $_.IsEnabled -eq "True" }).IpAddresses
                    $ipAllPort = $null
                    foreach ($ip in $ips) {
                        if ($ip.Name -eq "IPAll") {
                            $ipAllPort = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TCPPort" }).Value
                            if (($ip.IpAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value -ne "") {
                                $ipAllPort = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value + "d"
                            }
                        } else {
                            $enabled = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "Enabled" }).Value
                            $active = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "Active" }).Value
                            $tcpDynamicPorts = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value
                            if ($enabled -and $active -and $tcpDynamicPorts -eq "") {
                                $ports += ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TCPPort" }).Value
                            } elseif ($enabled -and $active -and $tcpDynamicPorts -ne "") {
                                $ports += $ipAllPort + "d"
                            }
                        }
                    }
                    if ($ipAllPort -ne "") {
                        #IPAll overrides any set ports. Not sure why that's the way it is?
                        $ports = $ipAllPort
                    }

                    $ports = $ports | Select-Object -Unique
                    foreach ($port in $ports) {
                        $newspn = $spn.PSObject.Copy()
                        if ($port -like "*d") {
                            $newspn.Port = ($port.replace("d", ""))
                            $newspn.RequiredSPN = $newspn.RequiredSPN.Replace(":" + $newSPN.InstanceName, ":" + $newspn.Port)
                            $newspn.DynamicPort = $true
                            $newspn.Warning = "Dynamic port is enabled"
                        } else {
                            #If this is a named instance, replace the instance name with a port number (for non-dynamic ported named instances)
                            $newspn.Port = $port
                            $newspn.DynamicPort = $false

                            if ($newspn.InstanceName -eq "MSSQLSERVER") {
                                $newspn.RequiredSPN = $newspn.RequiredSPN + ":" + $port
                            } else {
                                $newspn.RequiredSPN = $newspn.RequiredSPN.Replace(":" + $newSPN.InstanceName, ":" + $newspn.Port)
                            }
                        }
                        $spns += $newspn
                    }
                }
                $spns
            }


            try {
                $spns = Invoke-ManagedComputerCommand -ComputerName $hostEntry -ScriptBlock $Scriptblock -ArgumentList $resolved.FullComputerName, $hostEntry, $computer.InstanceName -Credential $Credential -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't connect to $computer" -ErrorRecord $_ -Continue
            }

            #Now query AD for each required SPN
            foreach ($spn in $spns) {
                $searchfor = 'User'
                if ($spn.InstanceServiceAccount -eq 'LocalSystem' -or $spn.InstanceServiceAccount -like 'NT SERVICE\*') {
                    Write-Message -Level Verbose -Message "Virtual account detected, changing target registration to computername"
                    $spn.InstanceServiceAccount = "$($resolved.Domain)\$($resolved.ComputerName)$"
                    $searchfor = 'Computer'
                } elseif ($spn.InstanceServiceAccount -like '*\*$') {
                    Write-Message -Level Verbose -Message "Managed Service Account detected"
                    $searchfor = 'Computer'
                }

                $serviceAccount = $spn.InstanceServiceAccount
                # spare the cmdlet to search for the same account over and over
                if ($spn.InstanceServiceAccount -notin $resultCache.Keys) {
                    Write-Message -Message "Searching for $serviceAccount" -Level Verbose
                    try {
                        $result = Get-DbaADObject -ADObject $serviceAccount -Type $searchfor -Credential $Credential -EnableException
                        $resultCache[$spn.InstanceServiceAccount] = $result
                    } catch {
                        if (![System.String]::IsNullOrEmpty($spn.InstanceServiceAccount)) {
                            Write-Message -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($serviceAccount)." -Level Warning
                        }
                    }
                } else {
                    $result = $resultCache[$spn.InstanceServiceAccount]
                }
                if ($result.Count -gt 0) {
                    try {
                        $results = $result.GetUnderlyingObject()
                        if ($results.Properties.servicePrincipalName -contains $spn.RequiredSPN) {
                            $spn.IsSet = $true
                        }
                    } catch {
                        Write-Message -Message "The SQL Service account ($serviceAccount) has been found, but you don't have enough permission to inspect its SPNs" -Level Warning
                        continue
                    }
                } else {
                    Write-Message -Level Warning -Message "SQL Service account not found. Results may not be accurate."
                    $spn
                    continue
                }
                if (!$spn.IsSet -and $spn.TcpEnabled) {
                    $spn.Error = "SPN missing"
                }

                $spn | Select-DefaultView -ExcludeProperty Credential, DomainName
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCZzyLspgdKGlP+
# dkjBpK/oLWwCgtbyv20jBnTbdQROuKCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCab3K5cahj3l8e5g1r0wgdU0dYXfgHqcFu
# HsfiyOmekzANBgkqhkiG9w0BAQEFAASCAQB1wmFvxVCvWFeoR8vI2kA4evERyrD7
# NZpY+/TKazyfIqwCQmnO4ESDmqJIkcYqWfte8sZ/9N+aTZaBg9DF0l/cuulqv1mQ
# D+92p7gKzHqbUmgClbYLTO9NjclE1x3rVlUjX7nw0UmelXoNnLWB7koI/CkddshU
# 40bXFNw2PIVCkXMNvZgZlVegFCFacrxQmh6huL2JMCINetCbe3XTzKS9oGvwLVlW
# QZe63FoeSsASuaY0qQ4bh0T4TGV6ILjzHA3pr+S+yLef3fIDLGynTj5Ysz+ZMhHg
# gbjmi7Dt5jEY3HNJWDqUg3GAvphmfyeTbb+RB1NHMhOuWiZn2CX0CKbDoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQxMFowLwYJKoZIhvcNAQkEMSIEIEvgzb0Z
# jAw8Z5vvDNYU7FXQByaUceFFa/D4nla3MUwYMA0GCSqGSIb3DQEBAQUABIICAHZA
# psL+GfhgmnUrrNTrq97kDh1W3YOanOJBmGb8P1wweGc26yjjRfUOV0P2130Je5CB
# f+v+Jk9hMg6oNdYPBYYogTtPHWKUzZqtOwwu+pUS7uifkmSK0WM7vTXNTwa1Mr21
# zFLYvW3XgKlGWv0xuFXd94xelXtVlvQs/dJkapbxLWXtdvX4t9hmrMZaddO3Myd0
# tjTMLMBSgxWyALeHC0zRxHqCEf6+ZKt6ugNiyOkxEFQ4M78J+GU8rEebsFIx/gp5
# LvPEtSeQ9/9UV9kgskt3TjRAYc4gI0xzC24ZINeh9FHJiwdO5slwJuRjtx++3v05
# ZKv85HIQeh40wlRIwzN8zrnitivSaqBDEinoZT3QBQcCNphNWMd8SrKq3YDhNPiN
# pZW1wqKZ08lZuHUoTGphV9ftRkl399GeWvtGFlh2QRPyISSFU2ilNRRAmPizEbAA
# efRM26VIZ34KCtXl5mo02Fw9t4KBSTd0tLc8B7jUnIZj5RacqRKKLX1X3yiagXuR
# nnI5ldUxfxdSe6SrdFWQkZWZkfXWBEggkfpZl0irkH4pcnLnIN2F6t4zmFQ5rxLF
# FMnO7/9hIwErTf3W5E1xIJZH1spV56ED2qNr8RWcK1DePOADdZeBJtCyr61RpNby
# JgWNebJcE2hFK5m4/j6rmatBY8ONPpcvHUotdQg7
# SIG # End signature block
