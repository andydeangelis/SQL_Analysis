function Get-SQLInstanceComponent {
    <#
    .SYNOPSIS
        Retrieves SQL server information from a local or remote servers.
    .DESCRIPTION
        Retrieves SQL server information from a local or remote servers. Pulls all instances from a SQL server and
        detects if in a cluster or not.
    .PARAMETER ComputerName
        Local or remote systems to query for SQL information.
    .NOTES
        Tags: Install, Patching, SP, CU, Instance
        Author: Kirill Kravtsov (@nvarscar) https://nvarscar.wordpress.com/

        Based on https://github.com/adbertram/PSSqlUpdater
        The majority of this function was created by Boe Prox.
    .EXAMPLE
        Get-SQLInstanceComponent -ComputerName SQL01 -Component SSDS
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Database Engine
        InstanceName  : MSSQLSERVER
        InstanceID    : MSSQL11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        Description
        -----------
        Retrieves the SQL instance information from SQL01 for component type SSDS (Database Engine).
    .EXAMPLE
        Get-SQLInstanceComponent -ComputerName SQL01
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Analysis Services
        InstanceName  : MSSQLSERVER
        InstanceID    : MSAS11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Reporting Services
        InstanceName  : MSSQLSERVER
        InstanceID    : MSRS11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        Description
        -----------
        Retrieves the SQL instance information from SQL01 for all component types (SSAS, SSDS, SSRS).
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Computer', 'DNSHostName', 'IPAddress')]
        [DbaInstanceParameter[]]$ComputerName = $Env:COMPUTERNAME,
        [ValidateSet('SSDS', 'SSAS', 'SSRS')]
        [string[]]$Component = @('SSDS', 'SSAS', 'SSRS'),
        [pscredential]$Credential
    )

    begin {

        $regScript = {
            Param (
                $ComponentObject
            )
            $Component = $ComponentObject.Component
            $componentNameMap = @(
                [pscustomobject]@{
                    ComponentName = 'SSAS';
                    DisplayName   = 'Analysis Services';
                    RegKeyName    = "OLAP";
                },
                [pscustomobject]@{
                    ComponentName = 'SSDS';
                    DisplayName   = 'Database Engine';
                    RegKeyName    = 'SQL';
                },
                [pscustomobject]@{
                    ComponentName = 'SSRS';
                    DisplayName   = 'Reporting Services';
                    RegKeyName    = 'RS';
                }
            );

            function Get-SQLInstanceDetail {
                <#
                    .SYNOPSIS
                        The majority of this function was created by Boe Prox.
                #>
                param
                (
                    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
                    [string[]]$Instance,

                    [Parameter(Mandatory)]
                    [ValidateNotNullOrEmpty()]
                    [Microsoft.Win32.RegistryKey]$RegKey,

                    [Parameter(Mandatory)]
                    [ValidateNotNullOrEmpty()]
                    [Microsoft.Win32.RegistryKey]$reg,

                    [Parameter(Mandatory)]
                    [ValidateNotNullOrEmpty()]
                    [string]$RegPath
                )
                process {
                    #region Process each instance
                    foreach ($sqlInstance in $Instance) {
                        $log = @()
                        $nodes = New-Object System.Collections.ArrayList;
                        $clusterName = $null;
                        $isCluster = $false;
                        $instanceValue = $regKey.GetValue($sqlInstance);
                        $log += "Working with $regPath\$instanceValue on $computer"
                        $instanceReg = $reg.OpenSubKey("$regPath\\$instanceValue");
                        if ($instanceReg.GetSubKeyNames() -contains 'Cluster') {
                            $isCluster = $true;
                            $instanceRegCluster = $instanceReg.OpenSubKey('Cluster');
                            $clusterName = $instanceRegCluster.GetValue('ClusterName');
                            #Write-Message -Level Verbose -Message "Getting cluster node names";
                            $clusterReg = $reg.OpenSubKey("Cluster\\Nodes");
                            $clusterNodes = $clusterReg.GetSubKeyNames();
                            if ($clusterNodes) {
                                foreach ($clusterNode in $clusterNodes) {
                                    $null = $nodes.Add($clusterReg.OpenSubKey($clusterNode).GetValue("NodeName").ToUpper());
                                }
                            }
                        }

                        #region Gather additional information about SQL instance
                        $instanceRegSetup = $instanceReg.OpenSubKey("Setup")

                        #region Get SQL instance directory
                        try {
                            $instanceDir = $instanceRegSetup.GetValue("SqlProgramDir");
                            if (([System.IO.Path]::GetPathRoot($instanceDir) -ne $instanceDir) -and $instanceDir.EndsWith("\")) {
                                $instanceDir = $instanceDir.Substring(0, $instanceDir.Length - 1);
                            }
                        } catch {
                            $instanceDir = $null;
                        }
                        #endregion Get SQL instance directory

                        #region Get SQL edition
                        try {
                            $edition = $instanceRegSetup.GetValue("Edition");
                        } catch {
                            $edition = $null;
                        }
                        #endregion Get SQL edition

                        #region Get resume value
                        try {
                            $resume = [bool][int]$instanceRegSetup.GetValue("Resume");
                        } catch {
                            $resume = $false;
                        }
                        #endregion Get resume value

                        #region Get SQL version
                        $version = $null
                        try {
                            $versionHash = @{
                                '11' = 'SQLServer2012'
                                '12' = 'SQLServer2014'
                                '13' = 'SQLServer2016'
                                '14' = 'SQL2017'
                                '15' = 'SQL2019'
                            }
                            $version = $instanceRegSetup.GetValue("Version");
                            $log += "Found version $version"
                            if ($patchVersion = $instanceRegSetup.GetValue("PatchLevel")) {
                                $log += "Using patch version $patchVersion over $version"
                                $version = $patchVersion
                            }
                            # if patch version is not available - use global reg node to extract the latest patch
                            $majorVersion = $version.Split('.')[0]
                            if (!$patchVersion -and $majorVersion -and $versionHash[$majorVersion]) {
                                $verKey = $reg.OpenSubKey("SOFTWARE\\Microsoft\\Microsoft SQL Server\\$($majorVersion)0\\$($versionHash[$majorVersion])\\CurrentVersion")
                                $version = $verKey.GetValue('Version')
                                $log += "New version from the CurrentVersion key: $version"
                            }
                        } catch {
                            $log += "Failed to read one of the reg keys, found version $version so far"
                        }
                        #endregion Get SQL version

                        #region Get exe version
                        try {
                            # attempt to recover a real version of a sqlservr.exe by getting file properties from a remote machine
                            # not sure how to support SSRS/SSAS, as SSDS is the only one that has binary path in the Setup node
                            if ($binRoot = $instanceRegSetup.GetValue("SQLBinRoot")) {
                                $fileVersion = (Get-Item -Path (Join-Path $binRoot "sqlservr.exe") -ErrorAction Stop).VersionInfo.ProductVersion
                                if ($fileVersion) {
                                    $version = $fileVersion
                                    $log += "New version from the binary file: $version"
                                }
                            }
                        } catch {
                            $log += "Failed to get exe version, leaving $version as is"
                        }
                        #endregion Get exe version

                        #endregion Gather additional information about SQL instance

                        #region Generate return object
                        [pscustomobject]@{
                            ComputerName  = $computer.ToUpper();
                            InstanceName  = $sqlInstance;
                            InstanceID    = $instanceValue;
                            InstanceDir   = $instanceDir;
                            Edition       = $edition;
                            Version       = $version;
                            Caption       = {
                                switch -regex ($version) {
                                    "^11" { "SQL Server 2012"; break }
                                    "^10\.5" { "SQL Server 2008 R2"; break }
                                    "^10" { "SQL Server 2008"; break }
                                    "^9" { "SQL Server 2005"; break }
                                    "^8" { "SQL Server 2000"; break }
                                    default { "Unknown"; }
                                }
                            }.InvokeReturnAsIs();
                            IsCluster     = $isCluster;
                            IsClusterNode = ($nodes -contains $computer);
                            ClusterName   = $clusterName;
                            ClusterNodes  = ($nodes -ne $computer);
                            FullName      = {
                                if ($sqlInstance -eq "MSSQLSERVER") {
                                    $computer.ToUpper();
                                } else {
                                    "$($computer.ToUpper())\$($sqlInstance)";
                                }
                            }.InvokeReturnAsIs();
                            Log           = $log
                            Resume        = $resume
                        }
                        #endregion Generate return object
                    }
                    #endregion Process each instance
                }
            }
            $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Default')
            $baseKeys = "SOFTWARE\\Microsoft\\Microsoft SQL Server", "SOFTWARE\\Wow6432Node\\Microsoft\\Microsoft SQL Server";
            if ($reg.OpenSubKey($baseKeys[0])) {
                $regPath = $baseKeys[0];
            } elseif ($reg.OpenSubKey($baseKeys[1])) {
                $regPath = $baseKeys[1];
            } else {
                throw "Failed to find any regkeys on $env:computername"
            }

            $computer = $Env:COMPUTERNAME

            $regKey = $reg.OpenSubKey("$regPath");
            if ($regKey.GetSubKeyNames() -contains "Instance Names") {
                foreach ($componentName in $Component) {
                    $componentRegKeyName = $componentNameMap |
                        Where-Object { $_.ComponentName -eq $componentName } |
                        Select-Object -ExpandProperty RegKeyName;
                    $regKey = $reg.OpenSubKey("$regPath\\Instance Names\\{0}" -f $componentRegKeyName);
                    if ($regKey) {
                        foreach ($regValueName in $regKey.GetValueNames()) {
                            if ($componentRegKeyName -eq 'RS' -and $regValueName -eq 'PBIRS') { continue } #filtering out Power BI - not supported
                            if ($componentRegKeyName -eq 'RS' -and $regValueName -eq 'SSRS') { continue }  #filtering out SSRS2017+ - not supported
                            $result = Get-SQLInstanceDetail -RegPath $regPath -Reg $reg -RegKey $regKey -Instance $regValueName;
                            $result | Add-Member -Type NoteProperty -Name InstanceType -Value ($componentNameMap | Where-Object { $_.ComponentName -eq $componentName }).DisplayName -PassThru
                        }
                    }
                }
            } elseif ($regKey.GetValueNames() -contains 'InstalledInstances') {
                $isCluster = $false;
                $regKey.GetValue('InstalledInstances') | ForEach-Object {
                    Get-SQLInstanceDetail -RegPath $regPath -Reg $reg -RegKey $regKey -Instance $_
                };
            } else {
                throw "Failed to find any instance names on $env:computername"
            }
        }
    }
    process {
        foreach ($computer in $ComputerName) {
            $arguments = @{ Component = $Component }
            $results = Invoke-Command2 -ComputerName $computer -ScriptBlock $regScript -Credential $Credential -ErrorAction Stop -Raw -ArgumentList $arguments -RequiredPSVersion 3.0

            # Log is stored in the log property, pile it all into the debug log
            foreach ($logEntry in $results.Log) {
                Write-Message -Level Debug -Message $logEntry
            }
            foreach ($result in $results) {
                # If version is unknown that component should be excluded, otherwise it would fail on conversion. We have no use for versionless components anyways.
                if (-Not $result.Version) {
                    Write-Message -Level Warning -Message "Component $($result.InstanceName) on $($result.ComputerName) has an unknown version and was ommitted from the instance list"
                    continue
                }
                # Replace first decimal of the minor build with a 0, since we're using build numbers here
                # Refer to https://sqlserverbuilds.blogspot.com/
                Write-Message -Level Debug -Message "Converting version $($result.Version) to [version]"
                $newVersion = New-Object -TypeName System.Version -ArgumentList ([string]$result.Version)
                $newVersion = New-Object -TypeName System.Version -ArgumentList ($newVersion.Major , ($newVersion.Minor - $newVersion.Minor % 10), $newVersion.Build)
                Write-Message -Level Debug -Message "Converted version $($result.Version) to $newVersion"
                # Find a proper build reference and replace Version property
                $result.Version = Get-DbaBuild -Build $newVersion -EnableException
                $result | Select-Object -ExcludeProperty Log
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUoA05ugsV39okM+SwS1im8Ei+
# gXugghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFHPRBVU0Y8vziVWbHaoX98I33g5AMA0G
# CSqGSIb3DQEBAQUABIIBAImCt46WEJWFZ1OZTgl81f9ZpvNGPiEzFslfydHBhCkH
# t01DcesOFTsBY1OsU1SywSMiGZ4aGp0v78slUA7mCb1tlCVYo40l+mgeGE3YnNwC
# X6VZEObB20AANgsvXGaItx1Orhjk+l2NvXVbeu74QvbzTDP69wRR22iQZbL+9sFY
# F0hsGoBEAdT97oCBM38/LQ7nyzvcXXh2ttgVbCbuEpp7Siqfo6M1ic/QZNnlKJK4
# TCvd+HwhewRzS9LeUkd8qFNUMgCGYW7dlbbCLTuHTYjT/UarlVnXyzoXT4rHh+c/
# wfRNz82BUFNVU9pC1LImABV3N2zSQLEFk0SG9uleyzihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDUxWjAvBgkqhkiG9w0BCQQxIgQgH1n4SkPwNXRleCMPAdLC
# aH4elD/LI6C+LICaVMhJ6YAwDQYJKoZIhvcNAQEBBQAEggIAg5W1kjLPx4VjBQQK
# EnC5rKZBYQK4apzGB90/Y7ZkheiTBW7T5TtYEmrYJRVMQp7pa2ra/s/wX4gslO6o
# PpFI2LorasuLoHZyS8Ul78C/fifvAvwGAXgooXBWUcHvqR1ggPRecBU1+CKVHcBG
# Ikc7P3uduowvm3n0+JkEKInTCs+x2oJOFa1C4qPqeDe09zy/dCQtshAOtSQeAiUX
# ERY03hMNlpJGlXwZFwxc4n4XqHJmTE0FJGZ2tMK5EHSwkqjtjj3hr1vM8dnno38A
# 2VigYLveuclPvOcKKKQEKPtRAkAolHVD1r36Y7KNdS7TmykUtw9+xmQ3E9eJJpCn
# oZ+9isX/hqA8HRCJ6/kDJf5uBrox7kmytxY2R96AWVLi3QahcBcQwSqZ3fe9fz4K
# ANpBdiSKBKHeNSYKQkOJWsViBmpTeCc2yYblMTD5PQldRfHe3vDMte/APo83SZUJ
# ZzE/ZJ6XwXYA3PQGi/SM2aVkjQSh5ZHI1JwjX0VK91nI/odv0MteHYoKjCkBLJgl
# M6Db7mRgzBYTjuE+ERXyWZB9DF6TaPUh6c4a6FvklEELdD/nauN6tJ8VsTejKpza
# 8MTo+wvjie3t7DIZ88SIdkYoY3thwP/+Rzny8XAeY0L6IWFhbVT5udgju+z0/L4V
# lq5+yAS1uojcBXqVoUTGdzLjdlg=
# SIG # End signature block
