function Connect-DbaInstance {
    <#
    .SYNOPSIS
        Creates a robust, reusable SQL Server object.

    .DESCRIPTION
        This command creates a robust, reusable sql server object.

        It is robust because it initializes properties that do not cause enumeration by default. It also supports both Windows and SQL Server authentication methods, and detects which to use based upon the provided credentials.

        By default, this command also sets the connection's ApplicationName property  to "dbatools PowerShell module - dbatools.io - custom connection". If you're doing anything that requires profiling, you can look for this client name.

        Alternatively, you can pass in whichever client name you'd like using the -ClientName parameter. There are a ton of other parameters for you to explore as well.

        See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx,
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

        To execute SQL commands, you can use $server.ConnectionContext.ExecuteReader($sql) or $server.Databases['master'].ExecuteNonQuery($sql)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server.

    .PARAMETER AppendConnectionString
        Appends to the current connection string. Note that you cannot pass authentication information using this method. Use -SqlInstance and optionally -SqlCredential to set authentication information.

    .PARAMETER ApplicationIntent
        Declares the application workload type when connecting to a server.

        Valid values are "ReadOnly" and "ReadWrite".

    .PARAMETER BatchSeparator
        A string to separate groups of SQL statements being executed. By default, this is "GO".

    .PARAMETER ClientName
        By default, this command sets the client's ApplicationName property to "dbatools PowerShell module - dbatools.io". If you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client application name.

    .PARAMETER ConnectTimeout
        The length of time (in seconds) to wait for a connection to the server before terminating the attempt and generating an error.

        Valid values are integers between 0 and 2147483647.

        When opening a connection to a Azure SQL Database, set the connection timeout to 30 seconds.

    .PARAMETER EncryptConnection
        If this switch is enabled, SQL Server uses SSL encryption for all data sent between the client and server if the server has a certificate installed.

        For more information, see Connection String Syntax. https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/connection-string-syntax

        Beginning in .NET Framework 4.5, when TrustServerCertificate is false and Encrypt is true, the server name (or IP address) in a SQL Server SSL certificate must exactly match the server name (or IP address) specified in the connection string. Otherwise, the connection attempt will fail. For information about support for certificates whose subject starts with a wildcard character (*), see Accepted wildcards used by server certificates for server authentication. https://support.microsoft.com/en-us/help/258858/accepted-wildcards-used-by-server-certificates-for-server-authenticati

    .PARAMETER FailoverPartner
        The name of the failover partner server where database mirroring is configured.

        If the value of this key is "" (an empty string), then Initial Catalog must be present in the connection string, and its value must not be "".

        The server name can be 128 characters or less.

        If you specify a failover partner but the failover partner server is not configured for database mirroring and the primary server (specified with the Server keyword) is not available, then the connection will fail.

        If you specify a failover partner and the primary server is not configured for database mirroring, the connection to the primary server (specified with the Server keyword) will succeed if the primary server is available.

    .PARAMETER LockTimeout
        Sets the time in seconds required for the connection to time out when the current transaction is locked.

    .PARAMETER MaxPoolSize
        Sets the maximum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MinPoolSize
        Sets the minimum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MultipleActiveResultSets
        If this switch is enabled, an application can maintain multiple active result sets (MARS).

        If this switch is not enabled, an application must process or cancel all result sets from one batch before it can execute any other batch on that connection.

    .PARAMETER MultiSubnetFailover
        If this switch is enabled, and your application is connecting to an AlwaysOn availability group (AG) on different subnets, detection of and connection to the currently active server will be faster. For more information about SqlClient support for Always On Availability Groups, see https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql/sqlclient-support-for-high-availability-disaster-recovery

    .PARAMETER NetworkProtocol
        Explicitly sets the network protocol used to connect to the server.

        Valid values are "TcpIp","NamedPipes","Multiprotocol","AppleTalk","BanyanVines","Via","SharedMemory" and "NWLinkIpxSpx"

    .PARAMETER NonPooledConnection
        If this switch is enabled, a non-pooled connection will be requested.

    .PARAMETER PacketSize
        Sets the size in bytes of the network packets used to communicate with an instance of SQL Server. Must match at server.

    .PARAMETER PooledConnectionLifetime
        When a connection is returned to the pool, its creation time is compared with the current time and the connection is destroyed if that time span (in seconds) exceeds the value specified by Connection Lifetime. This is useful in clustered configurations to force load balancing between a running server and a server just brought online.

        A value of zero (0) causes pooled connections to have the maximum connection timeout.

    .PARAMETER SqlExecutionModes
        The SqlExecutionModes enumeration contains values that are used to specify whether the commands sent to the referenced connection to the server are executed immediately or saved in a buffer.

        Valid values include "CaptureSql", "ExecuteAndCaptureSql" and "ExecuteSql".

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a timeout error.

        The default is read from the configuration 'sql.execution.timeout' that is currently set to 0 (unlimited).
        If you want to change this to 10 minutes, use: Set-DbatoolsConfig -FullName 'sql.execution.timeout' -Value 600

    .PARAMETER TrustServerCertificate
        When this switch is enabled, the channel will be encrypted while bypassing walking the certificate chain to validate trust.

    .PARAMETER WorkstationId
        Sets the name of the workstation connecting to SQL Server.

    .PARAMETER AlwaysEncrypted
        Sets "Column Encryption Setting=enabled" on the connection so you can work with Always Encrypted values.

        For more informations, see https://docs.microsoft.com/en-us/sql/relational-databases/security/encryption/develop-using-always-encrypted-with-net-framework-data-provider

    .PARAMETER SqlConnectionOnly
        Instead of returning a rich SMO server object, this command will only return a SqlConnection object when setting this switch.

    .PARAMETER AzureUnsupported
        Terminate if Azure is detected but not supported

    .PARAMETER AzureDomain
        By default, this is set to database.windows.net

        In the event your AzureSqlDb is not on a database.windows.net domain, you can set a custom domain using the AzureDomain parameter.
        This tells Connect-DbaInstance to login to the database using the method that works best with Azure.

    .PARAMETER MinimumVersion
        Terminate if the target SQL Server instance version does not meet version requirements

    .PARAMETER Tenant
        The TenantId for an Azure Instance

    .PARAMETER AccessToken
        Connect to an Azure SQL Database or an Azure SQL Managed Instance with an AccessToken, that has to be generated with Get-AzAccessToken or New-DbaAzAccessToken.

        Note that the token is valid for only one hour and cannot be renewed automatically.

    .PARAMETER DedicatedAdminConnection
        Connects using "ADMIN:" to create a dedicated admin connection (DAC) as a non-pooled connection.
        If the instance is on a remote server, the remote access has to be enabled via "Set-DbaSpConfigure -Name RemoteDacConnectionsEnabled -Value $true" or "sp_configure 'remote admin connections', 1".
        The connection will not be closed if the variable holding the Server SMO is going out of scope, so it is very important to call .ConnectionContext.Disconnect() to close the connection. See example.

    .PARAMETER DisableException
        By default in most of our commands, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This command, however, gifts you  with "sea of red" exceptions, by default, because it is useful for advanced scripting.

        Using this switch turns our "nice by default" feature on which makes errors into pretty warnings.

    .NOTES
        Tags: Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Connect-DbaInstance

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance sql2014

        Creates an SMO Server object that connects using Windows Authentication

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $wincred

        Creates an SMO Server object that connects using alternative Windows credentials

    .EXAMPLE
        PS C:\> $sqlcred = Get-Credential sqladmin
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $sqlcred

        Login to sql2014 as SQL login sqladmin.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -ClientName "my connection"

        Creates an SMO Server object that connects using Windows Authentication and uses the client name "my connection".
        So when you open up profiler or use extended events, you can search for "my connection".

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"

        Creates an SMO Server object that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover

        Creates an SMO Server object that connects using Windows Authentication that uses TCP/IP and has MultiSubnetFailover enabled.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance sql2016 -ApplicationIntent ReadOnly

        Connects with ReadOnly ApplicationIntent.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD / Azure Active Directory, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database dbatools -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD Integrated Auth, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance "myserver.public.cust123.database.windows.net,3342" -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL Managed instance using AAD / Azure Active Directory, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance db.mycustomazure.com -Database mydb -AzureDomain mycustomazure.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        In the event your AzureSqlDb is not on a database.windows.net domain, you can set a custom domain using the AzureDomain parameter.
        This tells Connect-DbaInstance to login to the database using the method that works best with Azure.

    .EXAMPLE
        PS C:\> $connstring = "Data Source=TCP:mydb.database.windows.net,1433;User ID=sqladmin;Password=adfasdf;Connect Timeout=30;"
        PS C:\> $server = Connect-DbaInstance -ConnectionString $connstring
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure using a preconstructed connstring, then performs a sample query.
        ConnectionString is an alias of SqlInstance, so you can use -SqlInstance $connstring as well.

    .EXAMPLE
        PS C:\> $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database abc -SqCredential $cred -Tenant guidheremaybename
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        When connecting from a non-Azure workstation, logs into Azure using Universal with MFA Support with a username and password, then performs a sample query.

        Note that generating access tokens is not supported on Core, so when using Tenant on Core, we rewrite the connection string with Active Directory Service Principal authentication instead.

    .EXAMPLE
        PS C:\> $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
        PS C:\> Set-DbatoolsConfig -FullName azure.tenantid -Value 'guidheremaybename' -Passthru | Register-DbatoolsConfig
        PS C:\> Set-DbatoolsConfig -FullName azure.appid -Value $cred.Username -Passthru | Register-DbatoolsConfig
        PS C:\> Set-DbatoolsConfig -FullName azure.clientsecret -Value $cred.Password -Passthru | Register-DbatoolsConfig # requires securestring
        PS C:\> Set-DbatoolsConfig -FullName sql.connection.database -Value abc -Passthru | Register-DbatoolsConfig
        PS C:\> Connect-DbaInstance -SqlInstance psdbatools.database.windows.net

        Permanently sets some app id config values. To set them temporarily (just for a session), remove -Passthru | Register-DbatoolsConfig
        When connecting from a non-Azure workstation or an Azure VM without .NET 4.7.2 and higher, logs into Azure using Universal with MFA Support, then performs a sample query.

    .EXAMPLE
        PS C:\> $azureCredential = Get-Credential -Message 'Azure Credential'
        PS C:\> $azureAccount = Connect-AzAccount -Credential $azureCredential
        PS C:\> $azureToken = Get-AzAccessToken -ResourceUrl https://database.windows.net
        PS C:\> $azureInstance = "YOURSERVER.database.windows.net"
        PS C:\> $azureDatabase = "MYDATABASE"
        PS C:\> $server = Connect-DbaInstance -SqlInstance $azureInstance -Database $azureDatabase -AccessToken $azureToken
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Connect to an Azure SQL Database or an Azure SQL Managed Instance with an AccessToken.
        Note that the token is valid for only one hour and cannot be renewed automatically.

    .EXAMPLE
        PS C:\> $token = New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $tenantid -Credential $cred
        PS C:\> Connect-DbaInstance -SqlInstance sample.database.windows.net -Accesstoken $token

        Uses dbatools to generate the access token for an Azure SQL Database, then logs in using that AccessToken.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance srv1 -DedicatedAdminConnection
        PS C:\> $dbaProcess = Get-DbaProcess -SqlInstance $server -ExcludeSystemSpids
        PS C:\> $killedProcess = $dbaProcess | Out-GridView -OutputMode Multiple | Stop-DbaProcess
        PS C:\> $server | Disconnect-DbaInstance

        Creates a dedicated admin connection (DAC) to the default instance on server srv1.
        Receives all non-system processes from the instance using the DAC.
        Opens a grid view to let the user select processes to be stopped.
        Closes the connection.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Connstring", "ConnectionString")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database = (Get-DbatoolsConfigValue -FullName 'sql.connection.database'),
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$ApplicationIntent,
        [switch]$AzureUnsupported,
        [string]$BatchSeparator,
        [string]$ClientName = (Get-DbatoolsConfigValue -FullName 'sql.connection.clientname'),
        [int]$ConnectTimeout = ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout),
        [switch]$EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt'),
        [string]$FailoverPartner,
        [int]$LockTimeout,
        [int]$MaxPoolSize,
        [int]$MinPoolSize,
        [int]$MinimumVersion,
        [switch]$MultipleActiveResultSets,
        [switch]$MultiSubnetFailover = (Get-DbatoolsConfigValue -FullName 'sql.connection.multisubnetfailover'),
        [ValidateSet('TcpIp', 'NamedPipes', 'Multiprotocol', 'AppleTalk', 'BanyanVines', 'Via', 'SharedMemory', 'NWLinkIpxSpx')]
        [string]$NetworkProtocol = (Get-DbatoolsConfigValue -FullName 'sql.connection.protocol'),
        [switch]$NonPooledConnection,
        [int]$PacketSize = (Get-DbatoolsConfigValue -FullName 'sql.connection.packetsize'),
        [int]$PooledConnectionLifetime,
        [ValidateSet('CaptureSql', 'ExecuteAndCaptureSql', 'ExecuteSql')]
        [string]$SqlExecutionModes,
        [int]$StatementTimeout = (Get-DbatoolsConfigValue -FullName 'sql.execution.timeout'),
        [switch]$TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert'),
        [string]$WorkstationId,
        [switch]$AlwaysEncrypted,
        [string]$AppendConnectionString,
        [switch]$SqlConnectionOnly,
        [string]$AzureDomain = "database.windows.net",
        [string]$Tenant = (Get-DbatoolsConfigValue -FullName 'azure.tenantid'),
        [psobject]$AccessToken,
        [switch]$DedicatedAdminConnection,
        [switch]$DisableException
    )
    begin {
        function Test-Azure {
            Param (
                [DbaInstanceParameter]$SqlInstance
            )
            if ($SqlInstance.ComputerName -match $AzureDomain -or $instance.InputObject.ComputerName -match $AzureDomain) {
                Write-Message -Level Debug -Message "Test for Azure is positive"
                return $true
            } else {
                Write-Message -Level Debug -Message "Test for Azure is negative"
                return $false
            }
        }
        function Invoke-TEPPCacheUpdate {
            [CmdletBinding()]
            param (
                [System.Management.Automation.ScriptBlock]$ScriptBlock
            )

            try {
                [ScriptBlock]::Create($scriptBlock).Invoke()
            } catch {
                # If the SQL Server version doesn't support the feature, we ignore it and silently continue
                if ($_.Exception.InnerException.InnerException.GetType().FullName -eq "Microsoft.SqlServer.Management.Sdk.Sfc.InvalidVersionEnumeratorException") {
                    return
                }

                if ($ENV:APPVEYOR_BUILD_FOLDER -or ([Sqlcollaborative.Dbatools.Message.MEssageHost]::DeveloperMode)) { Stop-Function -Message }
                else {
                    Write-Message -Level Warning -Message "Failed TEPP Caching: $($scriptBlock.ToString() | Select-String '"(.*?)"' | ForEach-Object { $_.Matches[0].Groups[1].Value })" -ErrorRecord $_ 3>$null
                }
            }
        }
        #endregion Utility functions

        #region Ensure Credential integrity
        <#
        Usually, the parameter type should have been not object but off the PSCredential type.
        When binding null to a PSCredential type parameter on PS3-4, it'd then show a prompt, asking for username and password.

        In order to avoid that and having to refactor lots of functions (and to avoid making regular scripts harder to read), we created this workaround.
        #>
        if ($SqlCredential) {
            if ($SqlCredential.GetType() -ne [System.Management.Automation.PSCredential]) {
                Stop-Function -Message "The credential parameter was of a non-supported type. Only specify PSCredentials such as generated from Get-Credential. Input was of type $($SqlCredential.GetType().FullName)"
                return
            }
        }
        #endregion Ensure Credential integrity

        # In an unusual move, Connect-DbaInstance goes the exact opposite way of all commands when it comes to exceptions
        # this means that by default it Stop-Function -Messages, but do not be tempted to Stop-Function -Message
        if ($DisableException) {
            $EnableException = $false
        } else {
            $EnableException = $true
        }

        $loadedSmoVersion = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
            $_.Fullname -like "Microsoft.SqlServer.SMO,*"
        }

        if ($loadedSmoVersion) {
            $loadedSmoVersion = $loadedSmoVersion | ForEach-Object {
                if ($_.Location -match "__") {
                    ((Split-Path (Split-Path $_.Location) -Leaf) -split "__")[0]
                } else {
                    ((Get-ChildItem -Path $_.Location).VersionInfo.ProductVersion)
                }
            }
        }

        #'PrimaryFilePath' seems the culprit for slow SMO on databases
        $Fields2000_Db = 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsSystemObject', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'ReadOnly', 'RecoveryModel', 'ReplicationOptions', 'Status', 'Version'
        $Fields200x_Db = $Fields2000_Db + @('BrokerEnabled', 'DatabaseSnapshotBaseName', 'IsMirroringEnabled', 'Trustworthy')
        $Fields201x_Db = $Fields200x_Db + @('ActiveConnections', 'AvailabilityDatabaseSynchronizationState', 'AvailabilityGroupName', 'ContainmentType', 'EncryptionEnabled')

        $Fields2000_Login = 'CreateDate', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'Name', 'Sid', 'WindowsLoginAccessType'
        $Fields200x_Login = $Fields2000_Login + @('AsymmetricKey', 'Certificate', 'Credential', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'MustChangePassword', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced')
        $Fields201x_Login = $Fields200x_Login + @('PasswordHashAlgorithm')

        #see #7753
        $Fields_Job = 'LastRunOutcome', 'CurrentRunStatus', 'CurrentRunStep', 'CurrentRunRetryAttempt', 'NextRunScheduleID', 'NextRunDate', 'LastRunDate', 'JobType', 'HasStep', 'HasServer', 'CurrentRunRetryAttempt', 'HasSchedule', 'Category', 'CategoryID', 'CategoryType', 'OperatorToEmail', 'OperatorToNetSend', 'OperatorToPage'
        if ($AzureDomain) { $AzureDomain = [regex]::escape($AzureDomain) }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        # if tenant is specified with a GUID username such as 21f5633f-6776-4bab-b878-bbd5e3e5ed72 (for clientid)
        if ($Tenant -and -not $AccessToken -and $SqlCredential.UserName -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {

            try {
                if ($PSVersionTable.PSEdition -eq "Core") {
                    Write-Message -Level Verbose "Generating access tokens is not supported on Core. Will try connection string with Active Directory Service Principal instead. See https://github.com/dataplat/dbatools/pull/7610 for more information."
                    $tryconnstring = $true
                } else {
                    Write-Message -Level Verbose "Tenant detected, getting access token"
                    $AccessToken = (New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $Tenant -Credential $SqlCredential -ErrorAction Stop).GetAccessToken()
                    $PSBoundParameters.Tenant = $Tenant = $null
                    $PSBoundParameters.SqlCredential = $SqlCredential = $null
                    $PSBoundParameters.AccessToken = $AccessToken
                }

            } catch {
                $errormessage = Get-ErrorMessage -Record $_
                Stop-Function -Message "Failed to get access token for Azure SQL DB ($errormessage)"
                return
            }
        }

        Write-Message -Level Debug -Message "Starting process block"
        foreach ($instance in $SqlInstance) {
            if ($tryconnstring) {
                $azureserver = $instance.InputObject
                if ($Database) {
                    $instance = [DbaInstanceParameter]"Server=$azureserver; Authentication=Active Directory Service Principal; Database=$Database; User Id=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password)"
                } else {
                    $instance = [DbaInstanceParameter]"Server=$azureserver; Authentication=Active Directory Service Principal; User Id=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password)"
                }
            }

            Write-Message -Level Debug -Message "Immediately checking for Azure"
            if ((Test-Azure -SqlInstance $instance)) {
                Write-Message -Level Verbose -Message "Azure detected"
                $IsAzure = $true
            } else {
                $IsAzure = $false
            }
            Write-Message -Level Debug -Message "Starting loop for '$instance': ComputerName = '$($instance.ComputerName)', InstanceName = '$($instance.InstanceName)', IsLocalHost = '$($instance.IsLocalHost)', Type = '$($instance.Type)'"
            <#
            Best practice:
            * Create a smo server object by submitting the name of the instance as a string to SqlInstance and additional parameters to configure the connection
            * Reuse the smo server object in all following calls as SqlInstance
            * When reusing the smo server object, only the following additional parameters are allowed with Connect-DbaInstance:
                - Database, ApplicationIntent, NonPooledConnection, StatementTimeout (command clones ConnectionContext and returns new smo server object)
                - AzureUnsupported (command fails if target is Azure)
                - MinimumVersion (command fails if target version is too old)
                - SqlConnectionOnly (command returns only the ConnectionContext.SqlConnectionObject)
            Commands that use these parameters:
            * ApplicationIntent
                - Invoke-DbaQuery
            * NonPooledConnection
                - Install-DbaFirstResponderKit
            * StatementTimeout (sometimes not as a parameter, they should changed to do so)
                - Backup-DbaDatabase
                - Restore-DbaDatabase
                - Get-DbaTopResourceUsage
                - Import-DbaCsv
                - Invoke-DbaDbLogShipping
                - Invoke-DbaDbShrink
                - Invoke-DbaDbUpgrade
                - Set-DbaDbCompression
                - Test-DbaDbCompression
                - Start-DbccCheck
            * AzureUnsupported
                - Backup-DbaDatabase
                - Copy-DbaLogin
                - Get-DbaLogin
                - Set-DbaLogin
                - Get-DbaDefaultPath
                - Get-DbaUserPermission
                - Get-DbaXESession
                - New-DbaCustomError
                - Remove-DbaCustomError
            Additional possibilities as input to SqlInstance:
            * A smo connection object [Microsoft.Data.SqlClient.SqlConnection] (InputObject is used to build smo server object)
            * A smo registered server object [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer] (FullSmoName und InputObject.ConnectionString are used to build smo server object)
            * A connections string [String] (FullSmoName und InputObject are used to build smo server object)
            Limitations of these additional possibilities:
            * All additional parameters are ignored, a warning is displayed if they are used
            * Currently, connection pooling does not work with connections that are build from connection strings
            * All parameters that configure the connection and where they can be set (here just for documentation and future development):
                - AppendConnectionString      SqlConnectionInfo.AdditionalParameters
                - ApplicationIntent           SqlConnectionInfo.ApplicationIntent          SqlConnectionStringBuilder['ApplicationIntent']
                - AuthenticationType          SqlConnectionInfo.Authentication             SqlConnectionStringBuilder['Authentication']
                - BatchSeparator                                                                                                                     ConnectionContext.BatchSeparator
                - ClientName                  SqlConnectionInfo.ApplicationName            SqlConnectionStringBuilder['Application Name']
                - ConnectTimeout              SqlConnectionInfo.ConnectionTimeout          SqlConnectionStringBuilder['Connect Timeout']
                - Database                    SqlConnectionInfo.DatabaseName               SqlConnectionStringBuilder['Initial Catalog']
                - EncryptConnection           SqlConnectionInfo.EncryptConnection          SqlConnectionStringBuilder['Encrypt']
                - FailoverPartner             SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['Failover Partner']
                - LockTimeout                                                                                                                        ConnectionContext.LockTimeout
                - MaxPoolSize                 SqlConnectionInfo.MaxPoolSize                SqlConnectionStringBuilder['Max Pool Size']
                - MinPoolSize                 SqlConnectionInfo.MinPoolSize                SqlConnectionStringBuilder['Min Pool Size']
                - MultipleActiveResultSets                                                 SqlConnectionStringBuilder['MultipleActiveResultSets']    ConnectionContext.MultipleActiveResultSets
                - MultiSubnetFailover         SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['MultiSubnetFailover']
                - NetworkProtocol             SqlConnectionInfo.ConnectionProtocol
                - NonPooledConnection         SqlConnectionInfo.Pooled                     SqlConnectionStringBuilder['Pooling']
                - PacketSize                  SqlConnectionInfo.PacketSize                 SqlConnectionStringBuilder['Packet Size']
                - PooledConnectionLifetime    SqlConnectionInfo.PoolConnectionLifeTime     SqlConnectionStringBuilder['Load Balance Timeout']
                - SqlInstance                 SqlConnectionInfo.ServerName                 SqlConnectionStringBuilder['Data Source']
                - SqlCredential               SqlConnectionInfo.SecurePassword             SqlConnectionStringBuilder['Password']
                                            SqlConnectionInfo.UserName                   SqlConnectionStringBuilder['User ID']
                                            SqlConnectionInfo.UseIntegratedSecurity      SqlConnectionStringBuilder['Integrated Security']
                - SqlExecutionModes                                                                                                                  ConnectionContext.SqlExecutionModes
                - StatementTimeout            (SqlConnectionInfo.QueryTimeout?)                                                                      ConnectionContext.StatementTimeout
                - TrustServerCertificate      SqlConnectionInfo.TrustServerCertificate     SqlConnectionStringBuilder['TrustServerCertificate']
                - WorkstationId               SqlConnectionInfo.WorkstationId              SqlConnectionStringBuilder['Workstation Id']

            Some additional tests:
            * Is $AzureUnsupported set? Test for Azure.
            * Is $MinimumVersion set? Test for that.
            * Is $SqlConnectionOnly set? Then return $server.ConnectionContext.SqlConnectionObject.
            * Does the server object have the additional properties? Add them when necessary.

            Some general decisions:
            * We try to treat connections to Azure as normal connections.
            * Not every edge case will be covered at the beginning.
            * We copy as less code from the existing code paths as possible.
            #>

            # Analyse input object and extract necessary parts
            if ($instance.Type -like 'Server') {
                Write-Message -Level Verbose -Message "Server object passed in, will do some checks and then return the original object"
                $inputObjectType = 'Server'
                $inputObject = $instance.InputObject
            } elseif ($instance.Type -like 'SqlConnection') {
                Write-Message -Level Verbose -Message "SqlConnection object passed in, will build server object from instance.InputObject, do some checks and then return the server object"
                $inputObjectType = 'SqlConnection'
                $inputObject = $instance.InputObject
            } elseif ($instance.Type -like 'RegisteredServer') {
                Write-Message -Level Verbose -Message "RegisteredServer object passed in, will build empty server object, set connection string from instance.InputObject.ConnectionString, do some checks and then return the server object"
                $inputObjectType = 'RegisteredServer'
                $inputObject = $instance.InputObject
                $serverName = $instance.FullSmoName
                $connectionString = $instance.InputObject.ConnectionString
            } elseif ($instance.IsConnectionString) {
                Write-Message -Level Verbose -Message "Connection string is passed in, will build empty server object, set connection string from instance.InputObject, do some checks and then return the server object"
                $inputObjectType = 'ConnectionString'
                $serverName = $instance.FullSmoName
                $connectionString = $instance.InputObject
            } else {
                Write-Message -Level Verbose -Message "String is passed in, will build server object from instance object and other parameters, do some checks and then return the server object"
                $inputObjectType = 'String'
                $serverName = $instance.FullSmoName
            }

            # Check for ignored parameters
            # We do not check for SqlCredential as this parameter is widly used even if a server SMO is passed in and we don't want to outout a message for that
            $ignoredParameters = 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'NetworkProtocol', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'TrustServerCertificate', 'WorkstationId', 'FailoverPartner', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'AppendConnectionString', 'AccessToken'
            if ($inputObjectType -eq 'Server') {
                if (Test-Bound -ParameterName $ignoredParameters) {
                    Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                }
            } elseif ($inputObjectType -in 'RegisteredServer', 'ConnectionString' ) {
                if (Test-Bound -ParameterName $ignoredParameters, 'ApplicationIntent', 'StatementTimeout') {
                    Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                }
            } elseif ($inputObjectType -in 'SqlConnection' ) {
                if (Test-Bound -ParameterName $ignoredParameters, 'ApplicationIntent', 'StatementTimeout', 'DedicatedAdminConnection') {
                    Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                }
            }

            if ($DedicatedAdminConnection -and $serverName) {
                Write-Message -Level Debug -Message "Parameter DedicatedAdminConnection is used, so serverName will be changed and NonPooledConnection will be set."
                $serverName = 'ADMIN:' + $serverName
                $NonPooledConnection = $true
            }

            # Create smo server object
            if ($inputObjectType -eq 'Server') {
                # Test if we have to copy the connection context
                # Currently only if we have a different Database or have to swith to a NonPooledConnection or using a specific StatementTimeout or using ApplicationIntent
                # We do not test for SqlCredential as this would change the behavior compared to the legacy code path
                $copyContext = $false
                if ($Database -and $inputObject.ConnectionContext.CurrentDatabase -ne $Database) {
                    Write-Message -Level Verbose -Message "Database provided. Does not match ConnectionContext.CurrentDatabase, copying ConnectionContext and setting the CurrentDatabase"
                    $copyContext = $true
                }
                if ($ApplicationIntent -and $inputObject.ConnectionContext.ApplicationIntent -ne $ApplicationIntent) {
                    Write-Message -Level Verbose -Message "ApplicationIntent provided. Does not match ConnectionContext.ApplicationIntent, copying ConnectionContext and setting the ApplicationIntent"
                    $copyContext = $true
                }
                if ($NonPooledConnection -and -not $inputObject.ConnectionContext.NonPooledConnection) {
                    Write-Message -Level Verbose -Message "NonPooledConnection provided. Does not match ConnectionContext.NonPooledConnection, copying ConnectionContext and setting NonPooledConnection"
                    $copyContext = $true
                }
                if (Test-Bound -Parameter StatementTimeout -and $inputObject.ConnectionContext.StatementTimeout -ne $StatementTimeout) {
                    Write-Message -Level Verbose -Message "StatementTimeout provided. Does not match ConnectionContext.StatementTimeout, copying ConnectionContext and setting the StatementTimeout"
                    $copyContext = $true
                }
                if ($DedicatedAdminConnection -and $inputObject.ConnectionContext.ServerInstance -notmatch '^ADMIN:') {
                    Write-Message -Level Verbose -Message "DedicatedAdminConnection provided. Does not match ConnectionContext.ServerInstance, copying ConnectionContext and setting the ServerInstance"
                    $copyContext = $true
                }
                if ($copyContext) {
                    $connContext = $inputObject.ConnectionContext.Copy()
                    if ($ApplicationIntent) {
                        $connContext.ApplicationIntent = $ApplicationIntent
                    }
                    if ($NonPooledConnection) {
                        $connContext.NonPooledConnection = $true
                    }
                    if (Test-Bound -Parameter StatementTimeout) {
                        $connContext.StatementTimeout = $StatementTimeout
                    }
                    if ($DedicatedAdminConnection -and $inputObject.ConnectionContext.ServerInstance -notmatch '^ADMIN:') {
                        $connContext.ServerInstance = 'ADMIN:' + $connContext.ServerInstance
                        $connContext.NonPooledConnection = $true
                    }
                    if ($Database) {
                        # Save StatementTimeout because it might be reset on GetDatabaseConnection
                        $savedStatementTimeout = $connContext.StatementTimeout
                        $connContext = $connContext.GetDatabaseConnection($Database)
                        $connContext.StatementTimeout = $savedStatementTimeout
                    }
                    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $connContext
                } else {
                    $server = $inputObject
                }
            } elseif ($inputObjectType -eq 'SqlConnection') {
                $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $inputObject
            } elseif ($inputObjectType -in 'RegisteredServer', 'ConnectionString') {
                $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $serverName
                $server.ConnectionContext.ConnectionString = $connectionString
            } elseif ($inputObjectType -eq 'String') {
                # Identify authentication method
                if (Test-Azure -SqlInstance $instance) {
                    $authType = 'azure '
                } else {
                    $authType = 'local '
                }
                if ($SqlCredential) {
                    # support both ad\username and username@ad
                    $username = ($SqlCredential.UserName).TrimStart("\")
                    if ($username -like "*\*") {
                        $domain, $login = $username.Split("\")
                        $username = "$login@$domain"
                    }
                    if ($username -like '*@*') {
                        $authType += 'ad'
                    } else {
                        $authType += 'sql'
                    }
                } elseif ($AccessToken) {
                    $authType += 'token'
                } else {
                    $authType += 'integrated'
                }
                Write-Message -Level Verbose -Message "authentication method is '$authType'"

                # Best way to get connection pooling to work is to use SqlConnectionInfo -> ServerConnection -> Server
                $sqlConnectionInfo = New-Object -TypeName Microsoft.SqlServer.Management.Common.SqlConnectionInfo -ArgumentList $serverName

                # But if we have an AccessToken, we need ConnectionString -> SqlConnection -> ServerConnection -> Server
                # We will get the ConnectionString from the SqlConnectionInfo, so let's move on

                # I will list all properties of SqlConnectionInfo and set them if value is provided

                #AccessToken            Property   Microsoft.SqlServer.Management.Common.IRenewableToken AccessToken {get;set;}
                # This parameter needs an IRenewableToken and we currently support only a non renewable token

                #AdditionalParameters   Property   string AdditionalParameters {get;set;}
                if ($AppendConnectionString) {
                    Write-Message -Level Debug -Message "AdditionalParameters will be appended by '$AppendConnectionString;'"
                    $sqlConnectionInfo.AdditionalParameters += "$AppendConnectionString;"
                }
                if ($FailoverPartner) {
                    Write-Message -Level Debug -Message "AdditionalParameters will be appended by 'FailoverPartner=$FailoverPartner;'"
                    $sqlConnectionInfo.AdditionalParameters += "FailoverPartner=$FailoverPartner;"
                }
                if ($MultiSubnetFailover) {
                    Write-Message -Level Debug -Message "AdditionalParameters will be appended by 'MultiSubnetFailover=True;'"
                    $sqlConnectionInfo.AdditionalParameters += 'MultiSubnetFailover=True;'
                }
                if ($AlwaysEncrypted) {
                    Write-Message -Level Debug -Message "AdditionalParameters will be appended by 'Column Encryption Setting=enabled;'"
                    $sqlConnectionInfo.AdditionalParameters += 'Column Encryption Setting=enabled;'
                }

                #ApplicationIntent      Property   string ApplicationIntent {get;set;}
                if ($ApplicationIntent) {
                    Write-Message -Level Debug -Message "ApplicationIntent will be set to '$ApplicationIntent'"
                    $sqlConnectionInfo.ApplicationIntent = $ApplicationIntent
                }

                #ApplicationName        Property   string ApplicationName {get;set;}
                if ($ClientName) {
                    Write-Message -Level Debug -Message "ApplicationName will be set to '$ClientName'"
                    $sqlConnectionInfo.ApplicationName = $ClientName
                }

                #Authentication         Property   Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod Authentication {get;set;}
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryInteractive
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::NotSpecified
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::SqlPassword
                if ($authType -eq 'azure integrated') {
                    # Azure AD integrated security
                    # TODO: This is not tested / How can we test that?
                    Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryIntegrated'"
                    $sqlConnectionInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
                } elseif ($authType -eq 'azure ad') {
                    # Azure AD account with password
                    Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryPassword'"
                    $sqlConnectionInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
                }

                #ConnectionProtocol     Property   Microsoft.SqlServer.Management.Common.NetworkProtocol ConnectionProtocol {get;set;}
                if ($NetworkProtocol) {
                    Write-Message -Level Debug -Message "ConnectionProtocol will be set to '$NetworkProtocol'"
                    $sqlConnectionInfo.ConnectionProtocol = $NetworkProtocol
                }

                #ConnectionString       Property   string ConnectionString {get;}
                # Only a getter, not a setter - so don't touch

                #ConnectionTimeout      Property   int ConnectionTimeout {get;set;}
                if ($ConnectTimeout) {
                    Write-Message -Level Debug -Message "ConnectionTimeout will be set to '$ConnectTimeout'"
                    $sqlConnectionInfo.ConnectionTimeout = $ConnectTimeout
                }

                #DatabaseName           Property   string DatabaseName {get;set;}
                if ($Database) {
                    Write-Message -Level Debug -Message "Database will be set to '$Database'"
                    $sqlConnectionInfo.DatabaseName = $Database
                }

                #EncryptConnection      Property   bool EncryptConnection {get;set;}
                if ($EncryptConnection) {
                    Write-Message -Level Debug -Message "EncryptConnection will be set to '$EncryptConnection'"
                    $sqlConnectionInfo.EncryptConnection = $EncryptConnection
                }

                #MaxPoolSize            Property   int MaxPoolSize {get;set;}
                if ($MaxPoolSize) {
                    Write-Message -Level Debug -Message "MaxPoolSize will be set to '$MaxPoolSize'"
                    $sqlConnectionInfo.MaxPoolSize = $MaxPoolSize
                }

                #MinPoolSize            Property   int MinPoolSize {get;set;}
                if ($MinPoolSize) {
                    Write-Message -Level Debug -Message "MinPoolSize will be set to '$MinPoolSize'"
                    $sqlConnectionInfo.MinPoolSize = $MinPoolSize
                }

                #PacketSize             Property   int PacketSize {get;set;}
                if ($PacketSize) {
                    Write-Message -Level Debug -Message "PacketSize will be set to '$PacketSize'"
                    $sqlConnectionInfo.PacketSize = $PacketSize
                }

                #Password               Property   string Password {get;set;}
                # We will use SecurePassword

                #PoolConnectionLifeTime Property   int PoolConnectionLifeTime {get;set;}
                if ($PooledConnectionLifetime) {
                    Write-Message -Level Debug -Message "PoolConnectionLifeTime will be set to '$PooledConnectionLifetime'"
                    $sqlConnectionInfo.PoolConnectionLifeTime = $PooledConnectionLifetime
                }

                #Pooled                 Property   System.Data.SqlTypes.SqlBoolean Pooled {get;set;}
                # TODO: Do we need or want the else path or is it the default and we better don't touch it?
                if ($NonPooledConnection) {
                    Write-Message -Level Debug -Message "Pooled will be set to '$false'"
                    $sqlConnectionInfo.Pooled = $false
                } else {
                    Write-Message -Level Debug -Message "Pooled will be set to '$true'"
                    $sqlConnectionInfo.Pooled = $true
                }

                #QueryTimeout           Property   int QueryTimeout {get;set;}
                # We use ConnectionContext.StatementTimeout instead

                #SecurePassword         Property   securestring SecurePassword {get;set;}
                if ($authType -in 'azure ad', 'azure sql', 'local sql') {
                    Write-Message -Level Debug -Message "SecurePassword will be set"
                    $sqlConnectionInfo.SecurePassword = $SqlCredential.Password
                }

                #ServerCaseSensitivity  Property   Microsoft.SqlServer.Management.Common.ServerCaseSensitivity ServerCaseSensitivity {get;set;}

                #ServerName             Property   string ServerName {get;set;}
                # Was already set by the constructor.

                #ServerType             Property   Microsoft.SqlServer.Management.Common.ConnectionType ServerType {get;}
                # Only a getter, not a setter - so don't touch

                #ServerVersion          Property   Microsoft.SqlServer.Management.Common.ServerVersion ServerVersion {get;set;}
                # We can set that? No, we don't want to...

                #TrustServerCertificate Property   bool TrustServerCertificate {get;set;}
                if ($TrustServerCertificate) {
                    Write-Message -Level Debug -Message "TrustServerCertificate will be set to '$TrustServerCertificate'"
                    $sqlConnectionInfo.TrustServerCertificate = $TrustServerCertificate
                }

                #UseIntegratedSecurity  Property   bool UseIntegratedSecurity {get;set;}
                # $true is the default and it is automatically set to $false if we set a UserName, so we don't touch

                #UserName               Property   string UserName {get;set;}
                if ($authType -in 'azure ad', 'azure sql', 'local sql') {
                    Write-Message -Level Debug -Message "UserName will be set to '$username'"
                    $sqlConnectionInfo.UserName = $username
                }

                #WorkstationId          Property   string WorkstationId {get;set;}
                if ($WorkstationId) {
                    Write-Message -Level Debug -Message "WorkstationId will be set to '$WorkstationId'"
                    $sqlConnectionInfo.WorkstationId = $WorkstationId
                }

                # If we have an AccessToken, we will build a SqlConnection
                if ($AccessToken) {
                    # Check if token was created by New-DbaAzAccessToken or Get-AzAccessToken
                    Write-Message -Level Debug -Message "AccessToken detected, checking for string or PsObjectIRenewableToken"
                    if ($AccessToken | Get-Member | Where-Object Name -eq GetAccessToken) {
                        Write-Message -Level Debug -Message "Token was generated using New-DbaAzAccessToken, executing GetAccessToken()"
                        $AccessToken = $AccessToken.GetAccessToken()
                    }
                    if ($AccessToken | Get-Member | Where-Object Name -eq Token) {
                        Write-Message -Level Debug -Message "Token was generated using Get-AzAccessToken, getting .Token"
                        $AccessToken = $AccessToken.Token
                    }
                    Write-Message -Level Debug -Message "We have an AccessToken and build a SqlConnection with that token"
                    Write-Message -Level Debug -Message "But we remove 'Integrated Security=True;'"
                    # TODO: How do we get a ConnectionString without this?
                    Write-Message -Level Debug -Message "Building SqlConnection from SqlConnectionInfo.ConnectionString"
                    $connectionString = $sqlConnectionInfo.ConnectionString -replace 'Integrated Security=True;', ''
                    $sqlConnection = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnection -ArgumentList $connectionString
                    Write-Message -Level Debug -Message "SqlConnection was built"
                    $sqlConnection.AccessToken = $AccessToken
                    Write-Message -Level Debug -Message "Building ServerConnection from SqlConnection"
                    $serverConnection = New-Object -TypeName Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $sqlConnection
                    Write-Message -Level Debug -Message "ServerConnection was built"
                } else {
                    Write-Message -Level Debug -Message "Building ServerConnection from SqlConnectionInfo"
                    $serverConnection = New-Object -TypeName Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $sqlConnectionInfo
                    Write-Message -Level Debug -Message "ServerConnection was built"
                }

                if ($authType -eq 'local ad') {
                    if ($IsLinux -or $IsMacOS) {
                        Stop-Function -Target $instance -Message "Cannot use Windows credentials to connect when host is Linux or OS X. Use kinit instead. See https://github.com/dataplat/dbatools/issues/7602 for more info."
                        return
                    }
                    Write-Message -Level Debug -Message "ConnectAsUser will be set to '$true'"
                    $serverConnection.ConnectAsUser = $true

                    Write-Message -Level Debug -Message "ConnectAsUserName will be set to '$username'"
                    $serverConnection.ConnectAsUserName = $username

                    Write-Message -Level Debug -Message "ConnectAsUserPassword will be set"
                    $serverConnection.ConnectAsUserPassword = $SqlCredential.GetNetworkCredential().Password
                }

                Write-Message -Level Debug -Message "Building Server from ServerConnection"
                $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $serverConnection
                Write-Message -Level Debug -Message "Server was built"

                # Set properties of ConnectionContext that are not part of SqlConnectionInfo
                if (Test-Bound -ParameterName 'BatchSeparator') {
                    Write-Message -Level Debug -Message "Setting ConnectionContext.BatchSeparator to '$BatchSeparator'"
                    $server.ConnectionContext.BatchSeparator = $BatchSeparator
                }
                if (Test-Bound -ParameterName 'LockTimeout') {
                    Write-Message -Level Debug -Message "Setting ConnectionContext.LockTimeout to '$LockTimeout'"
                    $server.ConnectionContext.LockTimeout = $LockTimeout
                }
                if ($MultipleActiveResultSets) {
                    Write-Message -Level Debug -Message "Setting ConnectionContext.MultipleActiveResultSets to 'True'"
                    $server.ConnectionContext.MultipleActiveResultSets = $true
                }
                if (Test-Bound -ParameterName 'SqlExecutionModes') {
                    Write-Message -Level Debug -Message "Setting ConnectionContext.SqlExecutionModes to '$SqlExecutionModes'"
                    $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes
                }
                Write-Message -Level Debug -Message "Setting ConnectionContext.StatementTimeout to '$StatementTimeout'"
                $server.ConnectionContext.StatementTimeout = $StatementTimeout
            }

            $maskedConnString = Hide-ConnectionString $server.ConnectionContext.ConnectionString
            Write-Message -Level Debug -Message "The masked server.ConnectionContext.ConnectionString is $maskedConnString"

            # It doesn't matter which input we have, we pass this line and have a server SMO in $server to work with
            # It might be a brand new one or an already used one.
            # "Pooled connections are always closed directly after an operation" (so .IsOpen does not tell us anything):
            # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.common.connectionmanager.isopen?view=sql-smo-160#Microsoft_SqlServer_Management_Common_ConnectionManager_IsOpen
            # We could use .ConnectionContext.SqlConnectionObject.Open(), but we would have to check ConnectionContext.IsOpen first because it is not allowed on open connections
            # But ConnectionContext.IsOpen does not tell the truth if the instance was just shut down
            # And we don't use $server.ConnectionContext.Connect() as this would create a non pooled connection
            # Instead we run a real T-SQL command and just SELECT something to be sure we have a valid connection and let the SMO handle the connection
            Write-Message -Level Debug -Message "We connect to the instance by running SELECT 'dbatools is opening a new connection'"
            try {
                $null = $server.ConnectionContext.ExecuteWithResults("SELECT 'dbatools is opening a new connection'")
            } catch {
                if ($DedicatedAdminConnection) {
                    Write-Message -Level Warning -Message "Failed to open dedicated admin connection (DAC) to $instance. Only one DAC connection is allowed, so maybe another DAC is still open."
                }
                Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Continue
            }
            Write-Message -Level Debug -Message "We have a connected server object"

            if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue
            }

            if ($MinimumVersion -and $server.VersionMajor) {
                if ($server.VersionMajor -lt $MinimumVersion) {
                    Stop-Function -Target $instance -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                }
            }

            if ($SqlConnectionOnly) {
                $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server.ConnectionContext.SqlConnectionObject
                Write-Message -Level Debug -Message "We return only SqlConnection in server.ConnectionContext.SqlConnectionObject"
                $server.ConnectionContext.SqlConnectionObject
                continue
            }

            if (-not $server.ComputerName) {
                # To set the source of ComputerName to something else than the default use this config parameter:
                # Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'server.ComputerNamePhysicalNetBIOS'
                # Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
                # If the config parameter is not used, then there a different ways to handle the new property ComputerName
                # Rules in legacy code: Use $server.NetName, but if $server.NetName is empty or we are on Azure or Linux, use $instance.ComputerName
                $computerName = $null
                $computerNameSource = Get-DbatoolsConfigValue -FullName commands.connect-dbainstance.smo.computername.source
                if ($computerNameSource) {
                    Write-Message -Level Debug -Message "Setting ComputerName based on $computerNameSource"
                    $object, $property = $computerNameSource -split '\.'
                    $value = (Get-Variable -Name $object).Value.$property
                    if ($value) {
                        $computerName = $value
                        Write-Message -Level Debug -Message "ComputerName will be set to $computerName"
                    } else {
                        Write-Message -Level Debug -Message "No value found for ComputerName, so will use the default"
                    }
                }
                if (-not $computerName) {
                    if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        Write-Message -Level Debug -Message "We are on Azure, so server.ComputerName will be set to instance.ComputerName"
                        $computerName = $instance.ComputerName
                    } elseif ($server.HostPlatform -eq 'Linux') {
                        Write-Message -Level Debug -Message "We are on Linux what is often on docker and the internal name is not useful, so server.ComputerName will be set to instance.ComputerName"
                        $computerName = $instance.ComputerName
                    } elseif ($server.NetName) {
                        Write-Message -Level Debug -Message "We will set server.ComputerName to server.NetName"
                        $computerName = $server.NetName
                    } else {
                        Write-Message -Level Debug -Message "We will set server.ComputerName to instance.ComputerName as server.NetName is empty"
                        $computerName = $instance.ComputerName
                    }
                    Write-Message -Level Debug -Message "ComputerName will be set to $computerName"
                }
                Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $computerName -Force
            }

            if (-not $server.IsAzure) {
                Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue (Test-Azure -SqlInstance $instance) -Force
                Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                Write-Message -Level Debug -Message "We added IsAzure = '$($server.IsAzure)', DbaInstanceName = instance.InstanceName = '$($server.DbaInstanceName)', SqlInstance = server.DomainInstanceName = '$($server.SqlInstance)', NetPort = instance.Port = '$($server.NetPort)', ConnectedAs = server.ConnectionContext.TrueLogin = '$($server.ConnectedAs)'"
            }

            Write-Message -Level Debug -Message "We return the server object"
            $server

            # Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
            [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))

            # Update cache for instance names
            if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
            }

            # Update lots of registered stuff
            # Default for [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled is $true, so will not run by default
            # Must be explicitly activated with [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled = $false to run
            if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled) {
                # Variable $FullSmoName is used inside the script blocks, so we have to set
                $FullSmoName = $instance.FullSmoName.ToLowerInvariant()
                Write-Message -Level Debug -Message "Will run Invoke-TEPPCacheUpdate for FullSmoName = $FullSmoName"
                foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                    Invoke-TEPPCacheUpdate -ScriptBlock $scriptBlock
                }
            }

            # By default, SMO initializes several properties. We push it to the limit and gather a bit more
            # this slows down the connect a smidge but drastically improves overall performance
            # especially when dealing with a multitude of servers
            if ($loadedSmoVersion -ge 11 -and -not $isAzure) {
                try {
                    Write-Message -Level Debug -Message "SetDefaultInitFields will be used"
                    $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                    $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                    $initFieldsJob = New-Object System.Collections.Specialized.StringCollection
                    if ($server.VersionMajor -eq 8) {
                        # 2000
                        [void]$initFieldsDb.AddRange($Fields2000_Db)
                        [void]$initFieldsLogin.AddRange($Fields2000_Login)
                    } elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10) {
                        # 2005 and 2008
                        [void]$initFieldsDb.AddRange($Fields200x_Db)
                        [void]$initFieldsLogin.AddRange($Fields200x_Login)
                    } else {
                        # 2012 and above
                        [void]$initFieldsDb.AddRange($Fields201x_Db)
                        [void]$initFieldsLogin.AddRange($Fields201x_Login)
                    }
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                    #see 7753
                    [void]$initFieldsJob.AddRange($Fields_Job)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Agent.Job], $initFieldsJob)
                } catch {
                    Write-Message -Level Debug -Message "SetDefaultInitFields failed with $_"
                    # perhaps a DLL issue, continue going
                }
            }

            $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server
            Write-Message -Level Debug -Message "We are finished with this instance"
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUIwzH4hz4S4DIb7DnGP0AhYAG
# xKigghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFNKBwYt06wRZU4CLnEGYVDe03xjSMA0G
# CSqGSIb3DQEBAQUABIIBAHmS8bP9FBQKT6klMeOFoor3ZVrBJCety1gQmzhP7Oyx
# bfgzn6spp0gIKbYGOqWQsqurnCEpD75XZOUzj3Jad9/lghb/TSGB8y3n/O6elVW1
# qAx6FRSw0eAMrYWt5pON/fB+pbg+AUwE7CTvcAmuYHJOHTO6aHeJF46h3SkMhaol
# xTmOZFy7+GQvaM8SAmLXegfOwvE7UjtJDO75d4MbJ7038celjIe6HA8pz6J0gMyk
# DsaCgmkRQdA+y8Tv84U/GaRvw728xC8fJj3zvgvmTzfFi+LxLgzNQ7JKNyBrWYm4
# jUCZvJz3kx+45ZfW6KxvHEljvl1YeCAWU7BYg2NhJFOhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzEwWjAvBgkqhkiG9w0BCQQxIgQgFaa1c3sdFDMjxTwYM4Aq
# dw4SS98DHRBVdZdcKI28OMowDQYJKoZIhvcNAQEBBQAEggIAZC1TJRq7lnqvqb73
# wnH+/hJ4ad4m7lGPykawVgDIuTm8YES2pzSGsDLeK1sjLYtuAbZufcH6sgFcjULv
# ybP2/Drr1g9wA6gNLZuL7+0wvvRI38lnr29zzILXWwEO7+nmb6ijrFYxoO3mVJEp
# E+N999urpsiDyGnsm1of/Cg3mEpAxs5hxI/Z6yahH/hkzb6nvGNhXGXzEh/zTFfm
# uznuTLqpJq+0cLS2PUXU61TSStOPCcRf98EsxD9pAPIFw47fjCRU3zcPvo4f1UZN
# prlDyvyXHV/qw5UHlGVPtwjnRDn2xxR9/nZFEMn3ZA8cS5e0ac+G2VEWgk726pj3
# 77JnAQffY55CRXxS39QDotQoPDt4GhZLFBPnq4t9ksgjP5FYzMndjjAZVpS14bli
# l3LYFpAiel6ynrettTTzva34b6M+44nK7B4YvrngN1udp4tJwwI4IGe4+VHKDVjR
# Xs7is+i4hqqAu1T7CxjkYnrRqDQkGiPDzR21vFS0qXYP2I/GRjRnpvt8bqPeyEAe
# uJxwNctr920n7u32xtE/7Toj5Jd7JIEiqtSCpLV44FUUwTFrXAR8GlAC/rB6e1Cr
# KtW7TuWTXh09LTwks2kZk/e8iQDP5pNKGGVl0gvODuIaWfbMS2JKoqBVi0WuiaB2
# ybKcI6JgNDwv3Bra3xvifSI8c3A=
# SIG # End signature block
