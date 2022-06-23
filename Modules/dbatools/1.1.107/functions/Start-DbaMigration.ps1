function Start-DbaMigration {
    <#
    .SYNOPSIS
        Migrates SQL Server *ALL* databases, logins, database mail profiles/accounts, credentials, SQL Agent objects, linked servers,
        Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
        system triggers and backup devices from one SQL Server to another.

        For more granular control, please use Exclude or use the other functions available within the dbatools module.

    .DESCRIPTION
        Start-DbaMigration consolidates most of the migration tools in dbatools into one command.  This is useful when you're looking to migrate entire instances. It less flexible than using the underlying functions. Think of it as an easy button. It migrates:

        All user databases to exclude support databases such as ReportServerTempDB (Use -IncludeSupportDbs for this). Use -Exclude Databases to skip.
        All logins. Use -Exclude Logins to skip.
        All database mail objects. Use -Exclude DatabaseMail
        All credentials. Use -Exclude Credentials to skip.
        All objects within the Job Server (SQL Agent). Use -Exclude AgentServer to skip.
        All linked servers. Use -Exclude LinkedServers to skip.
        All groups and servers within Central Management Server. Use -Exclude CentralManagementServer to skip.
        All SQL Server configuration objects (everything in sp_configure). Use -Exclude SpConfigure to skip.
        All user objects in system databases. Use -Exclude SysDbUserObjects to skip.
        All system triggers. Use -Exclude SystemTriggers to skip.
        All system backup devices. Use -Exclude BackupDevices to skip.
        All Audits. Use -Exclude Audits to skip.
        All Endpoints. Use -Exclude Endpoints to skip.
        All Extended Events. Use -Exclude ExtendedEvents to skip.
        All Policy Management objects. Use -Exclude PolicyManagement to skip.
        All Resource Governor objects. Use -Exclude ResourceGovernor to skip.
        All Server Audit Specifications. Use -Exclude ServerAuditSpecifications to skip.
        All Custom Errors (User Defined Messages). Use -Exclude CustomErrors to skip.
        All Data Collector collection sets. Does not configure the server. Use -Exclude DataCollector to skip.
        All startup procedures. Use -Exclude StartupProcedures to skip.

        This script provides the ability to migrate databases using detach/copy/attach or backup/restore. SQL Server logins, including passwords, SID and database/server roles can also be migrated. In addition, job server objects can be migrated and server configuration settings can be exported or migrated. This script works with named instances, clusters and SQL Express.

        By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

    .PARAMETER Source
        Source SQL Server.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You may specify multiple servers.

        Note that when using -BackupRestore with multiple servers, the backup will only be performed once and backups will be deleted at the end.

        When using -DetachAttach with multiple servers, -Reattach must be specified.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER BackupRestore
        If this switch is enabled, the Copy-Only backup and restore method is used to perform database migrations. You must specify -SharedPath with a valid UNC format as well (\\server\share).

    .PARAMETER SharedPath
        Specifies the network location for the backup files. The SQL Server service accounts on both Source and Destination must have read/write permission to access this location.

    .PARAMETER WithReplace
        If this switch is enabled, databases are restored from backup using WITH REPLACE. This is useful if you want to stage some complex file paths.

    .PARAMETER ReuseSourceFolderStructure
        If this switch is enabled, the data and log directory structures on Source will be kept on Destination. Otherwise, databases will be migrated to Destination's default data and log directories.

        Consider this if you're migrating between different versions and use part of Microsoft's default SQL structure (MSSQL12.INSTANCE, etc.).

    .PARAMETER DetachAttach
        If this switch is enabled, the the detach/copy/attach method is used to perform database migrations. No files are deleted on Source. If the destination attachment fails, the source database will be reattached. File copies are performed over administrative shares (\\server\x$\mssql) using BITS. If a database is being mirrored, the mirror will be broken prior to migration.

    .PARAMETER Reattach
        If this switch is enabled, all databases are reattached to Source after a DetachAttach migration is complete.

    .PARAMETER NoRecovery
        If this switch is enabled, databases will be left in the No Recovery state to enable further backups to be added.

    .PARAMETER IncludeSupportDbs
        If this switch is enabled, the ReportServer, ReportServerTempDb, SSIDb, and distribution databases will be migrated if they exist. A logfile named $SOURCE-$DESTINATION-$date-Sqls.csv will be written to the current directory. Requires -BackupRestore or -DetachAttach.

    .PARAMETER SetSourceReadOnly
        If this switch is enabled, all migrated databases will be set to ReadOnly on the source instance prior to detach/attach & backup/restore. If -Reattach is specified, the database is set to read-only after reattaching.

    .PARAMETER AzureCredential
        Name of the AzureCredential if SharedPath is Azure page blob

    .PARAMETER Exclude
        Exclude one or more objects to migrate

        Databases
        Logins
        AgentServer
        Credentials
        LinkedServers
        SpConfigure
        CentralManagementServer
        DatabaseMail
        SysDbUserObjects
        SystemTriggers
        BackupDevices
        Audits
        Endpoints
        ExtendedEvents
        PolicyManagement
        ResourceGovernor
        ServerAuditSpecifications
        CustomErrors
        DataCollector
        StartupProcedures
        AgentServerProperties
        MasterCertificates

    .PARAMETER ExcludeSaRename
        If this switch is enabled, the sa account will not be renamed on the destination instance to match the source.

    .PARAMETER DisableJobsOnDestination
        If this switch is enabled, migrated SQL Agent jobs will be disabled on the destination instance.

    .PARAMETER DisableJobsOnSource
        If this switch is enabled, SQL Agent jobs will be disabled on the source instance.

    .PARAMETER UseLastBackup
        Use the last full, diff and logs instead of performing backups. Note that the backups must exist in a location accessible by all destination servers, such a network share.

    .PARAMETER Continue
        If specified, will to attempt to restore transaction log backups on top of existing database(s) in Recovering or Standby states. Only usable with -UseLastBackup

    .PARAMETER KeepCDC
        Indicates whether CDC information should be copied as part of the database

    .PARAMETER KeepReplication
        Indicates whether replication configuration should be copied as part of the database copy operation

    .PARAMETER MasterKeyPassword
        The password to encrypt a master key if one is required. This must be a SecureString.

    .PARAMETER Force
        If migrating users, forces drop and recreate of SQL and Windows logins.
        If migrating databases, deletes existing databases with matching names.
        If using -DetachAttach, -Force will break mirrors and drop dbs from Availability Groups.

        For other migration objects, it will just drop existing items and readd, if -force is supported within the underlying function.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Start-DbaMigration

    .EXAMPLE
        PS C:\> Start-DbaMigration -Source sqlserver\instance -Destination sqlcluster -DetachAttach

        All databases, logins, job objects and sp_configure options will be migrated from sqlserver\instance to sqlcluster. Databases will be migrated using the detach/copy files/attach method. Dbowner will be updated. User passwords, SIDs, database roles and server roles will be migrated along with the login.

    .EXAMPLE
        PS C:\> $params = @{
        >> Source = "sqlcluster"
        >> Destination = "sql2016"
        >> SourceSqlCredential = $scred
        >> DestinationSqlCredential = $cred
        >> SharedPath = "\\fileserver\share\sqlbackups\Migration"
        >> BackupRestore = $true
        >> ReuseSourceFolderStructure = $true
        >> Force = $true
        >> }
        >>
        PS C:\> Start-DbaMigration @params -Verbose

        Utilizes splatting technique to set all the needed parameters. This will migrate databases using the backup/restore method. It will also include migration of the logins, database mail configuration, credentials, SQL Agent, Central Management Server, and SQL Server global configuration.

    .EXAMPLE
        PS C:\> Start-DbaMigration -Verbose -Source sqlcluster -Destination sql2016 -DetachAttach -Reattach -SetSourceReadonly

        Migrates databases using detach/copy/attach. Reattach at source and set source databases read-only. Also migrates everything else.

    .EXAMPLE
        PS C:\> $PSDefaultParameters = @{
        >> "dbatools:Source" = "sqlcluster"
        >> "dbatools:Destination" = "sql2016"
        >> }
        >>
        PS C:\> Start-DbaMigration -Verbose -Exclude Databases, Logins

        Utilizes the PSDefaultParameterValues system variable, and sets the Source and Destination parameters for any function in the module that has those parameter names. This prevents the need from passing them in constantly.
        The execution of the function will migrate everything but logins and databases.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter]$Source,
        [DbaInstanceParameter[]]$Destination,
        [switch]$DetachAttach,
        [switch]$Reattach,
        [switch]$BackupRestore,
        [parameter(HelpMessage = "Specify a valid network share in the format \\server\share that can be accessed by your account and both Sql Server service accounts, or a URL to an Azure Storage account")]
        [string]$SharedPath,
        [switch]$WithReplace,
        [switch]$NoRecovery,
        [switch]$SetSourceReadOnly,
        [switch]$ReuseSourceFolderStructure,
        [switch]$IncludeSupportDbs,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [ValidateSet('Databases', 'Logins', 'AgentServer', 'Credentials', 'LinkedServers', 'SpConfigure', 'CentralManagementServer', 'DatabaseMail', 'SysDbUserObjects', 'SystemTriggers', 'BackupDevices', 'Audits', 'Endpoints', 'ExtendedEvents', 'PolicyManagement', 'ResourceGovernor', 'ServerAuditSpecifications', 'CustomErrors', 'DataCollector', 'StartupProcedures', 'AgentServerProperties', 'MasterCertificates')]
        [string[]]$Exclude,
        [switch]$DisableJobsOnDestination,
        [switch]$DisableJobsOnSource,
        [switch]$ExcludeSaRename,
        [switch]$UseLastBackup,
        [switch]$KeepCDC,
        [switch]$KeepReplication,
        [switch]$Continue,
        [switch]$Force,
        [string]$AzureCredential,
        [Security.SecureString]$MasterKeyPassword,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Exclude -notcontains "Databases") {
            if (-not $BackupRestore -and -not $DetachAttach -and -not $UseLastBackup) {
                Stop-Function -Message "You must specify a database migration method (-BackupRestore or -DetachAttach) or -Exclude Databases"
                return
            }
        }
        if ($DetachAttach -and ($BackupRestore -or $UseLastBackup)) {
            Stop-Function -Message "-DetachAttach cannot be used with -BackupRestore or -UseLastBackup"
            return
        }
        if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup"
            return
        }
        if ($SharedPath -and $UseLastBackup) {
            Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups"
            return
        }
        if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
            Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source"
            return
        }
        if ($Continue -and -not $UseLastBackup) {
            Stop-Function -Message "-Continue cannot be used without -UseLastBackup"
            return
        }
        if ($UseLastBackup -and -not $BackupRestore) {
            $BackupRestore = $true
        }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date
        $stepCounter = 0
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # testing twice for whatif reasons
        if ($Exclude -notcontains "Databases") {
            if (-not $BackupRestore -and -not $DetachAttach -and -not $UseLastBackup) {
                Stop-Function -Message "You must specify a database migration method (-BackupRestore or -DetachAttach) or -Exclude Databases"
                return
            }
        }

        if ($DetachAttach -and ($BackupRestore -or $UseLastBackup)) {
            Stop-Function -Message "-DetachAttach cannot be used with -BackupRestore or -UseLastBackup"
            return
        }
        if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup"
            return
        }
        if ($SharedPath -like 'https*' -and $DetachAttach) {
            Stop-Function -Message "URL shared storage is only supported by BackupRstore"
            return
        }
        if ($SharedPath -and $UseLastBackup) {
            Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups"
            return
        }
        if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
            Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source"
            return
        }
        if ($Continue -and -not $UseLastBackup) {
            Stop-Function -Message "-Continue cannot be used without -UseLastBackup"
            return
        }
        if ($UseLastBackup -and -not $BackupRestore) {
            $BackupRestore = $true
        }

        try {
            $sourceserver = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if ($Exclude -notcontains 'SpConfigure') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating SQL Server Configuration"
            Write-Message -Level Verbose -Message "Migrating SQL Server Configuration"
            Copy-DbaSpConfigure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }

        if ($Exclude -notcontains 'MasterCertificates') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Copying certificates in the master database"
            Write-Message -Level Verbose -Message "Copying certificates in the master database"
            Copy-DbaDbCertificate -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -EncryptionPassword (Get-RandomPassword) -MasterKeyPassword $MasterKeyPassword -Database master -SharedPath $SharedPath

        }

        if ($Exclude -notcontains 'CustomErrors') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating custom errors (user defined messages)"
            Write-Message -Level Verbose -Message "Migrating custom errors (user defined messages)"
            Copy-DbaCustomError -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Credentials') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating SQL credentials"
            Write-Message -Level Verbose -Message "Migrating SQL credentials"
            Copy-DbaCredential -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'DatabaseMail') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating database mail"
            Write-Message -Level Verbose -Message "Migrating database mail"
            Copy-DbaDbMail -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'CentralManagementServer') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Central Management Server"
            Write-Message -Level Verbose -Message "Migrating Central Management Server"
            Copy-DbaRegServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'BackupDevices') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Backup Devices"
            Write-Message -Level Verbose -Message "Migrating Backup Devices"
            Copy-DbaBackupDevice -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'SystemTriggers') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating System Triggers"
            Write-Message -Level Verbose -Message "Migrating System Triggers"
            Copy-DbaInstanceTrigger -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Databases') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating databases"
            Write-Message -Level Verbose -Message "Migrating databases"
            if ($BackupRestore) {
                if ($UseLastBackup) {
                    Copy-DbaDatabase -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -AllDatabases -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -BackupRestore -Force:$Force -NoRecovery:$NoRecovery -WithReplace:$WithReplace -IncludeSupportDbs:$IncludeSupportDbs -UseLastBackup:$UseLastBackup -Continue:$Continue -KeepCDC:$KeepCDC -KeepReplication:$KeepReplication
                } else {
                    Copy-DbaDatabase -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -AllDatabases -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -BackupRestore -SharedPath $SharedPath -Force:$Force -NoRecovery:$NoRecovery -WithReplace:$WithReplace -IncludeSupportDbs:$IncludeSupportDbs -AzureCredential $AzureCredential -KeepCDC:$KeepCDC -KeepReplication:$KeepReplication
                }
            } else {
                Copy-DbaDatabase -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -AllDatabases -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -DetachAttach:$DetachAttach -Reattach:$Reattach -Force:$Force -IncludeSupportDbs:$IncludeSupportDbs -KeepCDC:$KeepCDC -KeepReplication:$KeepReplication
            }
        }

        if ($Exclude -notcontains 'Logins') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating logins"
            Write-Message -Level Verbose -Message "Migrating logins"
            $syncit = $ExcludeSaRename -eq $false
            Copy-DbaLogin -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force -SyncSaName:$syncit
        }

        if ($Exclude -notcontains 'Logins' -and $Exclude -notcontains 'Databases' -and -not $NoRecovery) {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Updating database owners to match newly migrated logins"
            Write-Message -Level Verbose -Message "Updating database owners to match newly migrated logins"
            foreach ($dest in $Destination) {
                $null = Update-SqlDbOwner -Source $sourceserver -Destination $dest -DestinationSqlCredential $DestinationSqlCredential
            }
        }

        if ($Exclude -notcontains 'LinkedServers') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating linked servers"
            Write-Message -Level Verbose -Message "Migrating linked servers"
            Copy-DbaLinkedServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'DataCollector') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Data Collector collection sets"
            Write-Message -Level Verbose -Message "Migrating Data Collector collection sets"
            Copy-DbaDataCollector -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Audits') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Audits"
            Write-Message -Level Verbose -Message "Migrating Audits"
            Copy-DbaInstanceAudit -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ServerAuditSpecifications') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Server Audit Specifications"
            Write-Message -Level Verbose -Message "Migrating Server Audit Specifications"
            Copy-DbaInstanceAuditSpecification -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Endpoints') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Endpoints"
            Write-Message -Level Verbose -Message "Migrating Endpoints"
            Copy-DbaEndpoint -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'PolicyManagement') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Policy Management"
            Write-Message -Level Verbose -Message "Migrating Policy Management"
            Copy-DbaPolicyManagement -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ResourceGovernor') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Resource Governor"
            Write-Message -Level Verbose -Message "Migrating Resource Governor"
            Copy-DbaResourceGovernor -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'SysDbUserObjects') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating user objects in system databases (this can take a second)"
            Write-Message -Level Verbose -Message "Migrating user objects in system databases (this can take a second)."
            If ($Pscmdlet.ShouldProcess($destination, "Copying user objects.")) {
                Copy-DbaSysDbUserObject -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$force
            }
        }

        if ($Exclude -notcontains 'ExtendedEvents') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Extended Events"
            Write-Message -Level Verbose -Message "Migrating Extended Events"
            Copy-DbaXESession -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'AgentServer') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating job server"
            Write-Message -Level Verbose -Message "Migrating job server"
            $ExcludeAgentServerProperties = $Exclude -contains 'AgentServerProperties'
            Copy-DbaAgentServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -DisableJobsOnDestination:$DisableJobsOnDestination -DisableJobsOnSource:$DisableJobsOnSource -Force:$Force -ExcludeServerProperties:$ExcludeAgentServerProperties
        }

        if ($Exclude -notcontains 'StartupProcedures') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating startup procedures"
            Write-Message -Level Verbose -Message "Migrating startup procedures"
            Copy-DbaStartupProcedure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        $totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
        Write-Message -Level Verbose -Message "SQL Server migration complete."
        Write-Message -Level Verbose -Message "Migration started: $started"
        Write-Message -Level Verbose -Message "Migration completed: $(Get-Date)"
        Write-Message -Level Verbose -Message "Total Elapsed time: $totaltime"
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCChXwT4/8iyLyfS
# POsG7wqJKP7WbhPuYfJ2srk55Ve+ZKCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAWsZkR9SjhqAYgLYCiZfj7CUZm+zbKMUD4
# imhSYN4OQTANBgkqhkiG9w0BAQEFAASCAQCMk/mddc23vqJj9z7ho/xLjeY/+FAe
# NNCxrUDUpQ2DD2ENRivfQLaEytVMXIH9tXPU9MKBlm+QmJJRAGIyry/DiTFRNDwS
# 2YX+KU0IidfJFJN/pLaA+AQyYG/+XFz3/vFHGAxCwDz8xCUiv6tG5eWFd8O4vZ+6
# G7myfYdwAYNs1W3+AR4QvEp2OqQfHwkMINIFEDj61POXEs+TKbU5G9D36dDTonWP
# +Gi101/BrWbFvFAZqds6RtRCpwsACvJiCCfLVS8xZz3CEt+GD1dci+ETdDOV3VP1
# 9sRJmoe8vo3mi1hSjqyKrIMD/8v42q/uhrVq3IcMKeCWFe9Mh0mwzCBEoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQwMVowLwYJKoZIhvcNAQkEMSIEIADlT7QU
# XQHxMeCtZ1fbw01PuiOLPZu/baTTI5hFNKBZMA0GCSqGSIb3DQEBAQUABIICAIo1
# BHk0JM2W9KRK9+4jTc/V9mwnzJ8fKUOGhkgC14crqlq2E7I1LMstyU6PjRpIXG6j
# pVb5qmRIOd+SiHk5HMmgakpvA75hIHepj7eXgAVapTnspzS6tQPHskPdgrGwvU33
# nWYOlWuAPSlB2+qzBPuAypgEJT1dUNs2st2zelmgVDe0tiig/UpFVCTKTYAoPx98
# NosL2OwHh9s2IM12mtkesfcWbJyyshMygdLVgFuCWjdG7C4eXfWySWY7NW1U7e+1
# tmd+cqghKn0KUCQE0NmfeiAtFAOq3ictd5Q12yHm8nD0tJIh5ZxGJ6/mXdjoXVPA
# ryK6cfqY2lhRyqy6kjhVEOgt9wWKfYOnio4tqaTP9uqthIPifcPhEe5oSIYdR5/P
# FAD58TGNtQlWaZnUxDzkr1tkoYmwsM+4kKsy03sbm07QVrDcTnFwre4mGt9ESFWl
# 19BhnDT92ef0icLLEcl2TkqhznlH/6QoFSPKa9rJR7q+SmqXJQOB7KhuXynNyeKy
# efuzMjazcLHOSOCTheiMV8e2urcyZy1kI6inpUaBgiFJlj3V2qQUEi8qNrbruR9n
# cKxdW5uOnjzYp2UqKldVARpQMAHdUOexCW6YEq84gmU9AETkz7Be+OvRvuHPP5sg
# RTljjQZS3ucbIoexa6k6X0LPI1J/XYHFEWW80zdW
# SIG # End signature block
