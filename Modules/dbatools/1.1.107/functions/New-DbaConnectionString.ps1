function New-DbaConnectionString {
    <#
    .SYNOPSIS
        Builds or extracts a SQL Server Connection String

    .DESCRIPTION
        Builds or extracts a SQL Server Connection String. Note that dbatools-style syntax is used.

        So you do not need to specify "Data Source", you can just specify -SqlInstance and -SqlCredential and we'll handle it for you.

        This is the simplified PowerShell approach to connection string building. See examples for more info.

        See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. be it Windows or SQL Server. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER AccessToken
        Basically tells the connection string to ignore authentication. Does not include the AccessToken in the resulting connecstring.

    .PARAMETER AppendConnectionString
        Appends to the current connection string. Note that you cannot pass authentication information using this method. Use -SqlInstance and, optionally, -SqlCredential to set authentication information.

    .PARAMETER ApplicationIntent
        Declares the application workload type when connecting to a server. Possible values are ReadOnly and ReadWrite.

    .PARAMETER BatchSeparator
        By default, this is "GO"

    .PARAMETER ClientName
        By default, this command sets the client's ApplicationName property to "dbatools PowerShell module - dbatools.io". If you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client application name.

    .PARAMETER Database
        Database name

    .PARAMETER ConnectTimeout
        The length of time (in seconds) to wait for a connection to the server before terminating the attempt and generating an error.

        Valid values are greater than or equal to 0 and less than or equal to 2147483647.

        When opening a connection to a Azure SQL Database, set the connection timeout to 30 seconds.

    .PARAMETER EncryptConnection
        When true, SQL Server uses SSL encryption for all data sent between the client and server if the server has a certificate installed. Recognized values are true, false, yes, and no. For more information, see Connection String Syntax.

        Beginning in .NET Framework 4.5, when TrustServerCertificate is false and Encrypt is true, the server name (or IP address) in a SQL Server SSL certificate must exactly match the server name (or IP address) specified in the connection string. Otherwise, the connection attempt will fail. For information about support for certificates whose subject starts with a wildcard character (*), see Accepted wildcards used by server certificates for server authentication.

    .PARAMETER FailoverPartner
        The name of the failover partner server where database mirroring is configured.

        If the value of this key is "", then Initial Catalog must be present, and its value must not be "".

        The server name can be 128 characters or less.

        If you specify a failover partner but the failover partner server is not configured for database mirroring and the primary server (specified with the Server keyword) is not available, then the connection will fail.

        If you specify a failover partner and the primary server is not configured for database mirroring, the connection to the primary server (specified with the Server keyword) will succeed if the primary server is available.

    .PARAMETER IsActiveDirectoryUniversalAuth
        Azure related

    .PARAMETER LockTimeout
        Sets the time in seconds required for the connection to time out when the current transaction is locked.

    .PARAMETER MaxPoolSize
        Sets the maximum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MinPoolSize
        Sets the minimum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MultipleActiveResultSets
        When used, an application can maintain multiple active result sets (MARS). When false, an application must process or cancel all result sets from one batch before it can execute any other batch on that connection.

    .PARAMETER MultiSubnetFailover
        If your application is connecting to an AlwaysOn availability group (AG) on different subnets, setting MultiSubnetFailover provides faster detection of and connection to the (currently) active server. For more information about SqlClient support for Always On Availability Groups

    .PARAMETER NetworkProtocol
        Connect explicitly using 'TcpIp','NamedPipes','Multiprotocol','AppleTalk','BanyanVines','Via','SharedMemory' and 'NWLinkIpxSpx'

    .PARAMETER NonPooledConnection
        Request a non-pooled connection

    .PARAMETER PacketSize
        Sets the size in bytes of the network packets used to communicate with an instance of SQL Server. Must match at server.

    .PARAMETER PooledConnectionLifetime
        When a connection is returned to the pool, its creation time is compared with the current time, and the connection is destroyed if that time span (in seconds) exceeds the value specified by Connection Lifetime. This is useful in clustered configurations to force load balancing between a running server and a server just brought online.

        A value of zero (0) causes pooled connections to have the maximum connection timeout.

    .PARAMETER SqlExecutionModes
        The SqlExecutionModes enumeration contains values that are used to specify whether the commands sent to the referenced connection to the server are executed immediately or saved in a buffer.

        Valid values include CaptureSql, ExecuteAndCaptureSql and ExecuteSql.

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a time-out error.

    .PARAMETER TrustServerCertificate
        Sets a value that indicates whether the channel will be encrypted while bypassing walking the certificate chain to validate trust.

    .PARAMETER WorkstationId
        Sets the name of the workstation connecting to SQL Server.

    .PARAMETER Legacy
        Use this switch to create a connection string using System.Data.SqlClient instead of Microsoft.Data.SqlClient.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Connection, Connect, ConnectionString
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaConnectionString

    .EXAMPLE
        PS C:\> New-DbaConnectionString -SqlInstance sql2014

        Creates a connection string that connects using Windows Authentication

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance sql2016 | New-DbaConnectionString

        Builds a connected SMO object using Connect-DbaInstance then extracts and displays the connection string

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> New-DbaConnectionString -SqlInstance sql2014 -Credential $wincred

        Creates a connection string that connects using alternative Windows credentials

    .EXAMPLE
        PS C:\> $sqlcred = Get-Credential sqladmin
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -Credential $sqlcred

        Login to sql2014 as SQL login sqladmin.

    .EXAMPLE
        PS C:\> $connstring = New-DbaConnectionString -SqlInstance mydb.database.windows.net -SqlCredential me@myad.onmicrosoft.com -Database db

        Creates a connection string for an Azure Active Directory login to Azure SQL db. Output looks like this:
        Data Source=TCP:mydb.database.windows.net,1433;Initial Catalog=db;User ID=me@myad.onmicrosoft.com;Password=fakepass;MultipleActiveResultSets=False;Connect Timeout=30;Encrypt=True;TrustServerCertificate=False;Application Name="dbatools PowerShell module - dbatools.io";Authentication="Active Directory Password"

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -ClientName "mah connection"

        Creates a connection string that connects using Windows Authentication and uses the client name "mah connection". So when you open up profiler or use extended events, you can search for "mah connection".

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"

        Creates a connection string that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover

        Creates a connection string with Windows Authentication that uses TCPIP and has MultiSubnetFailover enabled.

    .EXAMPLE
        PS C:\> $connstring = New-DbaConnectionString sql2016 -ApplicationIntent ReadOnly

        Creates a connection string with ReadOnly ApplicationIntent.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "Server", "DataSource")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("SqlCredential")]
        [PSCredential]$Credential,
        [string]$AccessToken,
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$ApplicationIntent,
        [string]$BatchSeparator,
        [string]$ClientName = "custom connection",
        [int]$ConnectTimeout,
        [string]$Database,
        [switch]$EncryptConnection,
        [string]$FailoverPartner,
        [switch]$IsActiveDirectoryUniversalAuth,
        [int]$LockTimeout,
        [int]$MaxPoolSize,
        [int]$MinPoolSize,
        [switch]$MultipleActiveResultSets,
        [switch]$MultiSubnetFailover,
        [ValidateSet('TcpIp', 'NamedPipes', 'Multiprotocol', 'AppleTalk', 'BanyanVines', 'Via', 'SharedMemory', 'NWLinkIpxSpx')]
        [string]$NetworkProtocol,
        [switch]$NonPooledConnection,
        [int]$PacketSize,
        [int]$PooledConnectionLifetime,
        [ValidateSet('CaptureSql', 'ExecuteAndCaptureSql', 'ExecuteSql')]
        [string]$SqlExecutionModes,
        [int]$StatementTimeout,
        [switch]$TrustServerCertificate,
        [string]$WorkstationId,
        [switch]$Legacy,
        [string]$AppendConnectionString
    )
    begin {
        function Test-Azure {
            Param (
                [DbaInstanceParameter[]]$SqlInstance
            )
            if ($SqlInstance.ComputerName -match $AzureDomain) {
                Write-Message -Level Debug -Message "Test for Azure is positive"
                return $true
            } else {
                Write-Message -Level Debug -Message "Test for Azure is negative"
                return $false
            }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {

            <#
            The new code path (formerly known as experimental) is now the default.
            To have a quick way to switch back in case any problems occur, the switch "legacy" is introduced: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            All the sub paths inside the following if clause will end with a continue, so the normal code path is not used.
            #>
            if (-not (Get-DbatoolsConfigValue -FullName sql.connection.legacy)) {
                <#
                Maybe more docs...
                #>
                Write-Message -Level Debug -Message "We have to build a connect string, using these parameters: $($PSBoundParameters.Keys)"

                # Test for unsupported parameters
                if (Test-Bound -ParameterName 'LockTimeout') {
                    Write-Message -Level Warning -Message "Parameter LockTimeout not supported, because it is not part of a connection string."
                }
                # TODO: That can be added to the Data Source - but why?
                #if (Test-Bound -ParameterName 'NetworkProtocol') {
                #    Write-Message -Level Warning -Message "Parameter NetworkProtocol not supported, because it is not part of a connection string."
                #}
                if (Test-Bound -ParameterName 'StatementTimeout') {
                    Write-Message -Level Warning -Message "Parameter StatementTimeout not supported, because it is not part of a connection string."
                }
                if (Test-Bound -ParameterName 'SqlExecutionModes') {
                    Write-Message -Level Warning -Message "Parameter SqlExecutionModes not supported, because it is not part of a connection string."
                }

                # Set defaults like in Connect-DbaInstance
                if (Test-Bound -Not -ParameterName 'Database') {
                    $Database = (Get-DbatoolsConfigValue -FullName 'sql.connection.database')
                }
                if (Test-Bound -Not -ParameterName 'ClientName') {
                    $ClientName = (Get-DbatoolsConfigValue -FullName 'sql.connection.clientname')
                }
                if (Test-Bound -Not -ParameterName 'ConnectTimeout') {
                    $ConnectTimeout = ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
                }
                if (Test-Bound -Not -ParameterName 'EncryptConnection') {
                    $EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt')
                }
                if (Test-Bound -Not -ParameterName 'NetworkProtocol') {
                    $np = (Get-DbatoolsConfigValue -FullName 'sql.connection.protocol')
                    if ($np) {
                        $NetworkProtocol = $np
                    }
                }
                if (Test-Bound -Not -ParameterName 'PacketSize') {
                    $PacketSize = (Get-DbatoolsConfigValue -FullName 'sql.connection.packetsize')
                }
                if (Test-Bound -Not -ParameterName 'TrustServerCertificate') {
                    $TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert')
                }
                # TODO: Maybe put this in a config item:
                $AzureDomain = "database.windows.net"

                # Rename credential parameter to align with other commands, later rename parameter
                $SqlCredential = $Credential

                if ($Pscmdlet.ShouldProcess($instance, "Making a new Connection String")) {
                    if ($instance.Type -like "Server") {
                        Write-Message -Level Debug -Message "server object passed in, connection string is: $($instance.InputObject.ConnectionContext.ConnectionString)"
                        if ($Legacy) {
                            $converted = $instance.InputObject.ConnectionContext.ConnectionString | Convert-ConnectionString
                            $connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $converted
                        } else {
                            $connStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $instance.InputObject.ConnectionContext.ConnectionString
                        }
                        # In Azure, check for a database change
                        if ((Test-Azure -SqlInstance $instance) -and $Database) {
                            $connStringBuilder['Initial Catalog'] = $Database
                        }
                        $connstring = $connStringBuilder.ConnectionString
                        # TODO: Should we check the other parameters and change the connection string accordingly?
                    } else {
                        if ($Legacy) {
                            $connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
                        } else {
                            $connStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder
                        }
                        $connStringBuilder['Data Source'] = $instance.FullSmoName
                        if ($ApplicationIntent) { $connStringBuilder['ApplicationIntent'] = $ApplicationIntent }
                        if ($ClientName) { $connStringBuilder['Application Name'] = $ClientName }
                        if ($ConnectTimeout) { $connStringBuilder['Connect Timeout'] = $ConnectTimeout }
                        if ($Database) { $connStringBuilder['Initial Catalog'] = $Database }
                        if ($EncryptConnection) { $connStringBuilder['Encrypt'] = $true } else { $connStringBuilder['Encrypt'] = $false }
                        if ($FailoverPartner) { $connStringBuilder['Failover Partner'] = $FailoverPartner }
                        if ($MaxPoolSize) { $connStringBuilder['Max Pool Size'] = $MaxPoolSize }
                        if ($MinPoolSize) { $connStringBuilder['Min Pool Size'] = $MinPoolSize }
                        if ($MultipleActiveResultSets) { $connStringBuilder['MultipleActiveResultSets'] = $true } else { $connStringBuilder['MultipleActiveResultSets'] = $false }
                        if ($MultiSubnetFailover) { $connStringBuilder['MultiSubnetFailover'] = $true }
                        if ($NonPooledConnection) { $connStringBuilder['Pooling'] = $false }
                        if ($PacketSize) { $connStringBuilder['Packet Size'] = $PacketSize }
                        if ($PooledConnectionLifetime) { $connStringBuilder['Load Balance Timeout'] = $PooledConnectionLifetime }
                        if ($TrustServerCertificate) { $connStringBuilder['TrustServerCertificate'] = $true } else { $connStringBuilder['TrustServerCertificate'] = $false }
                        if ($WorkstationId) { $connStringBuilder['Workstation Id'] = $WorkstationId }
                        if ($SqlCredential) {
                            Write-Message -Level Debug -Message "We have a SqlCredential"
                            $username = ($SqlCredential.UserName).TrimStart("\")
                            # support both ad\username and username@ad
                            if ($username -like "*\*") {
                                $domain, $login = $username.Split("\")
                                $username = "$login@$domain"
                            }
                            $connStringBuilder['User ID'] = $username
                            $connStringBuilder['Password'] = $SqlCredential.GetNetworkCredential().Password
                            if ((Test-Azure -SqlInstance $instance) -and ($username -like "*@*")) {
                                Write-Message -Level Debug -Message "We connect to Azure with Azure AD account, so adding Authentication=Active Directory Password"
                                $connStringBuilder['Authentication'] = 'Active Directory Password'
                            }
                        } else {
                            Write-Message -Level Debug -Message "We don't have a SqlCredential"
                            if (Test-Azure -SqlInstance $instance) {
                                Write-Message -Level Debug -Message "We connect to Azure, so adding Authentication=Active Directory Integrated"
                                $connStringBuilder['Authentication'] = 'Active Directory Integrated'
                            } else {
                                Write-Message -Level Debug -Message "We don't connect to Azure, so setting Integrated Security=True"
                                $connStringBuilder['Integrated Security'] = $true
                            }
                        }

                        # special config for Azure
                        if (Test-Azure -SqlInstance $instance) {
                            if (Test-Bound -Not -ParameterName ConnectTimeout) {
                                $connStringBuilder['Connect Timeout'] = 30
                            }
                            $connStringBuilder['Encrypt'] = $true
                            # Why adding tcp:?
                            #$connStringBuilder['Data Source'] = "tcp:$($instance.ComputerName),$($instance.Port)"
                        }
                        if ($Legacy) {
                            $connstring = $connStringBuilder.ConnectionString
                        } else {
                            $connstring = $connStringBuilder.ToString()
                        }
                        if ($AppendConnectionString) {
                            # TODO: Check if new connection string is still valid
                            $connstring = "$connstring;$AppendConnectionString"
                        }
                    }
                    $connstring
                    continue
                }
            }
            <#
            This is the end of the new default code path.
            All session with the configuration "sql.connection.legacy" set to $true will run through the following code.
            To use the legacy code path: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            #>

            Write-Message -Level Debug -Message "sql.connection.legacy is used"

            if ($Pscmdlet.ShouldProcess($instance, "Making a new Connection String")) {
                if ($instance.ComputerName -match "database\.windows\.net" -or $instance.InputObject.ComputerName -match "database\.windows\.net") {
                    if ($instance.InputObject.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                        $connstring = $instance.InputObject.ConnectionContext.ConnectionString
                        if ($Database) {
                            $olddb = $connstring -split ';' | Where-Object { $_.StartsWith("Initial Catalog") }
                            $newdb = "Initial Catalog=$Database"
                            if ($olddb) {
                                $connstring = $connstring.Replace("$olddb", "$newdb")
                            } else {
                                $connstring = "$connstring;$newdb;"
                            }
                        }
                        $connstring
                        continue
                    } else {
                        $isAzure = $true

                        if (-not (Test-Bound -ParameterName ConnectTimeout)) {
                            $ConnectTimeout = 30
                        }

                        if (-not (Test-Bound -ParameterName ClientName)) {
                            $ClientName = "dbatools PowerShell module - dbatools.io"

                        }
                        $EncryptConnection = $true
                        $instance = [DbaInstanceParameter]"tcp:$($instance.ComputerName),$($instance.Port)"
                    }
                }

                if ($instance.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                    return $instance.ConnectionContext.ConnectionString
                } else {
                    $guid = [System.Guid]::NewGuid()
                    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $guid

                    if ($AppendConnectionString) {
                        $connstring = $server.ConnectionContext.ConnectionString
                        $server.ConnectionContext.ConnectionString = "$connstring;$appendconnectionstring"
                        $server.ConnectionContext.ConnectionString
                    } else {

                        $server.ConnectionContext.ApplicationName = $ClientName
                        if ($BatchSeparator) { $server.ConnectionContext.BatchSeparator = $BatchSeparator }
                        if ($ConnectTimeout) { $server.ConnectionContext.ConnectTimeout = $ConnectTimeout }
                        if ($Database) { $server.ConnectionContext.DatabaseName = $Database }
                        if ($EncryptConnection) { $server.ConnectionContext.EncryptConnection = $true }
                        if ($IsActiveDirectoryUniversalAuth) { $server.ConnectionContext.IsActiveDirectoryUniversalAuth = $true }
                        if ($LockTimeout) { $server.ConnectionContext.LockTimeout = $LockTimeout }
                        if ($MaxPoolSize) { $server.ConnectionContext.MaxPoolSize = $MaxPoolSize }
                        if ($MinPoolSize) { $server.ConnectionContext.MinPoolSize = $MinPoolSize }
                        if ($MultipleActiveResultSets) { $server.ConnectionContext.MultipleActiveResultSets = $true }
                        if ($NetworkProtocol) { $server.ConnectionContext.NetworkProtocol = $NetworkProtocol }
                        if ($NonPooledConnection) { $server.ConnectionContext.NonPooledConnection = $true }
                        if ($PacketSize) { $server.ConnectionContext.PacketSize = $PacketSize }
                        if ($PooledConnectionLifetime) { $server.ConnectionContext.PooledConnectionLifetime = $PooledConnectionLifetime }
                        if ($StatementTimeout) { $server.ConnectionContext.StatementTimeout = $StatementTimeout }
                        if ($SqlExecutionModes) { $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes }
                        if ($TrustServerCertificate) { $server.ConnectionContext.TrustServerCertificate = $true }
                        if ($WorkstationId) { $server.ConnectionContext.WorkstationId = $WorkstationId }

                        if ($null -ne $Credential.username) {
                            $username = ($Credential.username).TrimStart("\")

                            if ($username -like "*\*") {
                                $username = $username.Split("\")[1]
                                $server.ConnectionContext.LoginSecure = $true
                                $server.ConnectionContext.ConnectAsUser = $true
                                $server.ConnectionContext.ConnectAsUserName = $username
                                $server.ConnectionContext.ConnectAsUserPassword = ($Credential).GetNetworkCredential().Password
                            } else {
                                $server.ConnectionContext.LoginSecure = $false
                                $server.ConnectionContext.set_Login($username)
                                $server.ConnectionContext.set_SecurePassword($Credential.Password)
                            }
                        }

                        $connstring = $server.ConnectionContext.ConnectionString
                        if ($MultiSubnetFailover) { $connstring = "$connstring;MultiSubnetFailover=True" }
                        if ($FailoverPartner) { $connstring = "$connstring;Failover Partner=$FailoverPartner" }
                        if ($ApplicationIntent) { $connstring = "$connstring;ApplicationIntent=$ApplicationIntent;" }

                        if ($isAzure) {
                            if ($Credential) {
                                if ($Credential.UserName -like "*\*" -or $Credential.UserName -like "*@*") {
                                    $connstring = "$connstring;Authentication=`"Active Directory Password`""
                                } else {
                                    $username = ($Credential.username).TrimStart("\")
                                    $server.ConnectionContext.LoginSecure = $false
                                    $server.ConnectionContext.set_Login($username)
                                    $server.ConnectionContext.set_SecurePassword($Credential.Password)
                                }
                            } else {
                                $connstring = $connstring.Replace("Integrated Security=True;", "Persist Security Info=True;")
                                if (-not $AccessToken) {
                                    $connstring = "$connstring;Authentication=`"Active Directory Integrated`""
                                }
                            }
                        }

                        if ($connstring -ne $server.ConnectionContext.ConnectionString) {
                            $server.ConnectionContext.ConnectionString = $connstring
                        }

                        ($server.ConnectionContext.ConnectionString).Replace($guid, $instance)
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCChiJQWdZA/AG/A
# KmvyuWQ3IN81IS2X41EG29QfrMJifKCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAm+3L/nbZoIQM59+FM4QgHeY8taVtnbX/w
# 7jhnhaX0ATANBgkqhkiG9w0BAQEFAASCAQClOTkSn9Qk+7o/BqZlqgHluKPhb+py
# 1/2B6i6bvm5JNL3NxhJyCqXfgreWREhAawb9hgREpHhagU2cGXu6jzT3rLc0/gbl
# OJoy7S0HwRDANheLfsND4770X4D6BG+ZMFg3OzzdBvynVL3ZkVNI/U0LzglOoCRI
# cW1ybf7ZLPHLl6z3ezjah3IWutAT83MrywYVha9gK5a6Mt6me4fLPjQ2fJH4PjKA
# F4UA8qjHQxWO8Z3rJtvfNhplsaUJH+2yvz3/l0f8Y49RJh5Mg1VsXV3PtCMOoPtN
# 8jBqV7TYNflwpdnGPRRCBJxkYUXQW8n7FXg/qrUd0ynVnzQ0aMiniQAqoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMzM1owLwYJKoZIhvcNAQkEMSIEINOXsrVk
# /jSaHaz2XbFWbUBo/T233VfrVbzDfsviiPlYMA0GCSqGSIb3DQEBAQUABIICAJJi
# IAJv8iLUr7y2LYAtOYY/miAM0t0/8Y6PQSIcDRZL+Pmtc/nrrVFyvKo0NJLaqX1t
# uebZQy0pfCJb/iNZRcKEGIlKgzf+w+ZR2a0HAMAJL0WbLNnAGNwKcqAvTTciAp+R
# d13quwkh1gamwKQUPJt1PIVslC6UTnXUVcBd8RwHchorTNBotSjamCcV5HxL3Diw
# o0TQwY+IW0E++e21aQeZH9s71pGSeMQFwLC2GfAnrb9o1Dva5kX1Q1aTg3QT9M1Y
# jYm5FgbhhhjkaKOo0lwEQk7gVS0jWP0b8/QkZD5C5wuAqZ7/vkD24bsNxC+/S8/O
# TyV/0UiyK+09GkaEsl+p9uw+ZkhuGxsr1KHsCd5G/zUjPLYhSeZSyodQ7Qc5bpu6
# tsh+ToXyKIxUeJf4P8Vx8e3zDQUY77WcitIY6oi3R+i3FNjzJO/O1R1X4mstiRL5
# So4ZDP8tTulxv0wkN0xOWxLOpmdGdL/G+KXTB5hJbm3i7Sm/oBvHAhdEk4F19l2+
# wkxxEGebxMiJHbMVqjbLgeHiYAHef+Uze3pNJNLMFrDJB6CK2aWLSCgmm82p2qp4
# 29TP8otMpHvmyi3iVBJHceDDHsngP4Riv77utoq9nam2I3TSXi72EOzDVAbBxxsM
# nlWRSYph/wzCKz6e0txmz4EOWi4h3LqCMoBQwPNy
# SIG # End signature block
