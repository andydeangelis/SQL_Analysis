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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUZTW3eGxyabO3qcUzBFLcIBJa
# 9oGgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFCKFMcuCL+8bc1DcBej9MbJhzzOAMA0G
# CSqGSIb3DQEBAQUABIIBAIySfUJTarEA0GEk2r9COPVVhza2Fy1sgY/4ZSHeal1E
# 2OPY3di0uH4ipMvnRO/IWuaWkbrqanrTNDPZyk00LjVHRps6o8Y0EAPEb5wY/Rh4
# vAFw+anlPuc4wK+IkdaJ2AcHziGdwSLu0IaKwN+Kx+iKxAxgFuR8K2WIYyASv8hW
# sn3ofauqo6Z3ffNnXHoR7Fwhs4f0iE6ZGYWLThjXQO/v6C9dYdqkOboOUkvh47OU
# +JgwznJuPADVwtIQR+5Y4+w+JBpqVS7d1YJ8feX9JCCEOMeDEgHzRnCriOTdqy/O
# myNX4dpkUgqpb69FNxVAO71FDYvp6y97Se5ZioaXolihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDI0WjAvBgkqhkiG9w0BCQQxIgQgKm5HTQK8CaIL+P9Tlf7h
# eCNWIkA0Iu0EquKoPzN5SbowDQYJKoZIhvcNAQEBBQAEggIADU+ZnQyx3PYaLaug
# UeibbBjlbbfmztU+sZ7dCkJWWDeLd1m0/rzgpxCBahbkK0gT09pptM0HPgpUCle/
# 5uwaMagg0Rq+5ObUU9igbxj9u0vLd7W0vSo+whI7Vg30gcPt4Lc9QUdmLs+b854Y
# WI604Cpfo8+bxs2W0Zw4t5P4ELCH8AGWhQlXHOcSnQJAGsMhiSYHIlFUiLXwXhgZ
# BSyMfQT28oufg3xX4I5qH9HFVO+1qm2IBYqt5fcmjjFQKcSe6c9B5U8bWVa8aL+t
# fCLoCbIrDHLgLNbUVGA/yPz18Vot77dlr4I6kGvFZ845sJkFGG3RpC26pAJhorvK
# pD/Dj8gbV0SeoxR5DLDilTq/8BXopR0oX8s6D7nYBfOOHYYKx0XkHQXdL8O64JRi
# qKjuxo+2w5daFqt8WVAJRg323AN8W6BidlrkJdghZxnx/gxsB9cUeQNvaJqpAf/g
# u/zsHMbOHVw0XOF3Kjq2QBeyRMrUCs34mghPMHEXq0WJFTLxZ7U7FDic/HH2Eo8A
# owP2gnaFrcOTmh707ewOeqqpH2j5T5QwFodz+DK0ccNIzFqE28nCQEv0/HFl9la9
# 6dHNqFqFfMHbDvNkmEbki/ZLCjdGl2VV/cXzV4Kh4kMTfq7jFECW9NCgx85GNqB2
# JzXfkkyITcwyMmiota0DMXZB13U=
# SIG # End signature block
