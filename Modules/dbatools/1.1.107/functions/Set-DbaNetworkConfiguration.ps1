function Set-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Sets the network configuration of a SQL Server instance.

    .DESCRIPTION
        Sets the network configuration of a SQL Server instance.

        Parameters are available for typical tasks like enabling or disabling a protocol or switching between dynamic and static ports.
        The object returned by Get-DbaNetworkConfiguration can be used to adjust settings of the properties
        and then passed to this command via pipeline or -InputObject parameter.

        A change to the network configuration with SQL Server requires a restart to take effect,
        support for this can be done via the RestartService parameter.

        Remote SQL WMI is used by default, with PS Remoting used as a fallback.

        For a detailed explanation of the different properties see the documentation at:
        https://docs.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-network-configuration

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER EnableProtocol
        Enables one of the following network protocols: SharedMemory, NamedPipes, TcpIp.

    .PARAMETER DisableProtocol
        Disables one of the following network protocols: SharedMemory, NamedPipes, TcpIp.

    .PARAMETER DynamicPortForIPAll
        Configures the instance to listen on a dynamic port for all IP addresses.
        Will enable the TCP/IP protocol if needed.
        Will set TcpIpProperties.ListenAll to $true if needed.
        Will reset the last used dynamic port if already set.

    .PARAMETER StaticPortForIPAll
        Configures the instance to listen on one or more static ports for all IP addresses.
        Will enable the TCP/IP protocol if needed.
        Will set TcpIpProperties.ListenAll to $true if needed.

    .PARAMETER IpAddress
        Configures the instance to listen on specific IP addresses only. Listening on all other IP addresses will be disabled.
        Takes an array of string with either the IP address (for listening on a dynamic port) or IP address and port seperated by ":".
        IPv6 addresses must be enclosed in square brackets, e.g. [2001:db8:4006:812::200e] or [2001:db8:4006:812::200e]:1433 to be able to identify the port.

    .PARAMETER RestartService
        Every change to the network configuration needs a service restart to take effect.
        This switch will force a restart of the service if the network configuration has changed.

    .PARAMETER InputObject
        The output object from Get-DbaNetworkConfiguration.
        Get-DbaNetworkConfiguration has to be run with -OutputType Full (default) to get the complete object.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Network, Connection, SQLWMI
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaNetworkConfiguration

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016 -EnableProtocol SharedMemory -RestartService

        Ensures that the shared memory network protocol for the default instance on sql2016 is enabled.
        Restarts the service if needed.

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016\test -StaticPortForIPAll 14331, 14332 -RestartService

        Ensures that the TCP/IP network protocol is enabled and configured to use the ports 14331 and 14332 for all IP addresses.
        Restarts the service if needed.

    .EXAMPLE
        PS C:\> $netConf = Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a
        PS C:\> $netConf.TcpIpProperties.KeepAlive = 60000
        PS C:\> $netConf | Set-DbaNetworkConfiguration -RestartService -Confirm:$false

        Changes the value of the KeepAlive property for the default instance on sqlserver2014a and restarts the service.
        Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016\test -IpAddress 192.168.3.41:1433 -RestartService

        Ensures that the TCP/IP network protocol is enabled and configured to only listen on port 1433 of IP address 192.168.3.41.
        Restarts the service if needed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High", DefaultParameterSetName = 'NonPipeline')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('SharedMemory', 'NamedPipes', 'TcpIp')]
        [string]$EnableProtocol,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('SharedMemory', 'NamedPipes', 'TcpIp')]
        [string]$DisableProtocol,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [switch]$DynamicPortForIPAll,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [int[]]$StaticPortForIPAll,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$IpAddress,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$RestartService,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [object[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $wmiScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2 on the target machine.
            # We take on object as the first parameter which has to include the instance name and the target network configuration.
            $targetConf = $args[0]
            $changes = @()
            $verbose = @()
            $exception = $null

            try {
                $verbose += "Starting initialization of WMI object"

                # As we go remote, ensure the assembly is loaded
                [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
                $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
                $result = $wmi.Initialize()

                $verbose += "Initialization of WMI object finished with $result"

                # If WMI object is empty, there are no client protocols - so we test for that to see if initialization was successful
                $verbose += "Found $($wmi.ServerInstances.Count) instances and $($wmi.ClientProtocols.Count) client protocols inside of WMI object"

                $verbose += "Getting server protocols for $($targetConf.InstanceName)"
                $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $targetConf.InstanceName } ).ServerProtocols

                $verbose += 'Getting server protocol shared memory'
                $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
                if ($null -eq $targetConf.SharedMemoryEnabled) {
                    $verbose += 'SharedMemoryEnabled not in target object'
                } elseif ($wmiSpSm.IsEnabled -ne $targetConf.SharedMemoryEnabled) {
                    $wmiSpSm.IsEnabled = $targetConf.SharedMemoryEnabled
                    $wmiSpSm.Alter()
                    $changes += "Changed SharedMemoryEnabled to $($targetConf.SharedMemoryEnabled)"
                }

                $verbose += 'Getting server protocol named pipes'
                $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
                if ($null -eq $targetConf.NamedPipesEnabled) {
                    $verbose += 'NamedPipesEnabled not in target object'
                } elseif ($wmiSpNp.IsEnabled -ne $targetConf.NamedPipesEnabled) {
                    $wmiSpNp.IsEnabled = $targetConf.NamedPipesEnabled
                    $wmiSpNp.Alter()
                    $changes += "Changed NamedPipesEnabled to $($targetConf.NamedPipesEnabled)"
                }

                $verbose += 'Getting server protocol TCP/IP'
                $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }
                if ($null -eq $targetConf.TcpIpEnabled) {
                    $verbose += 'TcpIpEnabled not in target object'
                } elseif ($wmiSpTcp.IsEnabled -ne $targetConf.TcpIpEnabled) {
                    $wmiSpTcp.IsEnabled = $targetConf.TcpIpEnabled
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpEnabled to $($targetConf.TcpIpEnabled)"
                }

                $verbose += 'Getting properties for server protocol TCP/IP'
                $wmiSpTcpEnabled = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' }
                if ($null -eq $targetConf.TcpIpProperties.Enabled) {
                    $verbose += 'TcpIpProperties.Enabled not in target object'
                } elseif ($wmiSpTcpEnabled.Value -ne $targetConf.TcpIpProperties.Enabled) {
                    $wmiSpTcpEnabled.Value = $targetConf.TcpIpProperties.Enabled
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.Enabled to $($targetConf.TcpIpProperties.Enabled)"
                }

                $wmiSpTcpKeepAlive = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' }
                if ($null -eq $targetConf.TcpIpProperties.KeepAlive) {
                    $verbose += 'TcpIpProperties.KeepAlive not in target object'
                } elseif ($wmiSpTcpKeepAlive.Value -ne $targetConf.TcpIpProperties.KeepAlive) {
                    $wmiSpTcpKeepAlive.Value = $targetConf.TcpIpProperties.KeepAlive
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.KeepAlive to $($targetConf.TcpIpProperties.KeepAlive)"
                }

                $wmiSpTcpListenOnAllIPs = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' }
                if ($null -eq $targetConf.TcpIpProperties.ListenAll) {
                    $verbose += 'TcpIpProperties.ListenAll not in target object'
                } elseif ($wmiSpTcpListenOnAllIPs.Value -ne $targetConf.TcpIpProperties.ListenAll) {
                    $wmiSpTcpListenOnAllIPs.Value = $targetConf.TcpIpProperties.ListenAll
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.ListenAll to $($targetConf.TcpIpProperties.ListenAll)"
                }

                $verbose += 'Getting properties for IPn'
                $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
                foreach ($ip in $wmiIPn) {
                    $ipTarget = $targetConf.TcpIpAddresses | Where-Object { $_.Name -eq $ip.Name }

                    $ipActive = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'Active' }
                    if ($null -eq $ipTarget.Active) {
                        $verbose += 'Active not in target IP address object'
                    } elseif ($ipActive.Value -ne $ipTarget.Active) {
                        $ipActive.Value = $ipTarget.Active
                        $wmiSpTcp.Alter()
                        $changes += "Changed Active for $($ip.Name) to $($ipTarget.Active)"
                    }

                    $ipEnabled = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'Enabled' }
                    if ($null -eq $ipTarget.Enabled) {
                        $verbose += 'Enabled not in target IP address object'
                    } elseif ($ipEnabled.Value -ne $ipTarget.Enabled) {
                        $ipEnabled.Value = $ipTarget.Enabled
                        $wmiSpTcp.Alter()
                        $changes += "Changed Enabled for $($ip.Name) to $($ipTarget.Enabled)"
                    }

                    $ipIpAddress = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'IpAddress' }
                    if ($null -eq $ipTarget.IpAddress) {
                        $verbose += 'IpAddress not in target IP address object'
                    } elseif ($ipIpAddress.Value -ne $ipTarget.IpAddress) {
                        $ipIpAddress.Value = $ipTarget.IpAddress
                        $wmiSpTcp.Alter()
                        $changes += "Changed IpAddress for $($ip.Name) to $($ipTarget.IpAddress)"
                    }

                    $ipTcpDynamicPorts = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
                    if ($null -eq $ipTarget.TcpDynamicPorts) {
                        $verbose += 'TcpDynamicPorts not in target IP address object'
                    } elseif ($ipTcpDynamicPorts.Value -ne $ipTarget.TcpDynamicPorts) {
                        $ipTcpDynamicPorts.Value = $ipTarget.TcpDynamicPorts
                        $wmiSpTcp.Alter()
                        $changes += "Changed TcpDynamicPorts for $($ip.Name) to $($ipTarget.TcpDynamicPorts)"
                    }

                    $ipTcpPort = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                    if ($null -eq $ipTarget.TcpPort) {
                        $verbose += 'TcpPort not in target IP address object'
                    } elseif ($ipTcpPort.Value -ne $ipTarget.TcpPort) {
                        $ipTcpPort.Value = $ipTarget.TcpPort
                        $wmiSpTcp.Alter()
                        $changes += "Changed TcpPort for $($ip.Name) to $($ipTarget.TcpPort)"
                    }
                }

                $verbose += 'Getting properties for IPAll'
                $wmiIPAll = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -eq 'IPAll' }
                $ipTarget = $targetConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }

                $ipTcpDynamicPorts = $wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
                if ($null -eq $ipTarget.TcpDynamicPorts) {
                    $verbose += 'TcpDynamicPorts not in target IP address object'
                } elseif ($ipTcpDynamicPorts.Value -ne $ipTarget.TcpDynamicPorts) {
                    $ipTcpDynamicPorts.Value = $ipTarget.TcpDynamicPorts
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpDynamicPorts for $($wmiIPAll.Name) to $($ipTarget.TcpDynamicPorts)"
                }

                $ipTcpPort = $wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                if ($null -eq $ipTarget.TcpPort) {
                    $verbose += 'TcpPort not in target IP address object'
                } elseif ($ipTcpPort.Value -ne $ipTarget.TcpPort) {
                    $ipTcpPort.Value = $ipTarget.TcpPort
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpPort for $($wmiIPAll.Name) to $($ipTarget.TcpPort)"
                }
            } catch {
                $exception = $_
            }

            [PSCustomObject]@{
                Changes   = $changes
                Verbose   = $verbose
                Exception = $exception
            }
        }
    }

    process {
        if ($SqlInstance -and (Test-Bound -Not -ParameterName EnableProtocol, DisableProtocol, DynamicPortForIPAll, StaticPortForIPAll, IpAddress)) {
            Stop-Function -Message "You must choose an action if SqlInstance is used."
            return
        }

        if ($SqlInstance -and (Test-Bound -ParameterName EnableProtocol, DisableProtocol, DynamicPortForIPAll, StaticPortForIPAll, IpAddress -Not -Max 1)) {
            Stop-Function -Message "Only one action is allowed at a time."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Get network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)."
                $netConf = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
            }

            if ($EnableProtocol) {
                if ($netConf."${EnableProtocol}Enabled") {
                    Write-Message -Level Verbose -Message "Protocol $EnableProtocol is already enabled on $instance."
                } else {
                    Write-Message -Level Verbose -Message "Will enable protocol $EnableProtocol on $instance."
                    $netConf."${EnableProtocol}Enabled" = $true
                    if ($EnableProtocol -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $true
                    }
                }
            }

            if ($DisableProtocol) {
                if ($netConf."${DisableProtocol}Enabled") {
                    Write-Message -Level Verbose -Message "Will disable protocol $EnableProtocol on $instance."
                    $netConf."${DisableProtocol}Enabled" = $false
                    if ($DisableProtocol -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $false
                    }
                } else {
                    Write-Message -Level Verbose -Message "Protocol $EnableProtocol is already disabled on $instance."
                }
            }

            if ($DynamicPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '0' on $instance."
                $ipAll.TcpDynamicPorts = '0'
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '' on $instance."
                $ipAll.TcpPort = ''
            }

            if ($StaticPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '' on $instance."
                $ipAll.TcpDynamicPorts = ''
                $port = $StaticPortForIPAll -join ','
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '$port' on $instance."
                $ipAll.TcpPort = $port
            }

            if ($IpAddress) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if ($netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to False on $instance."
                    $netConf.TcpIpProperties.ListenAll = $false
                }
                foreach ($ip in ($netConf.TcpIpAddresses | Where-Object { $_.Name -ne 'IPAll' })) {
                    if ($ip.IpAddress -match ':') {
                        # IPv6: Remove interface id
                        $address = $ip.IpAddress -replace '^(.*)%.*$', '$1'
                    } else {
                        # IPv4: Do nothing special
                        $address = $ip.IpAddress
                    }
                    # Is the current IP one of those to be configured?
                    $isTarget = $false
                    foreach ($listenIP in $IpAddress) {
                        if ($listenIP -match '^\[(.+)\]:?(\d*)$') {
                            # IPv6
                            $listenAddress = $Matches.1
                            $listenPort = $Matches.2
                        } elseif ($listenIP -match '^([^:]+):?(\d*)$') {
                            # IPv4
                            $listenAddress = $Matches.1
                            $listenPort = $Matches.2
                        } else {
                            Write-Message -Level Verbose -Message "$listenIP is not a valid IP address. Skipping."
                            continue
                        }
                        if ($listenAddress -eq $address) {
                            $isTarget = $true
                            break
                        }
                    }
                    if ($isTarget) {
                        if (-not $ip.Enabled) {
                            Write-Message -Level Verbose -Message "Will set property Enabled of IP address $($ip.IpAddress) to True on $instance."
                            $ip.Enabled = $true
                        }
                        if ($listenPort) {
                            # configure for static port
                            if ($ip.TcpDynamicPorts -ne '') {
                                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IP address $($ip.IpAddress) to '' on $instance."
                                $ip.TcpDynamicPorts = ''
                            }
                            if ($ip.TcpPort -ne $listenPort) {
                                Write-Message -Level Verbose -Message "Will set property TcpPort of IP address $($ip.IpAddress) to '$listenPort' on $instance."
                                $ip.TcpPort = $listenPort
                            }
                        } else {
                            # configure for dynamic port
                            if ($ip.TcpDynamicPorts -ne '0') {
                                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IP address $($ip.IpAddress) to '0' on $instance."
                                $ip.TcpDynamicPorts = '0'
                            }
                            if ($ip.TcpPort -ne '') {
                                Write-Message -Level Verbose -Message "Will set property TcpPort of IP address $($ip.IpAddress) to '' on $instance."
                                $ip.TcpPort = ''
                            }
                        }
                    } else {
                        if ($ip.Enabled) {
                            Write-Message -Level Verbose -Message "Will set property Enabled of IP address $($ip.IpAddress) to False on $instance."
                            $ip.Enabled = $false
                        }
                    }
                }
            }

            $InputObject += $netConf
        }

        foreach ($netConf in $InputObject) {
            try {
                $output = [PSCustomObject]@{
                    ComputerName  = $netConf.ComputerName
                    InstanceName  = $netConf.InstanceName
                    SqlInstance   = $netConf.SqlInstance
                    Changes       = @()
                    RestartNeeded = $false
                    Restarted     = $false
                }

                if ($Pscmdlet.ShouldProcess("Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                    $computerName = Resolve-DbaComputerName -ComputerName $netConf.ComputerName -Credential $Credential
                    $null = Test-ElevationRequirement -ComputerName $computerName -EnableException $true
                    $result = Invoke-Command2 -ScriptBlock $wmiScriptBlock -ArgumentList $netConf -ComputerName $computerName -Credential $Credential -ErrorAction Stop
                    foreach ($verbose in $result.Verbose) {
                        Write-Message -Level Verbose -Message $verbose
                    }
                    $output.Changes = $result.Changes
                    if ($result.Exception) {
                        # The new code pattern for WMI calls is used where all exceptions are catched and return as part of an object.
                        $output.Exception = $result.Exception
                        Write-Message -Level Verbose -Message "Execution against $computerName failed with: $($result.Exception)"
                        Stop-Function -Message "Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName) failed with: $($result.Exception)" -Target $netConf.ComputerName -ErrorRecord $result.Exception -Continue
                    }
                }

                if ($result.Changes.Count -gt 0) {
                    $output.RestartNeeded = $true
                    if ($RestartService) {
                        if ($Pscmdlet.ShouldProcess("Restarting service for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                            try {
                                $null = Restart-DbaService -ComputerName $netConf.ComputerName -InstanceName $netConf.InstanceName -Credential $Credential -Type Engine -Force -EnableException -Confirm:$false
                                $output.Restarted = $true
                            } catch {
                                Write-Message -Level Warning -Message "A restart of the service for instance $($netConf.InstanceName) on $($netConf.ComputerName) failed ($_). Restart of instance is necessary for the new settings to take effect."
                            }
                        }
                    } else {
                        Write-Message -Level Warning -Message "A restart of the service for instance $($netConf.InstanceName) on $($netConf.ComputerName) is needed for the changes to take effect."
                    }
                }

                $output

            } catch {
                Stop-Function -Message "Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName) not possible." -Target $netConf.ComputerName -ErrorRecord $_ -Continue
            }
        }
    }
}

# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBE90WrQT3R4Ihv
# ZnunWLN+pXMybLJNj5PXm20NSaBH2aCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCB+LowwNkak/yoPYsqdgKtN1O1IzFa1Jmdt
# g1XRcICGLDANBgkqhkiG9w0BAQEFAASCAQAzZKHmt3Lu5jcvl4BsLFXR9qYuSG8N
# lVRQkrjPdno8uwsCJJTH6rDT1LP1LxP1Q5BYSl6pEohYW+bm5bWrQS9JRBAtPtTg
# z+V00YAoqjAe+6Zsf86GJphRYNReABHBWW+Ug5KibK9sXX8TFxox8c5Jgvxk0rdO
# X2AEawCs1OD+g7HBBrcyfkXXS3t/sfghaWld9brOlL0FbKlu+uV6L3CNxnNp1wS0
# +kz9Ooz5phVgzelWLOaMcbuNJRiXBU50kSVBbM7zs6lI6RKuIhLFYBeWqgjvlvSt
# OZRTSYkrDkpIYGbB98/80tFgWoxA5KtXBpbR1W9vyUK6h/D7SL2lwshsoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDM1OVowLwYJKoZIhvcNAQkEMSIEIGp3g6xD
# I4HlVSLDNDU3nHSZ/3uOKUSBlNuQMYOXcVMVMA0GCSqGSIb3DQEBAQUABIICAATd
# EtHsApDCTF6dBaP1CDWktDHYc1a+oghHkaiyy3ce34g5KqMI/jSiyItjE61G34Ao
# g9YYGqHJdkYg+sCNyTQKakOV273999tp42lAuHAzYqpZ01pokJoBp8BH6PDUye9v
# L2xVzoriwTxbF224+0E3Pn2Vo/lBDfAauAt8aBCpKpqvfg3gp8yQH7zTaQ3NbuX+
# kw19IAcYvmmfolCvwQiM5mCbkQvzWmIr1cy7OzwQeUTZr/2Ikn7iq0HL5K8J/DCU
# UUC3xR9zvfdCudAr4EVl3yylZMrs9VYsVCzGIGumKozfK2thot6zwgQ7hNJPycMM
# LxKZpjEbMPpPCu600FAIdG8YxIfoQuzjxCTcMXz/LfH2t3rTXCa9J9xpd7RXT68i
# IdlGGaMpe4MZmHHAJHRDuQ2YLIHJEGhOPeKvL5dHa3LLhTblSUpTMhmNBpjAe5mf
# mmRM687sKpUTyRAkhtu4UsdNmPBcWRTEX9fK/oXuklk3KRK5sd327BkH98e3udZf
# +7oX+N7yaiEesuKi4+iFyhqSp1vdWLhzIni44IqX5obm6znFInW4qZujEKpV7jGZ
# kfilK8cux8PCWzEr0J2IyfwOdLD9st6ZKUdhk4eE1sxImH2UxdL6T0VsD+ftYEsO
# 3Yz93GNk5/jgUDFXBxUWkgT40gbHM5HzQ3BhzcSK
# SIG # End signature block
