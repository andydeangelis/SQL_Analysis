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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUwLoINKSuMUbB22bEF4K23Lge
# SXOgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFEb23DvZmo8ZqYhsDwaF1XW7Jet7MA0G
# CSqGSIb3DQEBAQUABIIBABJJkHELK6tqcfpJgZ1O1yL63yH2JQGDXXIJJbEko+gB
# 8KdlXr/KZNWucEZDfzMj4zPwOgbTlcCodnFT1uhpzLp3BdfeKaQk0Sl5JZ+qxo+k
# ABngDvgljqT7d9/WvaCnvWYDAa+AuS8SQO6Pq4pFjVl/BSHtkryEaw+45y4tOhz6
# 85FGvp8d1Uki2m5TbWJu3L+VtR+0tCSp04yCIb+NcmqRmJRaGWmcZUywiawMZW1R
# sFhRcM7Q/1ZAVV2gCPg0+fn6XmkDsf4ywWUBnGs3CXw9toYyEMUbwirw1Q1mX5Kk
# VZ8GtCpUHEQ2poFRGR5hc2ayG0J3VlGeJ2cEkATf2KChggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzQ2WjAvBgkqhkiG9w0BCQQxIgQgOegQb9npVFDaGpTLQcTc
# Rdf6Om8G4RKoMOs04JBMUOYwDQYJKoZIhvcNAQEBBQAEggIANW0LFdBtRHXyCds2
# ++h7dKmPh4Cz15ieRYeRNFCEuDqBgrczh6qL0TqlGSm3WNPr0gEmSswhhQXyUO7J
# Vpylt0perS2EVziPVOKfE4Ia8Ht/yCVWLATdt+8iwJ1gFgAAOk+vt9Hb1kYQ9A+8
# L58fOzk6EH+uqu66CYkP+saH4XPKsQ0rEh9TcL7mcw6krVHPAMT6UKzeG45tGiey
# 2rknPwxBeJAx4w5D8CQrGAdUZ7in1/jYqX0ovoeEFROzi2E2Dac9FHi0Z9eASWQ8
# liMdwQziOGw8qZTtxqN09C+G3qgGwLMTUdVqCLtfs+eRz69VIzX4sfHLDzPgfaXf
# GPxNK/nZYhLOI/w9FQlxSqm27Me5ePZWwcL6ajwBl15zmQaY5ZQGt3Ov/gjK12jp
# /coeOEv4l3ZwuYZR1avnO9cD/feXNoP3cffEIQv4A3QuyYV8gnSNQrmfMYOJvGH2
# cVfRIA+l9c6cvAC2RqJMzNyIUHD1ZaAGa4EGh9Kks13yKUKvgqwgPbuCqm8tMHOB
# NkeDN1Ym4xsu5Y37D6NvI/YLFDgkc1UqVJnLadLWpTYG7ZRqeUYQ5lfMaZuU1UcS
# 3hMKXEgU78+PTrmjtazZGXPzRq3idwGlHCdeYC77OYec2Wyxnf7GsgM+xPueJKTd
# G06XQL0ph4ZsQBc9bcSDeRWoAks=
# SIG # End signature block
