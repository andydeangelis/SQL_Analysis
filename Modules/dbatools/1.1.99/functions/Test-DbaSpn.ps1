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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUDyvY/MMEl4eq+xUJ9r0REWqC
# r3+gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFFcGS8QcgEtI31V/1EVIyaQF2fvzMA0G
# CSqGSIb3DQEBAQUABIIBAK0GKrsGgcXS8RnlayLKATW64VQ2w4KXwDL493oloZkP
# 4wYI+ital+L1WuavSsPDym4Ur8dV4Eh2SHDp00FWi1uznAVP0a/WhdzcHckbCbHg
# WdNf7ERw1LHl42OPNubMLpARtd/zjEQA2yq8Pm5Hcm8UReBDyaFrNJxP+bfS+zLg
# icgryeGGdF70aLm54poE9gBECDbYi6Fyb2WwzoSMkR2PpyxfHFywVOnClGaW9Zoq
# J1Gzy5CHCBgY6OxcM1S+fhfJ1PVtXpwqJP+hfwOmn/EOIg0C6lstCS24NpURoJa7
# w5Uu6PatYluEPcSsldPRuoak8v3KYuAwWxUKyM2APYahggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDMxWjAvBgkqhkiG9w0BCQQxIgQgdgtv59bJV7kUnx5fzXZY
# BcQru1rlyYoyoUMBsMKYRIAwDQYJKoZIhvcNAQEBBQAEggIAQvE+J+fJ2WsWJEXz
# otK077zmNaUYT0HFknjWYpHBAagbspNge6ftiHbtIJBy1NGMHosAxl7IzBLSfhyi
# HAgLzNvTDOxEGGzhUectEtP04LFbZhRpBjmxuiyljCxbJsPzJXFiYK2Pe/mvBVhC
# LgQCEGVkj3F/fEJAuqUYPIpUayiujDnKchsDrA7j2qQKu0xFzeJBTHhRLQ+UI4lO
# TzklhSPlZw+5owv95SfmoczcIaPvxAJo4CElX+RI3Ny/+6GUoWeAFJ45/Ii0tSa/
# xv9a9TfS0GVlq5dbfhm1i0mKQShW6V9QGlb/m9A0Ix8us53qSeho597uZG1tDu0y
# jlwIOm3zpW/tTuRIQR+Ojg//Ysbn/lL8Y4G9vdE3EHC70IsJFTSboOWAE68faV9O
# 4mXAO7YuQWXcwcpWbTExi1BAZsRT6GBLd/zktxe86wxeGpjrYKMhTrPch6xIhVV5
# SybFaGdKSJLxNKmVwzU507Vtwlb4qVw5pUN+tpiNgANxix14iRAQYtkr4Tc+J/lo
# FWssRjXheyvu+AEGBOLnWsAkGy7qe93/DIKGnTqmQZk0PpJysW+5RsHFLOu7BXa3
# 6b5DYpRjQUpJJGxG+R6vH7imx3N8H1VUzoGz3qNkHgohDIoEeZy87mr8zMr1A/Ac
# JeSl7om9z1wMvrd2zslXpl45KEw=
# SIG # End signature block
