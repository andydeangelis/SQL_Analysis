function Reset-DbaAdmin {
    <#
    .SYNOPSIS
        This function allows administrators to regain access to SQL Servers in the event that passwords or access was lost.

        Supports SQL Server 2005 and above. Windows administrator access is required.

    .DESCRIPTION
        This function allows administrators to regain access to local or remote SQL Servers by either resetting the sa password, adding the sysadmin role to existing login, or adding a new login (SQL or Windows) and granting it sysadmin privileges.

        This is accomplished by stopping the SQL services or SQL Clustered Resource Group, then restarting SQL via the command-line using the /mReset-DbaAdmin parameter which starts the server in Single-User mode and only allows this script to connect.

        Once the service is restarted, the following tasks are performed:
        - Login is added if it doesn't exist
        - If login is a Windows User, an attempt is made to ensure it exists
        - If login is a SQL Login, password policy will be set to OFF when creating the login, and SQL Server authentication will be set to Mixed Mode.
        - Login will be enabled and unlocked
        - Login will be added to sysadmin role

        If failures occur at any point, a best attempt is made to restart the SQL Server.

        In order to make this script as portable as possible, Microsoft.Data.SqlClient and Get-WmiObject are used (as opposed to requiring the Failover Cluster Admin tools or SMO).

        If using this function against a remote SQL Server, ensure WinRM is configured and accessible. If this is not possible, run the script locally.

        Tested on Windows XP, 7, 8.1, Server 2012 and Windows Server Technical Preview 2.
        Tested on SQL Server 2005 SP4 through 2016 CTP2.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server must be 2005 and above, and can be a clustered or stand-alone instance.

    .PARAMETER SqlCredential
        Instead of using Login and SecurePassword, you can just pass in a credential object.

    .PARAMETER Login
        By default, the Login parameter is "sa" but any other SQL or Windows account can be specified. If a login does not currently exist, it will be added.

        When adding a Windows login to remote servers, ensure the SQL Server can add the login (ie, don't add WORKSTATION\Admin to remoteserver\instance. Domain users and Groups are valid input.

    .PARAMETER SecurePassword
        By default, if a SQL Login is detected, you will be prompted for a password. Use this to securely bypass the prompt.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Login(s) will be dropped and recreated on Destination. Logins that own Agent jobs cannot be dropped at this time.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WSMan, Instance, Utility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: Admin access to server (not SQL Services),
        Remoting must be enabled and accessible if $instance is not local

    .LINK
        https://dbatools.io/Reset-DbaAdmin

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlcluster -SqlCredential sqladmin

        Prompts for password, then resets the "sqladmin" account password on sqlcluster.

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlserver\sqlexpress -Login ad\administrator -Confirm:$false

        Adds the domain account "ad\administrator" as a sysadmin to the SQL instance.

        If the account already exists, it will be added to the sysadmin role.

        Does not prompt for a password since it is not a SQL login. Does not prompt for confirmation since -Confirm is set to $false.

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlserver\sqlexpress -Login sqladmin -Force

        Skips restart confirmation, prompts for password, then adds a SQL Login "sqladmin" with sysadmin privileges.
        If the account already exists, it will be added to the sysadmin role and the password will be reset.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWMICmdlet", "", Justification = "Using Get-WmiObject for client backwards compatibilty")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Login = "sa",
        [SecureString]$SecurePassword,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        #region Utility functions
        function ConvertTo-PlainText {
            <#
                .SYNOPSIS
                Internal function.
            #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [Security.SecureString]$Password
            )
            $marshal = [Runtime.InteropServices.Marshal]
            $plaintext = $marshal::PtrToStringAuto($marshal::SecureStringToBSTR($Password))
            return $plaintext
        }

        function Invoke-ResetSqlCmd {
            <#
                .SYNOPSIS
                Internal function. Executes a SQL statement against specified computer, and uses "Reset-DbaAdmin" as the Application Name.
            #>
            [OutputType([System.Boolean])]
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [Alias("ServerInstance", "SqlServer")]
                [DbaInstanceParameter]$instance,
                [string]$sql,
                [switch]$EnableException
            )
            try {
                $connstring = "Data Source=$instance;Integrated Security=True;TrustServerCertificate=true;Connect Timeout=20;Application Name=Reset-DbaAdmin"
                $conn = New-Object Microsoft.Data.SqlClient.SqlConnection $connstring
                $conn.Open()
                $cmd = New-Object Microsoft.Data.sqlclient.sqlcommand($null, $conn)
                $cmd.CommandText = $sql
                $null = $cmd.ExecuteNonQuery()
                $true
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -EnableException $EnableException
                $false
            } finally {
                $cmd.Dispose()
                $conn.Close()
                $conn.Dispose()
            }
        }
        #endregion Utility functions
        if ($Force) { $ConfirmPreference = 'none' }

        if ($SqlCredential) {
            $Login = $SqlCredential.UserName
            $SecurePassword = $SqlCredential.Password
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $stepcounter = 0
            $baseaddress = $instance.ComputerName
            # Get hostname

            if ($instance.IsLocalHost) {
                $ipaddr = "."
                $hostName = $env:COMPUTERNAME
                $baseaddress = $env:COMPUTERNAME
            } else {
                $resolved = Resolve-DbaNetworkName -ComputerName $baseaddress
                $ipaddr = $resolved.IPAddress
                $hostName = $resolved.FullComputerName
            }

            # Setup remote session if server is not local
            if (-not $instance.IsLocalHost) {
                try {
                    $connectionParams = @{
                        ComputerName = $hostName
                        ErrorAction  = "Stop"
                        UseSSL       = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false)
                    }
                    $session = New-PSSession @connectionParams
                } catch {
                    Stop-Function -Continue -ErrorRecord $_ -Message "Can't access $hostName using PSSession. Check your firewall settings and ensure Remoting is enabled or run the script locally."
                }
            }

            Write-Message -Level Verbose -Message "Detecting login type."
            # Is login a Windows login? If so, does it exist?
            if ($Login -match "\\") {
                Write-Message -Level Verbose -Message "Windows login detected. Checking to ensure account is valid."
                $windowslogin = $true
                try {
                    if ($hostName -eq $env:COMPUTERNAME) {
                        $account = New-Object System.Security.Principal.NTAccount($Login)
                        #Variable $sid marked as unused by PSScriptAnalyzer replace with $null to catch output
                        $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
                    } else {
                        Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $Login -ScriptBlock {
                            $account = New-Object System.Security.Principal.NTAccount($args)
                            #Variable $sid marked as unused by PSScriptAnalyzer replace with $null to catch output
                            $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
                        }
                    }
                } catch {
                    Write-Message -Level Warning -Message "Cannot resolve Windows User or Group $Login. Trying anyway."
                }
            }

            # If it's not a Windows login, it's a SQL login, so it needs a password.
            if (-not $windowslogin -and -not $SecurePassword) {
                Write-Message -Level Verbose -Message "SQL login detected"
                do {
                    $password = Read-Host -AsSecureString "Please enter a new password for $Login"
                } while ($password.Length -eq 0)
            }

            If ($SecurePassword) {
                $password = $SecurePassword
            }

            # Get instance and service display name, then get services
            $instanceName = $instance.InstanceName
            if (-not $instanceName) {
                $instanceName = "MSSQLSERVER"
            }
            $displayName = "SQL Server ($instanceName)"

            try {
                if ($hostName -eq $env:COMPUTERNAME) {
                    $instanceServices = Get-Service -ErrorAction Stop | Where-Object { $_.DisplayName -like "*($instanceName)*" -and $_.Status -eq "Running" }
                    $sqlservice = Get-Service -ErrorAction Stop | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                } else {
                    $instanceServices = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object { $_.DisplayName -like "*($instanceName)*" -and $_.Status -eq "Running" }
                    $sqlservice = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                }
            } catch {
                Stop-Function -Message "Cannot connect to WMI on $hostName or SQL Service does not exist. Check permissions, firewall and SQL Server running status." -ErrorRecord $_ -Target $instance
                return
            }

            if (-not $instanceServices) {
                Stop-Function -Message "Couldn't find SQL Server instance. Check the spelling, ensure the service is running and try again." -Target $instance
                return
            }

            Write-Message -Level Verbose -Message "Attempting to stop SQL Services."

            # Check to see if service is clustered. Clusters don't support -m (since the cluster service
            # itself connects immediately) or -f, so they are handled differently.
            try {
                $checkcluster = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object { $_.Name -eq "ClusSvc" -and $_.Status -eq "Running" }
            } catch {
                Stop-Function -Message "Can't check services." -Target $instance -ErrorRecord $_
                return
            }

            if ($null -ne $checkcluster) {
                $clusterResource = Get-DbaCmObject -ClassName "MSCluster_Resource" -Namespace "root\mscluster" -ComputerName $hostName | Where-Object { $_.Name.StartsWith("SQL Server") -and $_.OwnerGroup -eq "SQL Server ($instanceName)" }
            }

            if ($pscmdlet.ShouldProcess($baseaddress, "Stop $instance to restart in single-user mode")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Stopping $instance to restart in single-user mode"
                # Take SQL Server offline so that it can be started in single-user mode
                if ($clusterResource.count -gt 0) {
                    $isClustered = $true
                    try {
                        $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.TakeOffline(60) }
                    } catch {
                        $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_ -Target $instance
                        return
                    }
                } else {
                    try {
                        Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                        Write-Message -Level Verbose -Message "Successfully stopped SQL service."
                    } catch {
                        Start-Service -InputObject $instanceServices -ErrorAction Stop
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL service and quit." -ErrorRecord $_ -Target $instance
                        return
                    }
                }
            }

            # /mReset-DbaAdmin Starts an instance of SQL Server in single-user mode and only allows this script to connect.
            if ($pscmdlet.ShouldProcess($baseaddress, "Starting $instance in single-user mode")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting $instance in single-user mode"
                try {
                    if ($instance.IsLocalHost) {
                        $netstart = net start ""$displayName"" /mReset-DbaAdmin 2>&1
                        if ("$netstart" -notmatch "success") {
                            Stop-Function -Message "Restart failure" -Continue
                        }
                    } else {
                        $netstart = Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $displayName -ScriptBlock { net start ""$args"" /mReset-DbaAdmin } 2>&1
                        foreach ($line in $netstart) {
                            if ($line.length -gt 0) {
                                Write-Message -Level Verbose -Message $line
                            }
                        }
                    }
                } catch {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue

                    if ($isClustered) {
                        $clusterResource | Where-Object Name -EQ "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object Name -NE "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                    } else {
                        Start-Service -InputObject $instanceServices -ErrorAction SilentlyContinue
                    }
                    Stop-Function -Message "Couldn't execute net start command. Restarted services and quit." -ErrorRecord $_
                    return
                }
            }

            if ($pscmdlet.ShouldProcess($baseaddress, "Testing $instance to ensure it's back up")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Testing $instance to ensure it's back up"
                try {
                    $null = Invoke-ResetSqlCmd -instance $instance -Sql "SELECT 1" -EnableException
                } catch {
                    try {
                        Start-Sleep 3
                        $null = Invoke-ResetSqlCmd -instance $instance -Sql "SELECT 1" -EnableException
                    } catch {
                        Stop-Service Input-Object $sqlservice -Force -ErrorAction SilentlyContinue
                        if ($isClustered) {
                            $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                            $clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        } else {
                            Start-Service -InputObject $instanceServices -ErrorAction SilentlyContinue
                        }
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_
                    }
                }
            }

            # Get login. If it doesn't exist, create it.
            if ($pscmdlet.ShouldProcess($instance, "Adding login $Login if it doesn't exist")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding login $Login if it doesn't exist"
                if ($windowslogin) {
                    $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$Login')
                    BEGIN CREATE LOGIN [$Login] FROM WINDOWS END"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't create Windows login."
                    }

                } elseif ($Login -ne "sa") {
                    # Create new sql user
                    $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$Login')
                    BEGIN CREATE LOGIN [$Login] WITH PASSWORD = '$(ConvertTo-PlainText $password)', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF END"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't create SQL login."
                    }
                }
            }

            # If $Login is a SQL Login, Mixed mode authentication is required.
            if ($windowslogin -ne $true) {
                if ($pscmdlet.ShouldProcess($instance, "Enabling mixed mode authentication for $Login and ensuring account is unlocked")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Enabling mixed mode authentication for $Login and ensuring account is unlocked"
                    $sql = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't set to Mixed Mode."
                    }

                    $sql = "ALTER LOGIN [$Login] WITH CHECK_POLICY = OFF
                    ALTER LOGIN [$Login] WITH PASSWORD = '$(ConvertTo-PlainText $password)' UNLOCK"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't unlock account."
                    }
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Enabling $Login")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensuring login is enabled"
                $sql = "ALTER LOGIN [$Login] ENABLE"
                if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                    Write-Message -Level Warning -Message "Couldn't enable login."
                }
            }

            if ($Login -ne "sa") {
                if ($pscmdlet.ShouldProcess($instance, "Ensuring $Login exists within sysadmin role")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensuring $Login exists within sysadmin role"
                    $sql = "EXEC sp_addsrvrolemember '$Login', 'sysadmin'"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't add to sysadmin role."
                    }
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Finished with login tasks. Restarting")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Finished with login tasks. Restarting."
                try {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                    if ($isClustered -eq $true) {
                        $clusterResource | Where-Object Name -EQ "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object Name -NE "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                    } else {
                        Start-Service -InputObject $instanceServices -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Logging in to get account information")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Logging in to get account information"
                if ($SecurePassword) {
                    $cred = New-Object System.Management.Automation.PSCredential ($Login, $SecurePassword)
                    Get-DbaLogin -SqlInstance $instance -SqlCredential $cred -Login $Login
                } elseif ($SqlCredential) {
                    Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login
                } else {
                    try {
                        Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login -EnableException
                    } catch {
                        Stop-Function -Message "Password not supplied, tried logging in with Integrated authentication and it failed. Either way, $Login should work now on $instance." -Continue
                    }
                }
            }

        }
    }
    end {
        Write-Message -Level Verbose -Message "Script complete."
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAbCtd8rhS2DBjo
# NIS2qQMLiwwfx/JyOVVZHJF57TU7kaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCFjlmGdbGyfcqTfzg/C3x7wDET1yPJRQHy
# Ygfx4B+TOzANBgkqhkiG9w0BAQEFAASCAQBW/uUUPgNNtxHAL4wIA5BtBApdItpO
# g5UOYj8RwhMMl0aekfJV7mtR58osCSj8s78XfcFWCFo1ca/yJMTCY3BHNc6a1eZ5
# +syR5LgzxuPEx/mIwFfpODjdNFlTUC8rv+GWrt7SH08yD2RLi9KpKKPs0KFfq0sW
# xyrQpahAFMR9bbeGU2FYtLCmycxixD3h+KWLeQx8gjHrPnEG3SNrbD0OE0Y2BV84
# c4eppM6u2DF7gSvLzh7r2LGtDtBowsyy4rZEko5wcFB7NdlUaU9OMxnGLLge0Bpi
# 4cgnKMV9cMzZOlAqQPcqXfqaINgY8tgvqy90giNLobDo4djIo/cNG1oIoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDM1MVowLwYJKoZIhvcNAQkEMSIEIAYmntvT
# H+kfLKJHDeXeV4/m9nr4fnTcYFldc4wAyyBYMA0GCSqGSIb3DQEBAQUABIICABdu
# egSOEusW/7nIDg6TlZjJXAdWrN74n7W5A+6Z7OrtQfmPuia1V4JG4vPTtvBm89Qk
# +8DjrTIdpeAdGwtC6V1cuU79VVNMGsuGtSadHCfKj7qDhnZ0Nlg0fuklYBMSeS7b
# cXasA9OP08B+7M2ZKxHPH/t0Ranwq0dnlJl6O0VSsoYvVhfXm8rx3+PZCW4gQc13
# YN4YmaX9mxf5KpVMP59wKvCYr3pOe8J183GvlgVI7oS52OgERciNC9eTfEMzxPNw
# ubhOssZkY9bCnyQjVZmBqsw5Z+kuEiTvP1zxgJmpOmK6Bejz6M4l2AtVPUHgBmwq
# zgkF7mo0zzz2ooKgL8oQnhHjHgckAGUS4gb81TiYyg6BUEUQSo+A6DB3y/Xz8D0k
# LEIO74OwIqJhJFYqhvdbjR87kASCVORbMWFWN43UKHcK9+86ECJ30TSF8yOUoVG6
# Whe+xg3lHFP/36ZaoXOsk4TkuMMChLZWSn/sAJgOJi/UHduuc0zLQ/jrcXALuZcY
# EwH5/7/oeekpRxpi0II4WfEI301wZcZy2aqXcwcXzO7jiDL5cI4PKevB7gpVOrF3
# geNMGUouf8HGX1J82hVqxWt+inUjjteWtPYxXk59HUztXH1iry3j5jbXvym6mL2m
# KX0Wg9ECrDKYiQkE2nHKvfg02MtOGvE8Qj8o5TyW
# SIG # End signature block
