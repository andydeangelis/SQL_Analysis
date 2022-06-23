function New-DbaFirewallRule {
    <#
    .SYNOPSIS
        Creates a new inbound firewall rule for a SQL Server instance and adds the rule to the target computer.

    .DESCRIPTION
        Creates a new inbound firewall rule for a SQL Server instance and adds the rule to the target computer.

        This is basically a wrapper around New-NetFirewallRule executed at the target computer.
        So this only works if New-NetFirewallRule works on the target computer.

        Both DisplayName and Name are set to the same value, since DisplayName is required
        but only Name uniquely defines the rule, thus avoiding duplicate rules with different settings.
        The names and the group for all rules are fixed to be able to get them back with Get-DbaFirewallRule.

        The functionality is currently limited. Help to extend the functionality is welcome.

        As long as you can read this note here, there may be breaking changes in future versions.
        So please review your scripts using this command after updating dbatools.

        The firewall rule for the instance itself will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server default instance' or 'SQL Server instance <InstanceName>'
            Name        = 'SQL Server default instance' or 'SQL Server instance <InstanceName>'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '<Port>' (for instances with static port)
            Program     = '<Path ending with MSSQL\Binn\sqlservr.exe>' (for instances with dynamic port)

        The firewall rule for the SQL Server Browser will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server Browser'
            Name        = 'SQL Server Browser'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'UDP'
            LocalPort   = '1434'

        The firewall rule for the dedicated admin connection (DAC) will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server default instance (DAC)' or 'SQL Server instance <InstanceName> (DAC)'
            Name        = 'SQL Server default instance (DAC)' or 'SQL Server instance <InstanceName> (DAC)'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '<Port>' (typically 1434 for a default instance, but will be fetched from ERRORLOG)

        The firewall rule for the DAC will only be created if the DAC is configured for listening remotely.
        Use `Set-DbaSpConfigure -SqlInstance SRV1 -Name RemoteDacConnectionsEnabled -Value 1` to enable remote DAC before running this command.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER Type
        Creates firewall rules for the given type(s).

        Valid values are:
        * Engine - for the SQL Server instance
        * Browser - for the SQL Server Browser
        * DAC - for the dedicated admin connection (DAC)

        If this parameter is not used:
        * The firewall rule for the SQL Server instance will be created.
        * In case the instance is listening on a port other than 1433, also the firewall rule for the SQL Server Browser will be created if not already in place.
        * In case the DAC is configured for listening remotely, also the firewall rule for the DAC will be created.

    .PARAMETER Configuration
        A hashtable with custom configuration parameters that are used when calling New-NetFirewallRule.
        These will override the default settings.
        Parameters Name, DisplayName and Group are not allowed here and will be silently ignored.

        https://docs.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule

    .PARAMETER Force
        If the rule to be created already exists, a warning is displayed.
        If this switch is enabled, the rule will be deleted and created again.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Network, Connection, Firewall
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaFirewallRule

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1, SRV1\TEST

        Automatically configures the needed firewall rules for both the default instance and the instance named TEST on SRV1.

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1, SRV1\TEST -Configuration @{ Profile = 'Domain' }

        Automatically configures the needed firewall rules for both the default instance and the instance named TEST on SRV1,
        but configures the firewall rule for the domain profile only.

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1\TEST -Type Engine -Force -Confirm:$false

        Creates or recreates the firewall rule for the instance TEST on SRV1. Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [ValidateSet('Engine', 'Browser', 'DAC')]
        [string[]]$Type,
        [hashtable]$Configuration,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Configuration) {
            foreach ($notAllowedKey in 'Name', 'DisplayName', 'Group') {
                if ($notAllowedKey -in $Configuration.Keys) {
                    Write-Message -Level Verbose -Message "Key $notAllowedKey is not allowed in Configuration and will be removed."
                    $Configuration.Remove($notAllowedKey)
                }
            }
        }

        $cmdScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2.
            $firewallRuleParameters = $args[0]
            $force = $args[1]

            try {
                if (-not (Get-Command -Name New-NetFirewallRule -ErrorAction SilentlyContinue)) {
                    throw 'The module NetSecurity with the command New-NetFirewallRule is missing on the target computer, so New-DbaFirewallRule is not supported.'
                }
                $successful = $true
                if ($force) {
                    $null = Remove-NetFirewallRule -Name $firewallRuleParameters.Name -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                }
                $cimInstance = New-NetFirewallRule @firewallRuleParameters -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($warn.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $warn = $null
                }
                if ($err.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $err = $null
                }
                [PSCustomObject]@{
                    Successful  = $successful
                    CimInstance = $cimInstance
                    Warning     = $warn
                    Error       = $err
                    Exception   = $null
                }
            } catch {
                [PSCustomObject]@{
                    Successful  = $false
                    CimInstance = $null
                    Warning     = $null
                    Error       = $null
                    Exception   = $_
                }
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            $rules = @( )
            $programNeeded = $false
            $browserNeeded = $false
            if ($PSBoundParameters.Type) {
                $browserOptional = $false
            } else {
                $browserOptional = $true
            }

            # Create rule for instance
            if (-not $PSBoundParameters.Type -or 'Engine' -in $PSBoundParameters.Type) {
                # Apply the defaults
                $rule = @{
                    Type         = 'Engine'
                    InstanceName = $instance.InstanceName
                    Config       = @{
                        Group     = 'SQL Server'
                        Enabled   = 'True'
                        Direction = 'Inbound'
                        Protocol  = 'TCP'
                    }
                }

                # Test for default or named instance
                if ($instance.InstanceName -eq 'MSSQLSERVER') {
                    $rule.Config.DisplayName = 'SQL Server default instance'
                    $rule.Config.Name = 'SQL Server default instance'
                    $rule.SqlInstance = $instance.ComputerName
                } else {
                    $rule.Config.DisplayName = "SQL Server instance $($instance.InstanceName)"
                    $rule.Config.Name = "SQL Server instance $($instance.InstanceName)"
                    $rule.SqlInstance = $instance.ComputerName + '\' + $instance.InstanceName
                    $browserNeeded = $true
                }

                # Get information about IP addresses for LocalPort
                try {
                    $tcpIpAddresses = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -OutputType TcpIpAddresses -EnableException
                } catch {
                    Stop-Function -Message "Failed." -Target $instance -ErrorRecord $_ -Continue
                }

                if ($tcpIpAddresses.Count -gt 1) {
                    # I would have to test this, so I better not support this in the first version.
                    # As LocalPort is [<String[]>], $tcpIpAddresses.TcpPort will probably just work with the current implementation.
                    Stop-Function -Message "SQL Server instance $instance listens on more than one IP addresses. This is currently not supported by this command." -Continue
                }

                if ($tcpIpAddresses.TcpPort -ne '') {
                    $rule.Config.LocalPort = $tcpIpAddresses.TcpPort
                    if ($tcpIpAddresses.TcpPort -ne '1433') {
                        $browserNeeded = $true
                    }
                } else {
                    $programNeeded = $true
                }

                if ($programNeeded) {
                    # Get information about service for Program
                    try {
                        $service = Get-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Credential $Credential -Type Engine -EnableException
                    } catch {
                        Stop-Function -Message "Failed." -Target $instance -ErrorRecord $_ -Continue
                    }
                    $rule.Config.Program = $service.BinaryPath -replace '^"?(.*sqlservr.exe).*$', '$1'
                }

                $rules += $rule
            }

            # Create rule for Browser
            if ((-not $PSBoundParameters.Type -and $browserNeeded) -or 'Browser' -in $PSBoundParameters.Type) {
                # Apply the defaults
                $rule = @{
                    Type         = 'Browser'
                    InstanceName = $null
                    SqlInstance  = $null
                    Config       = @{
                        DisplayName = 'SQL Server Browser'
                        Name        = 'SQL Server Browser'
                        Group       = 'SQL Server'
                        Enabled     = 'True'
                        Direction   = 'Inbound'
                        Protocol    = 'UDP'
                        LocalPort   = '1434'
                    }
                }

                $rules += $rule
            }

            # Create rule for the dedicated admin connection (DAC)
            if (-not $PSBoundParameters.Type -or 'DAC' -in $PSBoundParameters.Type) {
                # As we create firewall rules, we probably don't have access to the instance yet. So we have to get the port of the DAC via Invoke-Command2.
                # Get-DbaStartupParameter also uses Invoke-Command2 to get the location of ERRORLOG.
                # We only scan the current log because this command is typically run shortly after the installation and should include the needed information.
                try {
                    $errorLogPath = Get-DbaStartupParameter -SqlInstance $instance -Credential $Credential -Simple -EnableException | Select-Object -ExpandProperty ErrorLog
                    $dacMessage = Invoke-Command2 -Raw -ComputerName $instance.ComputerName -ArgumentList $errorLogPath -ScriptBlock {
                        Get-Content -Path $args[0] |
                            Select-String -Pattern 'Dedicated admin connection support was established for listening.+' |
                            Select-Object -Last 1 |
                            ForEach-Object { $_.Matches.Value }
                    }
                    Write-Message -Level Debug -Message "Last DAC message in ERRORLOG: '$dacMessage'"
                } catch {
                    Stop-Function -Message "Failed to execute command to get information for DAC on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                }

                if (-not $dacMessage) {
                    Write-Message -Level Warning -Message "No information about the dedicated admin connection (DAC) found in ERRORLOG, cannot create firewall rule for DAC. Use 'Set-DbaSpConfigure -SqlInstance '$instance' -Name RemoteDacConnectionsEnabled -Value 1' to enable remote DAC and try again."
                } elseif ($dacMessage -match 'locally') {
                    Write-Message -Level Verbose -Message "Dedicated admin connection is only listening locally, so no firewall rule is needed."
                } else {
                    $dacPort = $dacMessage -replace '^.* (\d+).$', '$1'
                    Write-Message -Level Verbose -Message "Dedicated admin connection is listening remotely on port $dacPort."

                    # Apply the defaults
                    $rule = @{
                        Type         = 'DAC'
                        InstanceName = $instance.InstanceName
                        Config       = @{
                            Group     = 'SQL Server'
                            Enabled   = 'True'
                            Direction = 'Inbound'
                            Protocol  = 'TCP'
                            LocalPort = $dacPort
                        }
                    }

                    # Test for default or named instance
                    if ($instance.InstanceName -eq 'MSSQLSERVER') {
                        $rule.Config.DisplayName = 'SQL Server default instance (DAC)'
                        $rule.Config.Name = 'SQL Server default instance (DAC)'
                        $rule.SqlInstance = $instance.ComputerName
                    } else {
                        $rule.Config.DisplayName = "SQL Server instance $($instance.InstanceName) (DAC)"
                        $rule.Config.Name = "SQL Server instance $($instance.InstanceName) (DAC)"
                        $rule.SqlInstance = $instance.ComputerName + '\' + $instance.InstanceName
                    }

                    $rules += $rule
                }
            }

            foreach ($rule in $rules) {
                # Apply the given configuration
                if ($Configuration) {
                    foreach ($param in $Configuration.Keys) {
                        $rule.Config.$param = $Configuration.$param
                    }
                }

                # Run the command for the instance
                if ($PSCmdlet.ShouldProcess($instance, "Creating firewall rule for instance $($instance.InstanceName) on $($instance.ComputerName)")) {
                    try {
                        $commandResult = Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $cmdScriptBlock -ArgumentList $rule.Config, $Force
                    } catch {
                        Stop-Function -Message "Failed to execute command on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                    }

                    if ($commandResult.Error.Count -eq 1 -and $commandResult.Error[0] -match 'Cannot create a file when that file already exists') {
                        $status = 'The desired rule already exists. Use -Force to remove and recreate the rule.'
                        $commandResult.Error = $null
                        if ($rule.Type -eq 'Browser' -and $browserOptional) {
                            $commandResult.Successful = $true
                        }
                    } elseif ($commandResult.CimInstance.Status -match 'The rule was parsed successfully from the store') {
                        $status = 'The rule was successfully created.'
                    } else {
                        $status = $commandResult.CimInstance.Status
                    }

                    if ($commandResult.Warning) {
                        Write-Message -Level Verbose -Message "commandResult.Warning: $($commandResult.Warning)."
                        $status += " Warning: $($commandResult.Warning)."
                    }
                    if ($commandResult.Error) {
                        Write-Message -Level Verbose -Message "commandResult.Error: $($commandResult.Error)."
                        $status += " Error: $($commandResult.Error)."
                    }
                    if ($commandResult.Exception) {
                        Write-Message -Level Verbose -Message "commandResult.Exception: $($commandResult.Exception)."
                        $status += " Exception: $($commandResult.Exception)."
                    }

                    # Output information
                    [PSCustomObject]@{
                        ComputerName = $instance.ComputerName
                        InstanceName = $rule.InstanceName
                        SqlInstance  = $rule.SqlInstance
                        DisplayName  = $rule.Config.DisplayName
                        Name         = $rule.Config.Name
                        Type         = $rule.Type
                        Protocol     = $rule.Config.Protocol
                        LocalPort    = $rule.Config.LocalPort
                        Program      = $rule.Config.Program
                        RuleConfig   = $rule.Config
                        Successful   = $commandResult.Successful
                        Status       = $status
                        Details      = $commandResult
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DisplayName, Type, Successful, Status, Protocol, LocalPort, Program
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBwIFWhNjKEAHQx
# ljFKgiuj0ZhgwwdDMU2gsDLDU/pmmqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBHsAHVt6OHHk/Mszoq9aIrNp2xL6kuzMVT
# /bRMwFwASjANBgkqhkiG9w0BAQEFAASCAQBFsg4F4xIp2C+c86cSYSyDd7/Xxhj8
# 9DB0wl1DMshmhw6QOaeW1GsUeSl8KZnXvHD/19mk+fpnWspErfYJXaV7KdHTIPiH
# m+bPn0cdOC+JWVegTtvO5JAr5EezRZvmbaMNHw/fN+LaGV4GL84NQty56iPjyjxK
# Z+0WadrK51rB/OLrSeOUT8AwTWnQrgtvB1dhW2fYIJvDVzDAsGYXtVhXY7v8qaok
# 7uKKmK0mlhmUdolL5+/2HS4OYA9uSyXgo1+QMfj0ehwHdciJkFAj42tPY4thLIV7
# 0uiyf6oEUnW6q5U/Wf1J0bWEEmRP8+y4DF9LjW2Bi0RTzI4n+dv6iTu2oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMzN1owLwYJKoZIhvcNAQkEMSIEIOQCaf26
# oRdEFwqgiRWzxIHfNbFToY0PD2Ia3cQZZzBXMA0GCSqGSIb3DQEBAQUABIICAJYk
# IhVEoPopuNgBV7ZmBL5CmZnyHIJ7ZjZT7guu8cL7DlAP76cyPlN/cieOJeX93cmZ
# XODApRGZeeS3RjaWKUn3D0BWHAYGuEhx5/asU1fYZgtCyp6NNfLM8Yg5jmeNCiJ2
# Gu+NM/hl5QTibS3oWJvxKTQwW3tihrop8t4ZcXf/umW+ZteeNcKjR4OEPE0zExTj
# OFrQrfTJvjPcbCyQ+DOkjASKK8Epao37IGIvyBT7OJhh1ZZz5IyvZNZcHCla4tvV
# GnodeZ7hM1HYKQ7XbUA8qRslHm80aRgc3i5iH7to5Jj01SlaP4X2b59M6eKFt+MW
# yfkjU7WjqSxVDPVdgSizbkaIe8xn+ypMKGE3VIWYy4iQ4x/XYvcTCJp4SSG4mAe1
# L/FcqtZDnM5ZWLv8qgXzE7lLDaK2eGLXopcS53vXdNQApM3SRa+WEVETTH+wVY9n
# Bmw3YRDQenJQ7/ET/eEMy7fUkRVqONkw6caeRpO08jkP/eu9Uj2gQ/3lDePyy3vS
# Oc/GdWDnczn8LfBHwPUoKtRxuicNLpL7MlE7U7h9pT/CWWh4q9PonU1ATHJJr/V8
# 6Pu4bHLbue7WZ4tc2SBwHc/iksL/cE85lna5D7CSvy29USH9R6WiaaaFM6TOGt8x
# Qrjm9LPkl8fyAcE46wvt9H8gGeSj5qorUphCEiL6
# SIG # End signature block
