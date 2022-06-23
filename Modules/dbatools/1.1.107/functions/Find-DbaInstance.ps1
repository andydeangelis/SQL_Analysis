function Find-DbaInstance {
    <#
    .SYNOPSIS
        Search for SQL Server Instances.

    .DESCRIPTION
        This function searches for SQL Server Instances.

        It supports a variety of scans for this purpose which can be separated in two categories:
        - Discovery
        - Scan

        Discovery:
        This is where it compiles a list of computers / addresses to check.
        It supports several methods of generating such lists (including Active Directory lookup or IP Ranges), but also supports specifying a list of computers to check.
        - For details on discovery, see the documentation on the '-DiscoveryType' parameter
        - For details on explicitly providing a list, see the documentation on the '-ComputerName' parameter

        Scan:
        Once a list of computers has been provided, this command will execute a variety of actions to determine any instances present for each of them.
        This is described in more detail in the documentation on the '-ScanType' parameter.
        Additional parameters allow more granular control over individual scans (e.g. Credentials to use).

        Note on logging and auditing:
        The Discovery phase is un-problematic since it is non-intrusive, however during the scan phase, all targeted computers may be accessed repeatedly.
        This may cause issues with security teams, due to many logon events and possibly failed authentication.
        This action constitutes a network scan, which may be illegal depending on the nation you are in and whether you own the network you scan.
        If you are unsure whether you may use this command in your environment, check the detailed description on the '-ScanType' parameter and contact your IT security team for advice.

    .PARAMETER ComputerName
        The computer to scan. Can be a variety of input types, including text or the output of Get-ADComputer.
        Any extra instance information (such as connection strings or live sql server connections) beyond the computername will be discarded.

    .PARAMETER DiscoveryType
        The mechanisms to be used to discover instances.
        Supports any combination of:
        - Service Principal Name lookup ('DomainSPN'; from Active Directory)
        - SQL Instance Enumeration ('DataSourceEnumeration'; same as SSMS uses)
        - IP Address range ('IPRange'; all IP Addresses will be scanned)
        - Domain Server lookup ('DomainServer'; from Active Directory)

        SPN Lookup:
        The function tries to connect active directory to look up all computers with registered SQL Instances.
        Not all instances need to be registered properly, making this not 100% reliable.
        By default, your nearest Domain Controller is contacted for this scan.
        However it is possible to explicitly state the DC to contact using its DistinguishedName and the '-DomainController' parameter.
        If credentials were specified using the '-Credential' parameter, those same credentials are used to perform this lookup, allowing the scan of other domains.

        SQL Instance Enumeration:
        This uses the default UDP Broadcast based instance enumeration used by SSMS to detect instances.
        Note that the result from this is not used in the actual scan, but only to compile a list of computers to scan.
        To enable the same results for the scan, ensure that the 'Browser' scan is enabled.

        IP Address range:
        This 'Discovery' uses a range of IPAddresses and simply passes them on to be tested.
        See the 'Description' part of help on security issues of network scanning.
        By default, it will enumerate all ethernet network adapters on the local computer and scan the entire subnet they are on.
        By using the '-IpAddress' parameter, custom network ranges can be specified.

        Domain Server:
        This will discover every single computer in Active Directory that is a Windows Server and enabled.
        By default, your nearest Domain Controller is contacted for this scan.
        However it is possible to explicitly state the DC to contact using its DistinguishedName and the '-DomainController' parameter.
        If credentials were specified using the '-Credential' parameter, those same credentials are used to perform this lookup, allowing the scan of other domains.

    .PARAMETER Credential
        The credentials to use on windows network connection.
        These credentials are used for:
        - Contact to domain controllers for SPN lookups (only if explicit Domain Controller is specified)
        - CIM/WMI contact to the scanned computers during the scan phase (see the '-ScanType' parameter documentation on affected scans).

    .PARAMETER SqlCredential
        The credentials used to connect to SqlInstances to during the scan phase.
        See the '-ScanType' parameter documentation on affected scans.

    .PARAMETER ScanType

        The scans are the individual methods used to retrieve information about the scanned computer and any potentially installed instances.
        This parameter is optional, by default all scans except for establishing an actual SQL connection are performed.
        Scans can be specified in any arbitrary combination, however at least one instance detecting scan needs to be specified in order for data to be returned.

        Scans:
        Browser
        - Tries discovering all instances via the browser service
        - This scan detects instances.

        SQLService
        - Tries listing all SQL Services using CIM/WMI
        - This scan uses credentials specified in the '-Credential' parameter if any.
        - This scan detects instances.
        - Success in this scan guarantees high confidence (See parameter '-MinimumConfidence' for details).

        SPN
        - Tries looking up the Service Principal Names for each instance
        - Will use the nearest Domain Controller by default
        - Target a specific domain controller using the '-DomainController' parameter
        - If using the '-DomainController' parameter, use the '-Credential' parameter to specify the credentials used to connect

        TCPPort
        - Tries connecting to the TCP Ports.
        - By default, port 1433 is connected to.
        - The parameter '-TCPPort' can be used to provide a list of port numbers to scan.
        - This scan detects possible instances. Since other services might bind to a given port, this is not the most reliable test.
        - This scan is also used to validate found SPNs if both scans are used in combination

        DNSResolve
        - Tries resolving the computername in DNS

        Ping
        - Tries pinging the computer. Failure will NOT terminate scans.

        SqlConnect
        - Tries to establish a SQL connection to the server
        - Uses windows credentials by default
        - Specify custom credentials using the '-SqlCredential' parameter
        - This scan is not used by default
        - Success in this scan guarantees high confidence (See parameter '-MinimumConfidence' for details).

        All
        - All of the above

    .PARAMETER IpAddress
        This parameter can be used to override the defaults for the IPRange discovery.
        This parameter accepts a list of strings supporting any combination of:
        - Plain IP Addresses (e.g.: "10.1.1.1")
        - IP Address Ranges (e.g.: "10.1.1.1-10.1.1.5")
        - IP Address & Subnet Mask (e.g.: "10.1.1.1/255.255.255.0")
        - IP Address & Subnet Length: (e.g.: "10.1.1.1/24)
        Overlapping addresses will not result in duplicate scans.

    .PARAMETER DomainController
        The domain controller to contact for SPN lookups / searches.
        Uses the credentials from the '-Credential' parameter if specified.

    .PARAMETER TCPPort
        The ports to scan in the TCP Port Scan method.
        Defaults to 1433.

    .PARAMETER MinimumConfidence
        This command tries to discover instances, which isn't always a sure thing.
        Depending on the number and type of scans completed, we have different levels of confidence in our results.
        By default, we will return anything that we have at least a low confidence of being an instance.
        These are the confidence levels we support and how they are determined:
        - High: Established SQL Connection (including rejection for bad credentials) or service scan.
        - Medium: Browser reply or a combination of TCPConnect _and_ SPN test.
        - Low: Either TCPConnect _or_ SPN
        - None: Computer existence could be verified, but no sign of an SQL Instance

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, Connect, SqlServer, Lookup
        Author: Scott Sutherland, 2018 NetSPI | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Outside resources used and modified:
        https://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b

    .LINK
        https://dbatools.io/Find-DbaInstance

    .EXAMPLE
        PS C:\> Find-DbaInstance -DiscoveryType Domain, DataSourceEnumeration

        Performs a network search for SQL Instances by:
        - Looking up the Service Principal Names of computers in Active Directory
        - Using the UDP broadcast based auto-discovery of SSMS
        After that it will extensively scan all hosts thus discovered for instances.

    .EXAMPLE
        PS C:\> Find-DbaInstance -DiscoveryType All

        Performs a network search for SQL Instances, using all discovery protocols:
        - Active directory search for Service Principal Names
        - SQL Instance Enumeration (same as SSMS does)
        - All IPAddresses in the current computer's subnets of all connected network interfaces
        Note: This scan will take a long time, due to including the IP Scan

    .EXAMPLE
        PS C:\> Get-ADComputer -Filter "*" | Find-DbaInstance

        Scans all computers in the domain for SQL Instances, using a deep probe:
        - Tries resolving the name in DNS
        - Tries pinging the computer
        - Tries listing all SQL Services using CIM/WMI
        - Tries discovering all instances via the browser service
        - Tries connecting to the default TCP Port (1433)
        - Tries connecting to the TCP port of each discovered instance
        - Tries to establish a SQL connection to the server using default windows credentials
        - Tries looking up the Service Principal Names for each instance

    .EXAMPLE
        PS C:\> Get-Content .\servers.txt | Find-DbaInstance -SqlCredential $cred -ScanType Browser, SqlConnect

        Reads all servers from the servers.txt file (one server per line),
        then scans each of them for instances using the browser service
        and finally attempts to connect to each instance found using the specified credentials.
        then scans each of them for instances using the browser service and SqlService

    .EXAMPLE
        PS C:\> Find-DbaInstance -ComputerName localhost | Get-DbaDatabase | Format-Table -Wrap

        Scans localhost for instances using the browser service, traverses all instances for all databases and displays all information in a formatted table.

    .EXAMPLE
        PS C:\> $databases = Find-DbaInstance -ComputerName localhost | Get-DbaDatabase
        PS C:\> $results = $databases | Select-Object SqlInstance, Name, Status, RecoveryModel, SizeMB, Compatibility, Owner, LastFullBackup, LastDiffBackup, LastLogBackup
        PS C:\> $results | Format-Table -Wrap

        Scans localhost for instances using the browser service, traverses all instances for all databases and displays a subset of the important information in a formatted table.

        Using this method regularly is not recommended. Use Get-DbaService or Get-DbaRegServer instead.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification = "Internal functions are ignored")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Computer', ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [Parameter(Mandatory, ParameterSetName = 'Discover')]
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]$DiscoveryType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [ValidateSet('Default', 'SQLService', 'Browser', 'TCPPort', 'All', 'SPN', 'Ping', 'SqlConnect', 'DNSResolve')]
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType[]]$ScanType = "Default",
        [Parameter(ParameterSetName = 'Discover')]
        [string[]]$IpAddress,
        [string]$DomainController,
        [int[]]$TCPPort = 1433,
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]$MinimumConfidence = 'Low',
        [switch]$EnableException
    )

    begin {

        #region Utility Functions
        function Test-SqlInstance {
            <#
            .SYNOPSIS
                Performs the actual scanning logic

            .DESCRIPTION
                Performs the actual scanning logic
                Each potential target is accessed using the specified scan routines.

            .PARAMETER Target
                The target to scan.

            .EXAMPLE
                PS C:\> Test-SqlInstance
        #>
            [CmdletBinding()]
            param (
                [Parameter(ValueFromPipeline)][DbaInstance[]]$Target,
                [PSCredential]$Credential,
                [PSCredential]$SqlCredential,
                [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]$ScanType,
                [string]$DomainController,
                [int[]]$TCPPort = 1433,
                [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]$MinimumConfidence,
                [switch]$EnableException
            )

            begin {
                [System.Collections.ArrayList]$computersScanned = @()
            }

            process {
                foreach ($computer in $Target) {
                    $stepCounter = 0
                    if ($computersScanned.Contains($computer.ComputerName)) {
                        continue
                    } else {
                        $null = $computersScanned.Add($computer.ComputerName)
                    }
                    Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Starting"
                    Write-Message -Level Verbose -Message "Processing: $($computer)" -Target $computer -FunctionName Find-DbaInstance

                    #region Null variables to prevent scope lookup on conditional existence
                    $resolution = $null
                    $pingReply = $null
                    $sPNs = @()
                    $ports = @()
                    $browseResult = $null
                    $services = @()
                    #Variable marked as unused by PSScriptAnalyzer
                    #$serverObject = $null
                    #$browseFailed = $false
                    #endregion Null variables to prevent scope lookup on conditional existence

                    #region Gather data
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::DNSResolve) {
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Performing DNS resolution"
                            $resolution = [System.Net.Dns]::GetHostEntry($computer.ComputerName)
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::Ping) {
                        $ping = New-Object System.Net.NetworkInformation.Ping
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Waiting for ping response"
                            $pingReply = $ping.Send($computer.ComputerName)
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SPN) {
                        $computerByName = $computer.ComputerName
                        if ($resolution.HostName) { $computerByName = $resolution.HostName }
                        if ($computerByName -notmatch "$([dbargx]::IPv4)|$([dbargx]::IPv6)") {
                            try {
                                Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Finding SPNs"
                                $sPNs = Get-DomainSPN -DomainController $DomainController -Credential $Credential -ComputerName $computerByName -GetSPN
                            } catch {
                                # here to avoid an empty catch
                                $null = 1
                            }
                        }
                    }

                    # $ports required for all scans
                    Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Testing TCP ports"
                    $ports = $TCPPort | Test-TcpPort -ComputerName $computer

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::Browser) {
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Probing Browser service"
                            $browseResult = Get-SQLInstanceBrowserUDP -ComputerName $computer -EnableException
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SqlService) {
                        Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Finding SQL services using SQL WMI"
                        if ($Credential) {
                            $services = Get-DbaService -ComputerName $computer -Credential $Credential -EnableException -ErrorAction Ignore -WarningAction SilentlyCOntinue
                        } else {
                            $services = Get-DbaService -ComputerName $computer -ErrorAction Ignore -WarningAction SilentlyContinue
                        }
                    }
                    #endregion Gather data

                    #region Gather list of found instance indicators
                    $instanceNames = @()
                    if ($Services) {
                        $Services | Select-Object -ExpandProperty InstanceName -Unique | Where-Object { $_ -and ($instanceNames -notcontains $_) } | ForEach-Object {
                            $instanceNames += $_
                        }
                    }
                    if ($browseResult) {
                        $browseResult | Select-Object -ExpandProperty InstanceName -Unique | Where-Object { $_ -and ($instanceNames -notcontains $_) } | ForEach-Object {
                            $instanceNames += $_
                        }
                    }

                    $portsDetected = @()
                    foreach ($portResult in $ports) {
                        if ($portResult.IsOpen) { $portsDetected += $portResult.Port }
                    }
                    foreach ($sPN in $sPNs) {
                        try { $inst = $sPN.Split(':')[1] }
                        catch { continue }

                        try {
                            [int]$portNumber = $inst
                            if ($portNumber -and ($portsDetected -notcontains $portNumber)) {
                                $portsDetected += $portNumber
                            }
                        } catch {
                            if ($inst -and ($instanceNames -notcontains $inst)) {
                                $instanceNames += $inst
                            }
                        }
                    }
                    #endregion Gather list of found instance indicators

                    #region Case: Nothing found
                    if ((-not $instanceNames) -and (-not $portsDetected)) {
                        if ($resolution -or ($pingReply.Status -like "Success")) {
                            if ($MinimumConfidence -eq [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]::None) {
                                New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport -Property @{
                                    MachineName  = $computer.ComputerName
                                    ComputerName = $computer.ComputerName
                                    Ping         = $pingReply.Status -like 'Success'
                                }
                            } else {
                                Write-Message -Level Verbose -Message "Computer $computer could be contacted, but no trace of an SQL Instance was found. Skipping..." -Target $computer -FunctionName Find-DbaInstance
                            }
                        } else {
                            Write-Message -Level Verbose -Message "Computer $computer could not be contacted, skipping." -Target $computer -FunctionName Find-DbaInstance
                        }

                        continue
                    }
                    #endregion Case: Nothing found

                    [System.Collections.ArrayList]$masterList = @()

                    #region Case: Named instance found
                    foreach ($instance in $instanceNames) {
                        $object = New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport
                        $object.MachineName = $computer.ComputerName
                        $object.ComputerName = $computer.ComputerName
                        $object.InstanceName = $instance
                        $object.DnsResolution = $resolution
                        $object.Ping = $pingReply.Status -like 'Success'
                        $object.ScanTypes = $ScanType
                        $object.Services = $services | Where-Object InstanceName -EQ $instance
                        $object.SystemServices = $services | Where-Object { -not $_.InstanceName }
                        $object.SPNs = $sPNs

                        if ($result = $browseResult | Where-Object InstanceName -EQ $instance) {
                            $object.BrowseReply = $result
                        }
                        if ($ports) {
                            $object.PortsScanned = $ports
                        }

                        if ($object.BrowseReply) {
                            $object.Confidence = 'Medium'
                            if ($object.BrowseReply.TCPPort) {
                                $object.Port = $object.BrowseReply.TCPPort

                                $object.PortsScanned | Where-Object Port -EQ $object.Port | ForEach-Object {
                                    $object.TcpConnected = $_.IsOpen
                                }
                            }
                        }
                        if ($object.Services) {
                            $object.Confidence = 'High'

                            $engine = $object.Services | Where-Object ServiceType -EQ "Engine"
                            switch ($engine.State) {
                                "Running" { $object.Availability = 'Available' }
                                "Stopped" { $object.Availability = 'Unavailable' }
                                default { $object.Availability = 'Unknown' }
                            }
                        }

                        $object.Timestamp = Get-Date

                        $masterList += $object
                    }
                    #endregion Case: Named instance found

                    #region Case: Port number found
                    foreach ($port in $portsDetected) {
                        if ($masterList.Port -contains $port) { continue }

                        $object = New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport
                        $object.MachineName = $computer.ComputerName
                        $object.ComputerName = $computer.ComputerName
                        $object.Port = $port
                        $object.DnsResolution = $resolution
                        $object.Ping = $pingReply.Status -like 'Success'
                        $object.ScanTypes = $ScanType
                        $object.SystemServices = $services | Where-Object { -not $_.InstanceName }
                        $object.SPNs = $sPNs
                        $object.Confidence = 'Low'
                        if ($ports) {
                            $object.PortsScanned = $ports

                            if (($ports | Where-Object IsOpen).Port -eq 1433) {
                                $object.Confidence = 'Medium'
                            }
                        }

                        if (($ports.Port -contains $port) -and ($sPNs | Where-Object { $_ -like "*:$port" })) {
                            $object.Confidence = 'Medium'
                        }

                        $object.PortsScanned | Where-Object Port -EQ $object.Port | ForEach-Object {
                            $object.TcpConnected = $_.IsOpen
                        }
                        $object.Timestamp = Get-Date

                        if ($masterList.SqlInstance -contains $object.SqlInstance) {
                            continue
                        }

                        $masterList += $object
                    }
                    #endregion Case: Port number found

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SqlConnect) {
                        $instanceHash = @{ }
                        $toDelete = @()
                        foreach ($dataSet in $masterList) {
                            try {
                                $server = Connect-DbaInstance -SqlInstance $dataSet.FullSmoName -SqlCredential $SqlCredential
                                $dataSet.SqlConnected = $true
                                $dataSet.Confidence = 'High'

                                # Remove duplicates
                                if ($instanceHash.ContainsKey($server.DomainInstanceName)) {
                                    $toDelete += $dataSet
                                } else {
                                    $instanceHash[$server.DomainInstanceName] = $dataSet

                                    try {
                                        $dataSet.MachineName = $server.ComputerNamePhysicalNetBIOS
                                    } catch {
                                        # here to avoid an empty catch
                                        $null = 1
                                    }
                                }
                            } catch {
                                # Error class definitions
                                # https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-error-severities
                                # 24 or less means an instance was found, but had some issues

                                #region Processing error (Access denied, server error, ...)
                                if ($_.Exception.InnerException.Errors.Class -lt 25) {
                                    # There IS an SQL Instance and it listened to network traffic
                                    $dataSet.SqlConnected = $true
                                    $dataSet.Confidence = 'High'
                                }
                                #endregion Processing error (Access denied, server error, ...)

                                #region Other connection errors
                                else {
                                    $dataSet.SqlConnected = $false
                                }
                                #endregion Other connection errors
                            }
                        }

                        foreach ($item in $toDelete) {
                            $masterList.Remove($item)
                        }
                    }

                    $masterList | Where-Object { $_.Confidence -ge $MinimumConfidence }
                }
            }
        }

        function Get-DomainSPN {
            <#
            .SYNOPSIS
                Returns all computernames with registered MSSQL SPNs.

            .DESCRIPTION
                Returns all computernames with registered MSSQL SPNs.

            .PARAMETER DomainController
                The domain controller to ask.

            .PARAMETER Credential
                The credentials to use while asking.

            .PARAMETER ComputerName
                Filter by computername

            .PARAMETER GetSPN
                Returns the service SPNs instead of the hostname

            .EXAMPLE
                PS C:\> Get-DomainSPN -DomainController $DomainController -Credential $Credential

                Returns all computernames with MSQL SPNs known to $DomainController, assuming credentials are valid.
        #>
            [CmdletBinding()]
            param (
                [string]$DomainController,
                [Pscredential]$Credential,
                [string]$ComputerName = "*",
                [switch]$GetSPN
            )

            try {
                if ($DomainController) {
                    if ($Credential) {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController", $Credential.UserName, $Credential.GetNetworkCredential().Password
                    } else {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController"
                    }
                } else {
                    $entry = [ADSI]''
                }
                $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry

                $objSearcher.PageSize = 200
                $objSearcher.Filter = "(&(servicePrincipalName=MSSQLsvc*)(|(name=$ComputerName)(dnshostname=$ComputerName)))"
                $objSearcher.SearchScope = 'Subtree'

                $results = $objSearcher.FindAll()
                foreach ($computer in $results) {
                    if ($GetSPN) {
                        $computer.Properties["serviceprincipalname"] | Where-Object { $_ -like "MSSQLsvc*:*" }
                    } else {
                        if ($computer.Properties["dnshostname"] -and $computer.Properties["dnshostname"] -ne '') {
                            $computer.Properties["dnshostname"][0]
                        } else {
                            $computer.Properties["serviceprincipalname"][0] -match '(?<=/)[^:]*' > $null
                            if ($matches) {
                                $matches[0]
                            } else {
                                $computer.Properties["name"][0]
                            }
                        }
                    }
                }
            } catch {
                throw
            }
        }

        function Get-DomainServer {
            <#
            .SYNOPSIS
                Returns a list of all Domain Computer objects that are servers.

            .DESCRIPTION
                Returns a list of all Domain Computer objects that are ...
                - Enabled
                - Have an OS named like "*windows*server*"

            .PARAMETER DomainController
                The domain controller to ask.

            .PARAMETER Credential
                The credentials to use while asking.

            .EXAMPLE
                PS C:\> Get-DomainServer

                Returns a list of all Domain Computer objects that are servers.
        #>
            [CmdletBinding()]
            param (
                [string]$DomainController,
                [Pscredential]$Credential
            )

            try {
                if ($DomainController) {
                    if ($Credential) {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController", $Credential.UserName, $Credential.GetNetworkCredential().Password
                    } else {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController"
                    }
                } else {
                    $entry = [ADSI]''
                }
                $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry

                $objSearcher.PageSize = 200
                $objSearcher.Filter = "(&(objectcategory=computer)(operatingSystem=*windows*server*)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
                $objSearcher.SearchScope = 'Subtree'

                $results = $objSearcher.FindAll()
                foreach ($computer in $results) {
                    if ($computer.Properties["dnshostname"]) {
                        $computer.Properties["dnshostname"][0]
                    } else {
                        $computer.Properties["name"][0]
                    }
                }
            } catch { throw }
        }

        function Get-SQLInstanceBrowserUDP {
            <#
            .SYNOPSIS
                Requests a list of instances from the browser service.

            .DESCRIPTION
                Requests a list of instances from the browser service.

            .PARAMETER ComputerName
                Computer name or IP address to enumerate SQL Instance from.

            .PARAMETER UDPTimeOut
                Timeout in seconds. Longer timeout = more accurate.

            .PARAMETER EnableException
                By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
                This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
                Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

            .EXAMPLE
                PS C:\> Get-SQLInstanceBrowserUDP -ComputerName 'sql2017'

                Contacts the browsing service on sql2017 and requests its instance information.

            .NOTES
                Original Author: Eric Gruber
                Editors:
                - Scott Sutherland (Pipeline and timeout mods)
                - Friedrich Weinmann (Cleanup & dbatools Standardization)

        #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory, ValueFromPipeline)][DbaInstance[]]$ComputerName,
                [int]$UDPTimeOut = 2,
                [switch]$EnableException
            )

            process {
                foreach ($computer in $ComputerName) {
                    try {
                        #region Connect to browser service and receive response
                        $UDPClient = New-Object -TypeName System.Net.Sockets.Udpclient
                        $UDPClient.Client.ReceiveTimeout = $UDPTimeOut * 1000
                        $UDPClient.Connect($computer.ComputerName, 1434)
                        $UDPPacket = 0x03
                        $UDPEndpoint = New-Object -TypeName System.Net.IpEndPoint -ArgumentList ([System.Net.Ipaddress]::Any, 0)
                        $UDPClient.Client.Blocking = $true
                        [void]$UDPClient.Send($UDPPacket, $UDPPacket.Length)
                        $BytesRecived = $UDPClient.Receive([ref]$UDPEndpoint)
                        # Skip first three characters, since those contain trash data (SSRP metadata)
                        #$Response = [System.Text.Encoding]::ASCII.GetString($BytesRecived[3..($BytesRecived.Length - 1)])
                        $Response = [System.Text.Encoding]::ASCII.GetString($BytesRecived)
                        #endregion Connect to browser service and receive response

                        #region Parse Output
                        $Response | Select-String "(ServerName;(\w+);InstanceName;(\w+);IsClustered;(\w+);Version;(\d+\.\d+\.\d+\.\d+);(tcp;(\d+)){0,1})" -AllMatches | Select-Object -ExpandProperty Matches | ForEach-Object {
                            $obj = New-Object Sqlcollaborative.Dbatools.Discovery.DbaBrowserReply -Property @{
                                MachineName  = $computer.ComputerName
                                ComputerName = $_.Groups[2].Value
                                SqlInstance  = "$($_.Groups[2].Value)\$($_.Groups[3].Value)"
                                InstanceName = $_.Groups[3].Value
                                Version      = $_.Groups[5].Value
                                IsClustered  = "Yes" -eq $_.Groups[4].Value
                            }
                            if ($_.Groups[7].Success) {
                                $obj.TCPPort = $_.Groups[7].Value
                            }
                            $obj
                        }
                        #endregion Parse Output

                        $UDPClient.Close()
                    } catch {
                        try {
                            $UDPClient.Close()
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }

                        if ($EnableException) { throw }
                    }
                }
            }
        }

        function Test-TcpPort {
            <#
            .SYNOPSIS
                Tests whether a TCP Port is open or not.

            .DESCRIPTION
                Tests whether a TCP Port is open or not.

            .PARAMETER ComputerName
                The name of the computer to scan.

            .PARAMETER Port
                The port(s) to scan.

            .EXAMPLE
                PS C:\> $ports | Test-TcpPort -ComputerName "foo"

                Tests for each port in $ports whether the TCP port is open on computer "foo"
        #>
            [CmdletBinding()]
            param (
                [DbaInstance]$ComputerName,
                [Parameter(ValueFromPipeline)][int[]]$Port
            )

            begin {
                $client = New-Object Net.Sockets.TcpClient
            }
            process {
                foreach ($item in $Port) {
                    try {
                        $client.Connect($ComputerName.ComputerName, $item)
                        if ($client.Connected) {
                            $client.Close()
                            New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $true
                        } else {
                            New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $false
                        }
                    } catch {
                        New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $false
                    }
                }
            }
        }

        function Get-IPrange {
            <#
            .SYNOPSIS
                Get the IP addresses in a range

            .DESCRIPTION
                A detailed description of the Get-IPrange function.

            .PARAMETER Start
                A description of the Start parameter.

            .PARAMETER End
                A description of the End parameter.

            .PARAMETER IPAddress
                A description of the IPAddress parameter.

            .PARAMETER Mask
                A description of the Mask parameter.

            .PARAMETER Cidr
                A description of the Cidr parameter.

            .EXAMPLE
                Get-IPrange -Start 192.168.8.2 -End 192.168.8.20

            .EXAMPLE
                Get-IPrange -IPAddress 192.168.8.2 -Mask 255.255.255.0

            .EXAMPLE
                Get-IPrange -IPAddress 192.168.8.3 -Cidr 24

            .NOTES
                Author: BarryCWT
                Reference: https://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b
        #>

            param
            (
                [string]$Start,
                [string]$End,
                [string]$IPAddress,
                [string]$Mask,
                [int]$Cidr
            )

            function IP-toINT64 {
                param ($ip)

                $octets = $ip.split(".")
                return [int64]([int64]$octets[0] * 16777216 + [int64]$octets[1] * 65536 + [int64]$octets[2] * 256 + [int64]$octets[3])
            }

            function INT64-toIP {
                param ([int64]$int)

                return ([System.Net.IPAddress](([math]::truncate($int / 16777216)).tostring() + "." + ([math]::truncate(($int % 16777216) / 65536)).tostring() + "." + ([math]::truncate(($int % 65536) / 256)).tostring() + "." + ([math]::truncate($int % 256)).tostring()))
            }

            if ($Cidr) {
                $maskaddr = [Net.IPAddress]::Parse((INT64-toIP -int ([convert]::ToInt64(("1" * $Cidr + "0" * (32 - $Cidr)), 2))))
            }
            if ($Mask) {
                $maskaddr = [Net.IPAddress]::Parse($Mask)
            }
            if ($IPAddress) {
                $ipaddr = [Net.IPAddress]::Parse($IPAddress)
                $networkaddr = New-Object net.ipaddress ($maskaddr.address -band $ipaddr.address)
                $broadcastaddr = New-Object net.ipaddress (([system.net.ipaddress]::parse("255.255.255.255").address -bxor $maskaddr.address -bor $networkaddr.address))
                $startaddr = IP-toINT64 -ip $networkaddr.ipaddresstostring
                $endaddr = IP-toINT64 -ip $broadcastaddr.ipaddresstostring
            } else {
                $startaddr = IP-toINT64 -ip $Start
                $endaddr = IP-toINT64 -ip $End
            }

            for ($i = $startaddr; $i -le $endaddr; $i++) {
                INT64-toIP -int $i
            }
        }

        function Resolve-IPRange {
            <#
            .SYNOPSIS
                Returns a number of IPAddresses based on range specified.

            .DESCRIPTION
                Returns a number of IPAddresses based on range specified.
                Warning: A too large range can lead to memory exceptions.

                Scans subnet of active computer if no address is specified.

            .PARAMETER IpAddress
                The address / range / mask / cidr to scan. Example input:
                - 10.1.1.1
                - 10.1.1.1/24
                - 10.1.1.1-10.1.1.254
                - 10.1.1.1/255.255.255.0
        #>
            [CmdletBinding()]
            param (
                [AllowEmptyString()][string]$IpAddress
            )

            #region Scan defined range
            if ($IpAddress) {
                #region Determine processing mode
                $mode = 'Unknown'
                if ($IpAddress -like "*/*") {
                    $parts = $IpAddress.Split("/")

                    $address = $parts[0]
                    if ($parts[1] -match ([dbargx]::IPv4)) {
                        $mask = $parts[1]
                        $mode = 'Mask'
                    } elseif ($parts[1] -as [int]) {
                        $cidr = [int]$parts[1]

                        if (($cidr -lt 8) -or ($cidr -gt 31)) {
                            Stop-Function -Message "$IpAddress does not contain a valid cidr mask"
                            return
                        }

                        $mode = 'CIDR'
                    } else {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                    }
                } elseif ($IpAddress -like "*-*") {
                    $rangeStart = $IpAddress.Split("-")[0]
                    $rangeEnd = $IpAddress.Split("-")[1]

                    if ($rangeStart -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                        return
                    }
                    if ($rangeEnd -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                        return
                    }

                    $mode = 'Range'
                } else {
                    if ($IpAddress -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP address"
                        return
                    }
                    return $IpAddress
                }
                #endregion Determine processing mode

                switch ($mode) {
                    'CIDR' {
                        Get-IPrange -IPAddress $address -Cidr $cidr
                    }
                    'Mask' {
                        Get-IPrange -IPAddress $address -Mask $mask
                    }
                    'Range' {
                        Get-IPrange -Start $rangeStart -End $rangeEnd
                    }
                }
            }
            #endregion Scan defined range

            #region Scan own computer range
            else {
                foreach ($interface in ([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object NetworkInterfaceType -Like '*Ethernet*')) {
                    foreach ($property in ($interface.GetIPProperties().UnicastAddresses | Where-Object { $_.Address.AddressFamily -like "InterNetwork" })) {
                        Get-IPrange -IPAddress $property.Address -Cidr $property.PrefixLength
                    }
                }
            }
            #endregion Scan own computer range
        }
        #endregion Utility Functions

        #region Build parameter Splat for scan
        $paramTestSqlInstance = @{
            ScanType          = $ScanType
            TCPPort           = $TCPPort
            EnableException   = $EnableException
            MinimumConfidence = $MinimumConfidence
        }

        # Only specify when passed by user to avoid credential prompts on PS3/4
        if ($SqlCredential) {
            $paramTestSqlInstance["SqlCredential"] = $SqlCredential
        }
        if ($Credential) {
            $paramTestSqlInstance["Credential"] = $Credential
        }
        if ($DomainController) {
            $paramTestSqlInstance["DomainController"] = $DomainController
        }
        #endregion Build parameter Splat for scan

        # Prepare item processing in a pipeline compliant way
        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Test-SqlInstance', [System.Management.Automation.CommandTypes]::Function)
        $scriptCmd = {
            & $wrappedCmd @paramTestSqlInstance
        }
        $steppablePipeline = $scriptCmd.GetSteppablePipeline()
        $steppablePipeline.Begin($true)
    }

    process {
        if (Test-FunctionInterrupt) { return }
        #region Process items or discover stuff
        switch ($PSCmdlet.ParameterSetName) {
            'Computer' {
                $ComputerName | Invoke-SteppablePipeline -Pipeline $steppablePipeline
            }
            'Discover' {
                #region Discovery: DataSource Enumeration
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::DataSourceEnumeration)) {
                    try {
                        # Discover instances
                        foreach ($instance in ([System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources())) {
                            if ($instance.InstanceName -ne [System.DBNull]::Value) {
                                $steppablePipeline.Process("$($instance.Servername)\$($instance.InstanceName)")
                            } else {
                                $steppablePipeline.Process($instance.Servername)
                            }
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Datasource enumeration failed" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: DataSource Enumeration

                #region Discovery: SPN Search
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::DomainSPN)) {
                    try {
                        Get-DomainSPN -DomainController $DomainController -Credential $Credential -ErrorAction Stop | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    } catch {
                        Write-Message -Level Warning -Message "Failed to execute Service Principal Name discovery" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: SPN Search

                #region Discovery: IP Range
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::IPRange)) {
                    if ($IpAddress) {
                        foreach ($address in $IpAddress) {
                            Resolve-IPRange -IpAddress $address | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                        }
                    } else {
                        Resolve-IPRange | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    }
                }
                #endregion Discovery: IP Range

                #region Discovery: Windows Server Search
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::DomainServer)) {
                    try {
                        Get-DomainServer -DomainController $DomainController -Credential $Credential -ErrorAction Stop | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    } catch {
                        Write-Message -Level Warning -Message "Failed to execute Windows Server discovery" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: Windows Server Search
            }
            "Default" {
                Stop-Function -Message "Please specify DiscoveryType or ScanType. Try Get-Help Find-DbaInstance -Examples for working examples." -EnableException $EnableException
                return
            }
            default {
                Stop-Function -Message "Invalid parameterset, some developer probably had a beer too much. Please file an issue so we can fix this." -EnableException $EnableException
                return
            }
        }
        #endregion Process items or discover stuff
    }

    end {
        if (Test-FunctionInterrupt) {
            return
        }
        $steppablePipeline.End()
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC3r6cnmLlxOfO7
# oVxPGtDVjdVBCKKLH2PGMNfg+AXnrqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBF6/g7b/m9FAsllZWbXN9q0B1k/FxM88UR
# jO7OGcOC2zANBgkqhkiG9w0BAQEFAASCAQB2JOfjV4jKRf3Lfvjc2E9oJ/b/LvCI
# 3gSn4qcT4+BCq2cmIbRmy6qxRZvI+9dtCJRF58ja93hhDdwMRgIabzgjcFs7/xuq
# aXk8tovP6polmmCnMCMju5ZToG/Cpke/GmS7bpM3t4mVbuicmSQ7jV5/aG66GsLb
# k9Etjt3GBHxl0lc9CKru408tII3CjjHjSFrj07kwi66mX1hn0IQqC6GCT12qMXER
# nhMhMxYK2BCi1WQvLgzY0ZsdCJ6li9ks14YoXW84XjnQhnzaBsjGwxbsrI/j4pqC
# oJ6eh5Lh2G/Piu2Gbl8k/6VByTEAy/jXGoOmaVxsy4JnYWT+PmQNs83joYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI0NlowLwYJKoZIhvcNAQkEMSIEIFFjozV1
# Ss6Gc3mno9N1Dkv5jpJrexLpgShw3oAM6PKBMA0GCSqGSIb3DQEBAQUABIICAGwe
# 9PEWXzC14BHQQ7sHelUMWoSSLJXeYx1KBsuccUxqXNNVy+q/+qq9W7DxOIGsLBkT
# kgI1UQOCM0HtRMDsGZ19qoSk7fKwIlY6oVXiWc8sTD7QnuZoEsqMegrrLY3Lo1uR
# hRF0ITug+CCerBbW4Ap0pxPQazUgbDo6sqGnMSf+tZFAZHSAEFsFLMFOWTeKZQN+
# E5nbUx+E7aYC0qoWeY9S80Ekcy0FfWm+1IVEXS8UCQ14zipZeopr6k8784SL0BeK
# 1HiGNxCZyYQJbybwslfNSN40nBgWw1N4pKMCTj0oSm23aWo2VZyFNQsQ6fmRstxJ
# gebCNl7Zmu1X4j59qUqQKJXaK2nexBgOnnzOdEuGRIT0/UX3puzCb9qmEVEd25xl
# c0lv5KkSV6Y/PSOwbvszxcTSOr5ZL0MC+tDqVaJDKwymKhBvigJkAyHExU3JefkZ
# t2HflkqT6CWLUtD4O0h9WmoKmcG3I/SmTe9g4c11r9mmWt3IiyB/SgEf8w7147Oq
# 7Po46W+i3Uvk6H9FtGoam1lp2w5FL6CgQmwmOnmZtb36bz0kFC/0XC++B3Lhim82
# 2eGBqo5DiWL5VpmjPHa0kFxz8ulR0p4xqzsCdOizyOK8Vbxp6sNMM3fd6jvqVhZs
# uaFl/F5agjuskGkD/y+gfrm6ISTlW429lXwZCmF0
# SIG # End signature block
