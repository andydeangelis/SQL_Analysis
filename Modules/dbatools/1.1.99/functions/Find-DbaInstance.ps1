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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUFTzXVrQ6oO0vRzuqNv+yDHla
# MOWgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFGVxYNNFOcz3yxiOvSvL62hLVNq2MA0G
# CSqGSIb3DQEBAQUABIIBALOxN4Bj05mBI7iy0Y+Z3Qq1YKAaiG25SKdOLUsPqzB0
# WdwX+2FRL7ivGrB1Gka7L3QwHVM82+mv4ORJ3ltQPinAgfSxkfr10YQPgaudS8pO
# 6MWXYcj5MKtQURN6/I4x9hO0QwtLG3472LXMzxw9MpFBW4E0ODugPo1DVheZsI8J
# n4JokSItAsc1yb67i3jDOUCaNwL3cvdERndNraMnE1z+Tnc6kvj+/TwyeJIgfYrL
# hTQUEQDwWtUsny7CBDJ9MtFsrVzu5UYZjGfNkimS0ns24i3+y1tXCOfImMI74DZw
# PkW9Kd4/vBIW/GELWKkvQ/zUUDgiDIsxDfgpubPhbp6hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzIxWjAvBgkqhkiG9w0BCQQxIgQggJEea86aaRTPwTN40xDp
# HFjVKP/gx+owBM1DSYwj3GEwDQYJKoZIhvcNAQEBBQAEggIAdg1JgD5IIk+LQaBL
# 4h7Q/FAzgLWmLPWhcu1wzNuF7dRSJmIf7QhWzRkCltXJGDdGCTd7B+oLnq1B1S1a
# FiPa+ANZUFbeXDEm/3BCPZr0lm+8N4lWgNwttD6+GucIn2DN65gpP9wfgKMAk1Ud
# wDy2alzkbkhBRrPZAj/kDxfPieEyZhthg1DHqn9QOV3gZW6RC8Y5Ww5znPBJTuvA
# rBCEtIRrnQtZDSnEYpxUhR5btW1g0Y/1TMoBVxRCqFjlc5zwBlN90YxWilbxIQ0n
# jNCG3EWI9rks0TeMn7nCtMliVJQ2IeA3SaGONF62dBRJDuSvHVuSRmJvqfWZJJxy
# hCPYIXGVJQJtJb9/EM+gkbMf5p+nO6i/OpxRD/5nWYEfVqqkuERai3qMcDOwggCY
# /jOz2euuUbhJxlyCTopRel+5hfZZS9hrUIFbNb5FaFmXrWLbRjF1xf4KuKaCS4LJ
# sA6wsAChvtvynCTZBl9der+Dk0U/dYooJvKIuYVdWCCenLrFmK5TtG/vBEZNT021
# 2rEArAAoO5Xd7544WRcbbMyvZd2SvUnH8+u88Xzz59IQnoxc4F6Ich7IrZcvO+VR
# X/oWmwKwQMr4RK/FipmVa0ObMQJpt6b7n0W+9bR5sosN2xfBNB7YXCdCu89ukN6Q
# 38xmM9JRwkT555JYFG5p5NmiXY4=
# SIG # End signature block
