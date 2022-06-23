function Get-DbaService {
    <#
    .SYNOPSIS
        Gets the SQL Server related services on a computer.

    .DESCRIPTION
        Gets the SQL Server related services on one or more computers.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target computer(s).

    .PARAMETER InstanceName
        Only returns services that belong to the specific instances on all target computers.

    .PARAMETER SqlInstance
        Use a combination of computername and instancename to get the SQL Server related services for specific instances on specific computers.

        Parameters ComputerName and InstanceName will be ignored if SqlInstance is used.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Use -Type to collect only services of the desired SqlServiceType.
        Can be one of the following: "Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad"

    .PARAMETER ServiceName
        Can be used to specify service names explicitly, without looking for service types/instances.

    .PARAMETER AdvancedProperties
        Collect additional properties from the SqlServiceAdvancedProperty Namespace
        This collects information about Version, Service Pack Level", SkuName, Clustered status and the Cluster Service Name
        This adds additional overhead to the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Service, SqlServer, Instance, Connect
        Author: Klaas Vandenberghe ( @PowerDBAKlaas )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaService

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName sqlserver2014a

        Gets the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaService -AdvancedProperties

        Gets the SQL Server related services on computers sql1, sql2 and sql3. Includes Advanced Properties from the SqlServiceAdvancedProperty Namespace

    .EXAMPLE
        PS C:\> $cred = Get-Credential WindowsUser
        PS C:\> Get-DbaService -ComputerName sql1,sql2 -Credential $cred  | Out-GridView

        Gets the SQL Server related services on computers sql1 and sql2 via the user WindowsUser, and shows them in a grid view.

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName sql1,sql2 -InstanceName MSSQLSERVER

        Gets the SQL Server related services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> Get-DbaService -SqlInstance sql1, sql1\test, sql2\test

        Gets the SQL Server related services related to the default instance MSSQLSERVER on computers sql1, the named instances test on sql1 and sql2.

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName $MyServers -Type SSRS

        Gets the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

    .EXAMPLE
        PS C:\> $MyServers =  Get-Content .\servers.txt
        PS C:\> Get-DbaService -ComputerName $MyServers -ServiceName MSSQLSERVER,SQLSERVERAGENT

        Gets the SQL Server related services with ServiceName MSSQLSERVER or SQLSERVERAGENT  for all the servers that are stored in the file. Every line in the file can only contain one hostname for a server.

    .EXAMPLE
        PS C:\> $services = Get-DbaService -ComputerName sql1 -Type Agent,Engine
        PS C:\> $services.ChangeStartMode('Manual')

        Gets the SQL Server related services of types Sql Agent and DB Engine on computer sql1 and changes their startup mode to 'Manual'.

    .EXAMPLE
        PS C:\> (Get-DbaService -ComputerName sql1 -Type Engine).Restart($true)

        Calls a Restart method for each Engine service on computer sql1.

    #>
    [CmdletBinding(DefaultParameterSetName = "Search")]
    param (
        [parameter(ValueFromPipeline, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Search")]
        [Alias("Instance")]
        [string[]]$InstanceName,
        [Parameter(ParameterSetName = "Search")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = "Search")]
        [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad")]
        [string[]]$Type,
        [Parameter(ParameterSetName = "ServiceName")]
        [string[]]$ServiceName,
        [switch]$AdvancedProperties,
        [switch]$EnableException
    )

    begin {
        if ($SqlInstance) {
            # If SqlInstance is used, we select the list of computers for ComputerName
            $ComputerName = $SqlInstance | Select-Object -ExpandProperty ComputerName -Unique
        }

        #Dictionary to transform service type IDs into the names from Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer.Services.Type
        $ServiceIdMap = @(
            @{ Name = "Engine"; Id = 1 },
            @{ Name = "Agent"; Id = 2 },
            @{ Name = "FullText"; Id = 3, 9 },
            @{ Name = "SSIS"; Id = 4 },
            @{ Name = "SSAS"; Id = 5 },
            @{ Name = "SSRS"; Id = 6 },
            @{ Name = "Browser"; Id = 7 },
            @{ Name = "PolyBase"; Id = 10, 11 },
            @{ Name = "Launchpad"; Id = 12 },
            @{ Name = "Unknown"; Id = 8 }
        )
        if ($PsCmdlet.ParameterSetName -match 'Search') {
            if ($Type) {
                $searchClause = ""
                foreach ($itemType in $Type) {
                    foreach ($id in ($ServiceIdMap | Where-Object { $_.Name -eq $itemType }).Id) {
                        if ($searchClause) { $searchClause += ' OR ' }
                        $searchClause += "SQLServiceType = $id"
                    }
                }
            } else {
                $searchClause = "SQLServiceType > 0"
            }
        } elseif ($PsCmdlet.ParameterSetName -match 'ServiceName') {
            if ($ServiceName) {
                $searchClause = ""
                foreach ($sn in $ServiceName) {
                    if ($searchClause) { $searchClause += ' OR ' }
                    $searchClause += "ServiceName = '$sn'"
                }
            } else {
                $searchClause = "SQLServiceType > 0"
            }
        }
    }
    process {
        foreach ($computer in $ComputerName.ComputerName) {
            if ($SqlInstance) {
                # If SqlInstance is used, we select the list of instances for the current computer
                $InstanceName = $SqlInstance | Where-Object ComputerName -eq $computer | Select-Object -ExpandProperty InstanceName
            }

            try {
                $resolvedComputerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential -EnableException).FullComputerName
                $null = Get-DbaCmObject -ComputerName $resolvedComputerName -Credential $Credential -Namespace root\Microsoft -ClassName __NAMESPACE -EnableException
            } catch {
                Stop-Function -Message "Failed to resolve or to connect to $computer." -Target $computer -Category ConnectionError -ErrorRecord $_ -Continue
            }

            $namespaces = @( )
            $services = @()
            $outputServices = @()

            if (!$Type -or 'SSRS' -in $Type) {
                Write-Message -Level Verbose -Message "Getting SQL Reporting Server services on $computer" -Target $computer
                $reportingServices = Get-DbaReportingService -ComputerName $resolvedComputerName -InstanceName $InstanceName -Credential $Credential -ServiceName $ServiceName
                $outputServices += $reportingServices
            }

            Write-Message -Level Verbose -Message "Getting SQL Server namespaces on $computer" -Target $computer
            try {
                $namespaces = Get-DbaCmObject -ComputerName $resolvedComputerName -Credential $Credential -Namespace root\Microsoft\SQLServer -Query "Select Name FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'" -EnableException | Sort-Object Name -Descending
                Write-Message -Level Verbose -Message "The following namespaces have been found: $($namespaces.Name -join ', ')."
            } catch {
                Write-Message -Level Verbose -Message "No namespaces found in relevant namespace on $computer."
            }

            foreach ($namespace in $namespaces) {
                try {
                    Write-Message -Level Verbose -Message "Getting Cim class SqlService in Namespace $($namespace.Name) on $computer." -Target $computer
                    foreach ($service in (Get-DbaCmObject -ComputerName $resolvedComputerName -Credential $Credential -Namespace "root\Microsoft\SQLServer\$($namespace.Name)" -Query "SELECT * FROM SqlService WHERE $searchClause" -EnableException)) {
                        Write-Message -Level Verbose -Message "Found service $($service.ServiceName) in namespace $($namespace.Name)."
                        $services += $service
                    }
                    # Use highest namespace available, so break if services have been found
                    break
                } catch {
                    Write-Message -Level Verbose -Message "Failed to acquire services from namespace $($namespace.Name)." -Target $Computer -ErrorRecord $_
                }
            }

            # Remove services returned by the SSRS namespace
            $services = $services | Where-Object ServiceName -notin $reportingServices.ServiceName

            # Add custom properties and methods to the service objects
            foreach ($service in $services) {
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ComputerName -Value $service.HostName
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ServiceType -Value ($ServiceIdMap | Where-Object { $_.Id -contains $service.SQLServiceType }).Name
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name State -Value $(switch ($service.State) { 1 { 'Stopped' } 2 { 'Start Pending' }  3 { 'Stop Pending' } 4 { 'Running' } })
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name StartMode -Value $(switch ($service.StartMode) { 1 { 'Unknown' } 2 { 'Automatic' }  3 { 'Manual' } 4 { 'Disabled' } })

                if ($service.ServiceName -in ("MSSQLSERVER", "SQLSERVERAGENT", "ReportServer", "MSSQLServerOLAPService", "MSSQLFDLauncher", "SQLPBDMS", "SQLPBENGINE", "MSSQLLAUNCHPAD")) {
                    $instance = "MSSQLSERVER"
                } else {
                    if ($service.ServiceType -in @("Agent", "Engine", "SSRS", "SSAS", "FullText", "PolyBase", "Launchpad")) {
                        if ($service.ServiceName.indexof('$') -ge 0) {
                            $instance = $service.ServiceName.split('$')[1]
                        } else {
                            $instance = "Unknown"
                        }
                    } else {
                        $instance = ""
                    }
                }
                $priority = switch ($service.ServiceType) {
                    "Engine" { 200 }
                    default { 100 }
                }
                #If only specific instances are selected
                if (!$InstanceName -or $instance -in $InstanceName) {
                    #Add other properties and methods
                    Add-Member -Force -InputObject $service -NotePropertyName InstanceName -NotePropertyValue $instance
                    Add-Member -Force -InputObject $service -NotePropertyName ServicePriority -NotePropertyValue $priority
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Stop" -Value {
                        param ([bool]$Force = $false)
                        Stop-DbaService -InputObject $this -Force:$Force
                    }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Start" -Value { Start-DbaService -InputObject $this }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Restart" -Value {
                        param ([bool]$Force = $false)
                        Restart-DbaService -InputObject $this -Force:$Force
                    }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "ChangeStartMode" -Value {
                        param (
                            [parameter(Mandatory)]
                            [string]$Mode
                        )
                        $supportedModes = @("Automatic", "Manual", "Disabled")
                        if ($Mode -notin $supportedModes) {
                            Stop-Function -Message ("Incorrect mode '$Mode'. Use one of the following values: {0}" -f ($supportedModes -join ' | ')) -EnableException $false -FunctionName 'Get-DbaService'
                            Return
                        }
                        Set-ServiceStartMode -InputObject $this -Mode $Mode -ErrorAction Stop
                        $this.StartMode = $Mode
                    }

                    if ($AdvancedProperties) {
                        $namespaceValue = $service.CimClass.ToString().ToUpper().Replace(":SQLSERVICE", "").Replace("ROOT/MICROSOFT/SQLSERVER/", "")
                        $serviceAdvancedProperties = Get-DbaCmObject -ComputerName $Computer -Namespace "root\Microsoft\SQLServer\$($namespaceValue)" -Query "SELECT * FROM SqlServiceAdvancedProperty WHERE ServiceName = '$($service.ServiceName)'"

                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Version -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'VERSION' ).PropertyStrValue
                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name SPLevel -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'SPLEVEL' ).PropertyNumValue
                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name SkuName -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'SKUNAME' ).PropertyStrValue

                        $ClusterServiceTypeList = @(1, 2, 5, 7)
                        if ($ClusterServiceTypeList -contains $service.SQLServiceType) {
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Clustered -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'CLUSTERED' ).PropertyNumValue
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name VSName -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'VSNAME' ).PropertyStrValue
                        } else {
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Clustered -Value ''
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name VSName -Value ''
                        }
                    }
                    $outputServices += $service
                }
            }
            if ($AdvancedProperties) {
                $defaults = "ComputerName", "ServiceName", "ServiceType", "InstanceName", "DisplayName", "StartName", "State", "StartMode", "Version", "SPLevel", "SkuName", "Clustered", "VSName"
            } else {
                $defaults = "ComputerName", "ServiceName", "ServiceType", "InstanceName", "DisplayName", "StartName", "State", "StartMode"
            }
            if ($outputServices) {
                $outputServices | Select-DefaultView -Property $defaults -TypeName DbaSqlService
            } else {
                Write-Message -Level Verbose -Message "No services found in relevant namespaces on $computer."
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDXLhehhpm/l7iS
# UnExXoPNj90JxovsCoRlQRuREZwzyaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCB+TedQE85dr/S3ga31+CRl0KDQBMYjAqWn
# TztKIVtAgDANBgkqhkiG9w0BAQEFAASCAQAVcpNh9dRxH2OFN43pZmpoNgf8pBFH
# Hxnf3vu/GOXZzieIW/JCixeuIBUVb4YMdMbQJsHud8cwNCef5GhHylAYpGcjaAl4
# i81FnquvJrAJWyr4Im3eVttdfM2IHhpQyMDmJ4CXBoE+AmUcr5kXh6a1h/p6jZfB
# f8+74IcyilUv2Drpl/CZ5P/fkcQJxq2xMXHBdpcEbiGcMrGYETIEWG0lgUR3IaQV
# Q7PtK/fSCdIChOUW+puE/ymqyKpZaoUrm77DWZAlt/X+WFQJFTdr5SMjx/govFqp
# DH2G6fkcTY+Tshzc6NPAzDi1D5FI9gcNHKNJWkykYgUX6KBOYvnFRSV9oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMxN1owLwYJKoZIhvcNAQkEMSIEIOvXJ6i7
# baTh8zAHK8vMGQvGv8eiab+g0J01Rb53GrgnMA0GCSqGSIb3DQEBAQUABIICADDP
# 9WbWKuFcZE6nmgqwT8/w4xf1SVrmFP3JqSV8+v20fDAvEkbhwlELcHu4weB2Uxe8
# pgqhQ86h5L4F4T3XziRWEFAO4Ng1KNfkJWfiB7mm0v+1WLPa/FDO3Qe3WGm4mRH0
# VcwnvKFTRoZ4oWzZQQTUK6/OkclsH4ajL3+g4rmb3tUrmSCVlXGHr6lu5++vuSQf
# ltDx2+yWNbQ8UIbJgaIVovfgIF+9qebaKo6Yo2sFI+fMuj7yGziiFMjOdzCPFnhk
# 7mwvGZsr5ihHu2f/u37Z+aCK0zqZe67kNgNO3gvbKnxqHun9If8Rg9nPutX8Y7js
# BKKwYis/KNAG0XS5YcbbYmDEYnZwJ1OyWfUGH0aVBCeH/rY0Fh8aW1Dhor1QKT5L
# 2PT4wFiib9sWyH0sQdDsopcplEoIIloftHn/+CurxCNPP0/IUhCFyg/TQLstyMD5
# XYwt9u64npm/LzFQDo6x3s8R80HyQx8xRZOzeTRI3YrDPrKcVTEVUFU6FP2zMTNk
# gYyLNSX7k3wnCg22hDMWmrGhtahEWUpCNt4SuGrhcY9hNJbjBRx63LE6WDsY1mXS
# 9bYXVPaBtB1tZWyF+r6X+L7hMd4mo6+Y1Szzrtaq4VxGeUKgXLwWbFDn5/cJVwqT
# 7M8rWKqrtl2BUpNbPMIJ+yk/HebKZZcEZEXd1nej
# SIG # End signature block
