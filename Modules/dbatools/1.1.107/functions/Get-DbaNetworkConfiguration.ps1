function Get-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Returns the network configuration of a SQL Server instance as shown in SQL Server Configuration Manager.

    .DESCRIPTION
        Returns a PowerShell object with the network configuration of a SQL Server instance as shown in SQL Server Configuration Manager.

        As we get information from SQL WMI and also from the registry, we use PS Remoting to run the core code on the target machine.

        For a detailed explanation of the different properties see the documentation at:
        https://docs.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-network-configuration

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER OutputType
        Defines what information is returned from the command.
        Options include: Full, ServerProtocols, TcpIpProperties, TcpIpAddresses or Certificate. Full by default.

        Full returns one object per SqlInstance with information about the server protocols
        and nested objects with information about TCP/IP properties and TCP/IP addresses.
        It also outputs advanced properties including information about the used certificate.

        ServerProtocols returns one object per SqlInstance with information about the server protocols only.

        TcpIpProperties returns one object per SqlInstance with information about the TCP/IP protocol properties only.

        TcpIpAddresses returns one object per SqlInstance and IP address.
        If the instance listens on all IP addresses (TcpIpProperties.ListenAll), only the information about the IPAll address is returned.
        Otherwise only information about the individual IP addresses is returned.
        For more details see: https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/configure-a-server-to-listen-on-a-specific-tcp-port

        Certificate returns one object per SqlInstance with information about the configured network certificate and whether encryption is enforced.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Connection, SQLWMI
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaNetworkConfiguration

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a

        Returns the network configuration for the default instance on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance winserver\sqlexpress, sql2016 -OutputType ServerProtocols

        Returns information about the server protocols for the sqlexpress on winserver and the default instance on sql2016.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [ValidateSet('Full', 'ServerProtocols', 'TcpIpProperties', 'TcpIpAddresses', 'Certificate')]
        [string]$OutputType = 'Full',
        [switch]$EnableException
    )

    begin {
        $scriptBlock = {
            # This scriptblock will be processed by Invoke-Command2 on the target machine.
            # We take an object as the first parameter which has to include the properties ComputerName, InstanceName and SqlFullName,
            # so normally a DbaInstanceParameter.
            $instance = $args[0]
            $verbose = @( )

            # As we go remote, ensure the assembly is loaded
            [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
            $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
            $null = $wmi.Initialize()
            $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $instance.InstanceName } ).ServerProtocols

            $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
            $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
            $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }

            $outputTcpIpProperties = [PSCustomObject]@{
                Enabled   = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' } ).Value
                KeepAlive = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' } ).Value
                ListenAll = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' } ).Value
            }

            $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
            $outputTcpIpAddressesIPn = foreach ($ip in $wmiIPn) {
                [PSCustomObject]@{
                    Name            = $ip.Name
                    Active          = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'Active' } ).Value
                    Enabled         = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'Enabled' } ).Value
                    IpAddress       = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'IpAddress' } ).Value
                    TcpDynamicPorts = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' } ).Value
                    TcpPort         = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' } ).Value
                }
            }

            $wmiIPAll = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -eq 'IPAll' }
            $outputTcpIpAddressesIPAll = [PSCustomObject]@{
                Name            = $wmiIPAll.Name
                TcpDynamicPorts = ($wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' } ).Value
                TcpPort         = ($wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' } ).Value
            }

            $wmiService = $wmi.Services | Where-Object { $_.DisplayName -eq "SQL Server ($($instance.InstanceName))" }
            $serviceAccount = $wmiService.ServiceAccount
            $regRoot = ($wmiService.AdvancedProperties | Where-Object Name -eq REGROOT).Value
            $vsname = ($wmiService.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            $verbose += "regRoot = '$regRoot' / vsname = '$vsname'"
            if ([System.String]::IsNullOrEmpty($regRoot)) {
                $regRoot = $wmiService.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                $vsname = $wmiService.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }
                $verbose += "regRoot = '$regRoot' / vsname = '$vsname'"
                if (![System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = ($regRoot -Split 'Value\=')[1]
                    $vsname = ($vsname -Split 'Value\=')[1]
                    $verbose += "regRoot = '$regRoot' / vsname = '$vsname'"
                } else {
                    $verbose += "Can't find regRoot"
                }
            }
            if ($regRoot) {
                $regPath = "Registry::HKEY_LOCAL_MACHINE\$regRoot\MSSQLServer\SuperSocketNetLib"
                try {
                    $acceptedSPNs = (Get-ItemProperty -Path $regPath -Name AcceptedSPNs).AcceptedSPNs
                    $thumbprint = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate
                    $cert = Get-ChildItem Cert:\LocalMachine -Recurse -ErrorAction SilentlyContinue | Where-Object Thumbprint -eq $thumbprint | Select-Object -First 1
                    $extendedProtection = switch ((Get-ItemProperty -Path $regPath -Name ExtendedProtection).ExtendedProtection) { 0 { $false } 1 { $true } }
                    $forceEncryption = switch ((Get-ItemProperty -Path $regPath -Name ForceEncryption).ForceEncryption) { 0 { $false } 1 { $true } }
                    $hideInstance = switch ((Get-ItemProperty -Path $regPath -Name HideInstance).HideInstance) { 0 { $false } 1 { $true } }

                    $outputCertificate = [PSCustomObject]@{
                        VSName          = $vsname
                        ServiceAccount  = $serviceAccount
                        ForceEncryption = $forceEncryption
                        FriendlyName    = $cert.FriendlyName
                        DnsNameList     = $cert.DnsNameList
                        Thumbprint      = $cert.Thumbprint
                        Generated       = $cert.NotBefore
                        Expires         = $cert.NotAfter
                        IssuedTo        = $cert.Subject
                        IssuedBy        = $cert.Issuer
                        Certificate     = $cert
                    }

                    $outputAdvanced = [PSCustomObject]@{
                        ForceEncryption    = $forceEncryption
                        HideInstance       = $hideInstance
                        AcceptedSPNs       = $acceptedSPNs
                        ExtendedProtection = $extendedProtection
                    }
                } catch {
                    $outputCertificate = $outputAdvanced = "Failed to get information from registry: $_"
                }
            } else {
                $outputCertificate = $outputAdvanced = "Failed to get information from registry: Path not found"
            }

            [PSCustomObject]@{
                ComputerName        = $instance.ComputerName
                InstanceName        = $instance.InstanceName
                SqlInstance         = $instance.SqlFullName.Trim('[]')
                SharedMemoryEnabled = $wmiSpSm.IsEnabled
                NamedPipesEnabled   = $wmiSpNp.IsEnabled
                TcpIpEnabled        = $wmiSpTcp.IsEnabled
                TcpIpProperties     = $outputTcpIpProperties
                TcpIpAddresses      = $outputTcpIpAddressesIPn + $outputTcpIpAddressesIPAll
                Certificate         = $outputCertificate
                Advanced            = $outputAdvanced
                Verbose             = $verbose
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $computerName = Resolve-DbaComputerName -ComputerName $instance.ComputerName -Credential $Credential
                $null = Test-ElevationRequirement -ComputerName $computerName -EnableException $true
                $netConf = Invoke-Command2 -ScriptBlock $scriptBlock -ArgumentList $instance -ComputerName $computerName -Credential $Credential -ErrorAction Stop
                foreach ($verbose in $netConf.Verbose) {
                    Write-Message -Level Verbose -Message $verbose
                }

                # Test if object is filled to test if instance was found on computer
                if ($null -eq $netConf.SharedMemoryEnabled) {
                    Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName). No data was found for this instance, so skipping." -Target $instance -ErrorRecord $_ -Continue
                }

                if ($OutputType -eq 'Full') {
                    [PSCustomObject]@{
                        ComputerName        = $netConf.ComputerName
                        InstanceName        = $netConf.InstanceName
                        SqlInstance         = $netConf.SqlInstance
                        SharedMemoryEnabled = $netConf.SharedMemoryEnabled
                        NamedPipesEnabled   = $netConf.NamedPipesEnabled
                        TcpIpEnabled        = $netConf.TcpIpEnabled
                        TcpIpProperties     = $netConf.TcpIpProperties
                        TcpIpAddresses      = $netConf.TcpIpAddresses
                        Certificate         = $netConf.Certificate
                        Advanced            = $netConf.Advanced
                    }
                } elseif ($OutputType -eq 'ServerProtocols') {
                    [PSCustomObject]@{
                        ComputerName        = $netConf.ComputerName
                        InstanceName        = $netConf.InstanceName
                        SqlInstance         = $netConf.SqlInstance
                        SharedMemoryEnabled = $netConf.SharedMemoryEnabled
                        NamedPipesEnabled   = $netConf.NamedPipesEnabled
                        TcpIpEnabled        = $netConf.TcpIpEnabled
                    }
                } elseif ($OutputType -eq 'TcpIpProperties') {
                    [PSCustomObject]@{
                        ComputerName = $netConf.ComputerName
                        InstanceName = $netConf.InstanceName
                        SqlInstance  = $netConf.SqlInstance
                        Enabled      = $netConf.TcpIpProperties.Enabled
                        KeepAlive    = $netConf.TcpIpProperties.KeepAlive
                        ListenAll    = $netConf.TcpIpProperties.ListenAll
                    }
                } elseif ($OutputType -eq 'TcpIpAddresses') {
                    if ($netConf.TcpIpProperties.ListenAll) {
                        $ipConf = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                        [PSCustomObject]@{
                            ComputerName    = $netConf.ComputerName
                            InstanceName    = $netConf.InstanceName
                            SqlInstance     = $netConf.SqlInstance
                            Name            = $ipConf.Name
                            TcpDynamicPorts = $ipConf.TcpDynamicPorts
                            TcpPort         = $ipConf.TcpPort
                        }
                    } else {
                        $ipConf = $netConf.TcpIpAddresses | Where-Object { $_.Name -ne 'IPAll' }
                        foreach ($ip in $ipConf) {
                            [PSCustomObject]@{
                                ComputerName    = $netConf.ComputerName
                                InstanceName    = $netConf.InstanceName
                                SqlInstance     = $netConf.SqlInstance
                                Name            = $ip.Name
                                Active          = $ip.Active
                                Enabled         = $ip.Enabled
                                IpAddress       = $ip.IpAddress
                                TcpDynamicPorts = $ip.TcpDynamicPorts
                                TcpPort         = $ip.TcpPort
                            }
                        }
                    }
                } elseif ($OutputType -eq 'Certificate') {
                    if ($netConf.Certificate -like 'Failed*') {
                        Stop-Function -Message "Failed to collect certificate information from $($instance.ComputerName) for instance $($instance.InstanceName): $($netConf.Certificate)" -Target $instance -Continue
                    }
                    $output = [PSCustomObject]@{
                        ComputerName    = $netConf.ComputerName
                        InstanceName    = $netConf.InstanceName
                        SqlInstance     = $netConf.SqlInstance
                        VSName          = $netConf.Certificate.VSName
                        ServiceAccount  = $netConf.Certificate.ServiceAccount
                        ForceEncryption = $netConf.Certificate.ForceEncryption
                        FriendlyName    = $netConf.Certificate.FriendlyName
                        DnsNameList     = $netConf.Certificate.DnsNameList
                        Thumbprint      = $netConf.Certificate.Thumbprint
                        Generated       = $netConf.Certificate.Generated
                        Expires         = $netConf.Certificate.Expires
                        IssuedTo        = $netConf.Certificate.IssuedTo
                        IssuedBy        = $netConf.Certificate.IssuedBy
                        Certificate     = $netConf.Certificate.Certificate
                    }
                    $defaultView = 'ComputerName,InstanceName,SqlInstance,VSName,ServiceAccount,ForceEncryption,FriendlyName,DnsNameList,Thumbprint,Generated,Expires,IssuedTo,IssuedBy'.Split(',')
                    if (-not $netConf.Certificate.VSName) {
                        $defaultView = $defaultView | Where-Object { $_ -ne 'VSNAME' }
                    }
                    $output | Select-DefaultView -Property $defaultView
                }
            } catch {
                Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}

# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCD4X7eDTrKvwAH
# 7Momii1K4OuaVitQYOh4EHxHT/fYZ6CCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCqaqcA6WtBl742UNBud2GjhKHmaq6SXa/7
# xpBREu9Q+DANBgkqhkiG9w0BAQEFAASCAQCFcgoYvI62rlEsbl9m5vy80VXONbZ7
# CrHtrm1Uzo/1GMqpU/ie563vzQaG3L8A8lSmZGD82RgDsBm4Yb4gK85jxcYtU0Lx
# jWkRa7dHolxuU0ylDQ3HnbTu3vuCW50vbFXg2UYhkzYY7oWTeLzkMvq1QdR50mi+
# KQ8H0pHUdz5serrefJAlGGKiG70tlbNr/OM/pNtAtW2hKbs6beSSqj4T/wYNJokR
# Xn4KxoA4yXaeNfzD32ypRGpFdQ2RTeLtli7VFy7SXy/ScRcFz7V/Bs4wwKHJaFZ7
# IyjgEEWgwWoYZeBstF+ilyQoC00sbLMNukuWQ6X0r9ics4eVSu8uzBCloYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMxMFowLwYJKoZIhvcNAQkEMSIEIEuLMpNd
# OTuaJkWiqNc7u8jXns5b3/okHSlPa26rXx5bMA0GCSqGSIb3DQEBAQUABIICAHaX
# +uf5VhFwWOtID15uWZgW3e+ZthAgwP4jqt0WxSS/Ff+41snxVCt97pv1nFsjLRFz
# l+7FN6UOTJZpMjrb0L6xnIQzJ5MJOxkx/x+60GBOVxDdQe7poffk1wROJ1l3mD/V
# Wdin9GdCefLS6F5bQbZb2T1Cb38ViTMWiJGe1MRwXmPuHljJ0d59iDqI977eKwrZ
# C/Q5b2iRlbZIjCQNI0CvSMLJKzjgNRdFDMoapmwf5Iexy4HdEdi3bNfWSpiEKST5
# 9Lb3TkL/Hwcg4YCEi8/sTrIii+aycq7hiSCF0PjdoNzG5GWTzf+HCNhDXhTpaIQO
# 62Ra/DAwqOmXIIfWNn08Bhv6rewjyr08kTbHg1yEMF5HocySIiBK6vS47FNbw0fw
# kaa5birApVtMZYZceSqLoZSsAWkpw717j9JciQgi43PoYFn8OPceynzuQYIo8zIQ
# vAAXMBVVsuq2qiXbFcQG2ypFu0f4vy26pkMEPy2yUPNBIP10qpRx70l/5oOuWi9S
# /vBx3lGBsyq7wdYzj9iny753QmKIOhyyhADaIZCLjhVAgiMx5xBgU5HuTlJzlZvc
# zVsfgo+9k4AGZv3MGSxkJA6S7fkgzpqdWMcfW42vhqFFGWC6HWSqo1cHy+uv3xVQ
# JzgDc4crR545DhP1VotU0uC2UHxSyM1dnoE5+wfh
# SIG # End signature block
