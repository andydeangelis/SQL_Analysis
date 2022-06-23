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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWOoj/Iawv16xUfE9R6S6p61C
# 0DugghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFEZm81AEAZg7Zy0nAAXqKK1ct/GWMA0G
# CSqGSIb3DQEBAQUABIIBAAVmpnLxgahoQgiIicG6zQybTV/cu2A22+rCDUSFcSMg
# bNqbM5fAqyddQa/slFyTwqmAice1YjdOLdNxYXClXXAacnDLK5CO12FD6qGWgqNB
# 3UE8M/CY9Cyv6pxX8J+QX8WTKRiwsGBtJw/WSuVfr++njbqi9pXh73ielYHX+UjA
# i41ipr3/DFA77F4mVHY8U88rr2YgTFt5FApVDYuokOFdvV6ZXZQUEybSSHRwVFnb
# nPJh5PZ+o8paqPuY+w9PaiPhdISM8rxZWUhoqcY40mHJlwZc2QJdxJGyEGv5M0XD
# j3x+ayegPOOnZD1LyECm2a+wJtURT+ykqjoXmp9SZ6qhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDIyWjAvBgkqhkiG9w0BCQQxIgQgpYLfZGp9kUZGOeqtaya4
# QCip5/rDNYOYNbzM4Hd+/TswDQYJKoZIhvcNAQEBBQAEggIAtkqeQlIN5+VuwH8h
# iUSmzIvh3ZwuFwTPUOOOJazaIDhWg6Xml1sn4g2RPNCM84ibQ3dA82pFzryW7HbX
# HrquW79Yl17o76IT6YcWVXCeUI+0hTmPN3yo7vCfftGsf5WBe9Yd/q+DOgV0xAHk
# f+ladJSskIditIgznQDnmmmJZxIcKAn/Tpev9mPeDqCGzVHSmuxhUtvFgg+KPYCU
# xAq7gFcEzf1twriNcApP8HJoy2VrJsl4+50Hj4qrYFfmBmOvp12Qed5dOjBpYNve
# snpOD3h2JSBqphAHnz407iC+cSXY+eWoA9E3YI4gEq06zSaF6DDjJ56w4scN8Nl4
# imyvmEl7marePXXDjrEofqiGMjUOwmnkgIhn6DfEVGSteVjhPLfxu8Byxsz61ED0
# WipDyHt3OyCHrcsFKhNNnLbCPnPO4HRX2dXuh5NIDw/Mws9rYTTLrK4E/uRsPQpP
# mC4N0edyC1Kbh8Bbmn4DGY3Ab/ne/OYnOlqXhuFgTNSPKSrgm1iqgs82EimtyAfb
# icKxFIXP+iG7DPq4Lvpy4pL2QRCBhbeymINciVmHeQovjh8Uppz2JaCvS8bZpiDm
# 44bqMF7IvB2L0+7d3bPx0fgnxJ4if6AC9ui0XmIOSNZ7OGlYXDzQBAshWVtEsMDT
# Pi+sbohf0bbHs23Ntpv9b22mI2o=
# SIG # End signature block
