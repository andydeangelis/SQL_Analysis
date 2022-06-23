function Invoke-DbaDbLogShipping {
    <#
    .SYNOPSIS
        Invoke-DbaDbLogShipping sets up log shipping for one or more databases

    .DESCRIPTION
        Invoke-DbaDbLogShipping helps to easily set up log shipping for one or more databases.

        This function will make a lot of decisions for you assuming you want default values like a daily interval for the schedules with a 15 minute interval on the day.
        There are some settings that cannot be made by the function and they need to be prepared before the function is executed.

        The following settings need to be made before log shipping can be initiated:
        - Backup destination (the folder and the privileges)
        - Copy destination (the folder and the privileges)

        * Privileges
        Make sure your agent service on both the primary and the secondary instance is an Active Directory account.
        Also have the credentials ready to set the folder permissions

        ** Network share
        The backup destination needs to be shared and have the share privileges of FULL CONTROL to Everyone.

        ** NTFS permissions
        The backup destination must have at least read/write permissions for the primary instance agent account.
        The backup destination must have at least read permissions for the secondary instance agent account.
        The copy destination must have at least read/write permission for the secondary instance agent acount.

    .PARAMETER SourceSqlInstance
        Source SQL Server instance which contains the databases to be log shipped.
        You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER DestinationSqlInstance
        Destination SQL Server instance which contains the databases to be log shipped.
        You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SourceCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Database to set up log shipping for.

    .PARAMETER SharedPath
        The backup unc path to place the backup files. This is the root directory.
        A directory with the name of the database will be created in this path.

    .PARAMETER LocalPath
        If the backup path is locally for the source server you can also set this value.

    .PARAMETER BackupJob
        Name of the backup that will be created in the SQL Server agent.
        The parameter works as a prefix where the name of the database will be added to the backup job name.
        The default is "LSBackup_[databasename]"

    .PARAMETER BackupRetention
        The backup retention period in minutes. Default is 4320 / 72 hours

    .PARAMETER BackupSchedule
        Name of the backup schedule created for the backup job.
        The parameter works as a prefix where the name of the database will be added to the backup job schedule name.
        Default is "LSBackupSchedule_[databasename]"

    .PARAMETER BackupScheduleDisabled
        Parameter to set the backup schedule to disabled upon creation.
        By default the schedule is enabled.

    .PARAMETER BackupScheduleFrequencyType
        A value indicating when a job is to be executed.
        Allowed values are "Daily", "AgentStart", "IdleComputer"

    .PARAMETER BackupScheduleFrequencyInterval
        The number of type periods to occur between each execution of the backup job.

    .PARAMETER BackupScheduleFrequencySubdayType
        Specifies the units for the sub-day FrequencyInterval.
        Allowed values are "Time", "Seconds", "Minutes", "Hours"

    .PARAMETER BackupScheduleFrequencySubdayInterval
        The number of sub-day type periods to occur between each execution of the backup job.

    .PARAMETER BackupScheduleFrequencyRelativeInterval
        A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

    .PARAMETER BackupScheduleFrequencyRecurrenceFactor
        The number of weeks or months between the scheduled execution of a job. FrequencyRecurrenceFactor is used only if FrequencyType is 8, "Weekly", 16, "Monthly", 32 or "MonthlyRelative".

    .PARAMETER BackupScheduleStartDate
        The date on which execution of a job can begin.

    .PARAMETER BackupScheduleEndDate
        The date on which execution of a job can stop.

    .PARAMETER BackupScheduleStartTime
        The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

    .PARAMETER BackupScheduleEndTime
        The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

    .PARAMETER BackupThreshold
        Is the length of time, in minutes, after the last backup before a threshold alert error is raised.
        The default is 60.

    .PARAMETER CompressBackup
        Do the backups need to be compressed. By default the backups are not compressed.

    .PARAMETER CopyDestinationFolder
        The path to copy the transaction log backup files to. This is the root directory.
        A directory with the name of the database will be created in this path.

    .PARAMETER CopyJob
        Name of the copy job that will be created in the SQL Server agent.
        The parameter works as a prefix where the name of the database will be added to the copy job name.
        The default is "LSBackup_[databasename]"

    .PARAMETER CopyRetention
        The copy retention period in minutes. Default is 4320 / 72 hours

    .PARAMETER CopySchedule
        Name of the backup schedule created for the copy job.
        The parameter works as a prefix where the name of the database will be added to the copy job schedule name.
        Default is "LSCopy_[DestinationServerName]_[DatabaseName]"

    .PARAMETER CopyScheduleDisabled
        Parameter to set the copy schedule to disabled upon creation.
        By default the schedule is enabled.

    .PARAMETER CopyScheduleFrequencyType
        A value indicating when a job is to be executed.
        Allowed values are "Daily", "AgentStart", "IdleComputer"

    .PARAMETER CopyScheduleFrequencyInterval
        The number of type periods to occur between each execution of the copy job.

    .PARAMETER CopyScheduleFrequencySubdayType
        Specifies the units for the subday FrequencyInterval.
        Allowed values are "Time", "Seconds", "Minutes", "Hours"

    .PARAMETER CopyScheduleFrequencySubdayInterval
        The number of subday type periods to occur between each execution of the copy job.

    .PARAMETER CopyScheduleFrequencyRelativeInterval
        A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

    .PARAMETER CopyScheduleFrequencyRecurrenceFactor
        The number of weeks or months between the scheduled execution of a job. FrequencyRecurrenceFactor is used only if FrequencyType is 8, "Weekly", 16, "Monthly", 32 or "MonthlyRelative".

    .PARAMETER CopyScheduleStartDate
        The date on which execution of a job can begin.

    .PARAMETER CopyScheduleEndDate
        The date on which execution of a job can stop.

    .PARAMETER CopyScheduleStartTime
        The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

    .PARAMETER CopyScheduleEndTime
        The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

    .PARAMETER DisconnectUsers
        If this parameter is set in combinations of standby the users will be disconnected during restore.

    .PARAMETER FullBackupPath
        Path to an existing full backup. Use this when an existing backup needs to used to initialize the database on the secondary instance.

    .PARAMETER GenerateFullBackup
        If the database is not initialized on the secondary instance it can be done by creating a new full backup and
        restore it for you.

    .PARAMETER HistoryRetention
        Is the length of time in minutes in which the history is retained.
        The default value is 14420

    .PARAMETER NoRecovery
        If this parameter is set the database will be in recovery mode. The database will not be readable.
        This setting is default.

    .PARAMETER NoInitialization
        If this parameter is set the secondary database will not be initialized.
        The database needs to be on the secondary instance in recovery mode.

    .PARAMETER PrimaryMonitorServer
        Is the name of the monitor server for the primary server.
        The default is the name of the primary sql server.

    .PARAMETER PrimaryMonitorCredential
        Allows you to login to enter a secure credential. Only needs to be used when the PrimaryMonitorServerSecurityMode is 0 or "sqlserver"
        To use: $scred = Get-Credential, then pass $scred object to the -PrimaryMonitorCredential parameter.

    .PARAMETER PrimaryMonitorServerSecurityMode
        The security mode used to connect to the monitor server for the primary server. Allowed values are 0, "sqlserver", 1, "windows"
        The default is 1 or Windows.

    .PARAMETER PrimaryThresholdAlertEnabled
        Enables the Threshold alert for the primary database

    .PARAMETER RestoreDataFolder
        Folder to be used to restore the database data files. Only used when parameter GenerateFullBackup or UseExistingFullBackup are set.
        If the parameter is not set the default data folder of the secondary instance will be used.
        If the folder is set but doesn't exist we will try to create the folder.

    .PARAMETER RestoreLogFolder
        Folder to be used to restore the database log files. Only used when parameter GenerateFullBackup or UseExistingFullBackup are set.
        If the parameter is not set the default transaction log folder of the secondary instance will be used.
        If the folder is set but doesn't exist we will try to create the folder.

    .PARAMETER RestoreDelay
        In case a delay needs to be set for the restore.
        The default is 0.

    .PARAMETER RestoreAlertThreshold
        The amount of minutes after which an alert will be raised is no restore has taken place.
        The default is 45 minutes.

    .PARAMETER RestoreJob
        Name of the restore job that will be created in the SQL Server agent.
        The parameter works as a prefix where the name of the database will be added to the restore job name.
        The default is "LSRestore_[databasename]"

    .PARAMETER RestoreRetention
        The backup retention period in minutes. Default is 4320 / 72 hours

    .PARAMETER RestoreSchedule
        Name of the backup schedule created for the restore job.
        The parameter works as a prefix where the name of the database will be added to the restore job schedule name.
        Default is "LSRestore_[DestinationServerName]_[DatabaseName]"

    .PARAMETER RestoreScheduleDisabled
        Parameter to set the restore schedule to disabled upon creation.
        By default the schedule is enabled.

    .PARAMETER RestoreScheduleFrequencyType
        A value indicating when a job is to be executed.
        Allowed values are "Daily", "AgentStart", "IdleComputer"

    .PARAMETER RestoreScheduleFrequencyInterval
        The number of type periods to occur between each execution of the restore job.

    .PARAMETER RestoreScheduleFrequencySubdayType
        Specifies the units for the subday FrequencyInterval.
        Allowed values are "Time", "Seconds", "Minutes", "Hours"

    .PARAMETER RestoreScheduleFrequencySubdayInterval
        The number of subday type periods to occur between each execution of the restore job.

    .PARAMETER RestoreScheduleFrequencyRelativeInterval
        A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

    .PARAMETER RestoreScheduleFrequencyRecurrenceFactor
        The number of weeks or months between the scheduled execution of a job. FrequencyRecurrenceFactor is used only if FrequencyType is 8, "Weekly", 16, "Monthly", 32 or "MonthlyRelative".

    .PARAMETER RestoreScheduleStartDate
        The date on which execution of a job can begin.

    .PARAMETER RestoreScheduleEndDate
        The date on which execution of a job can stop.

    .PARAMETER RestoreScheduleStartTime
        The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

    .PARAMETER RestoreScheduleEndTime
        The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

    .PARAMETER RestoreThreshold
        The number of minutes allowed to elapse between restore operations before an alert is generated.
        The default value = 45

    .PARAMETER SecondaryDatabasePrefix
        The secondary database can be renamed to include a prefix.

    .PARAMETER SecondaryDatabaseSuffix
        The secondary database can be renamed to include a suffix.

    .PARAMETER SecondaryMonitorServer
        Is the name of the monitor server for the secondary server.
        The default is the name of the secondary sql server.

    .PARAMETER SecondaryMonitorCredential
        Allows you to login to enter a secure credential. Only needs to be used when the SecondaryMonitorServerSecurityMode is 0 or "sqlserver"
        To use: $scred = Get-Credential, then pass $scred object to the -SecondaryMonitorCredential parameter.

    .PARAMETER SecondaryMonitorServerSecurityMode
        The security mode used to connect to the monitor server for the secondary server. Allowed values are 0, "sqlserver", 1, "windows"
        The default is 1 or Windows.

    .PARAMETER SecondaryThresholdAlertEnabled
        Enables the Threshold alert for the secondary database

    .PARAMETER Standby
        If this parameter is set the database will be set to standby mode making the database readable.
        If not set the database will be in recovery mode.

    .PARAMETER StandbyDirectory
        Directory to place the standby file(s) in

    .PARAMETER UseExistingFullBackup
        If the database is not initialized on the secondary instance it can be done by selecting an existing full backup
        and restore it for you.

    .PARAMETER UseBackupFolder
        This enables the user to specify a specific backup folder containing one or more backup files to initialize the database on the secondary instance.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        Use this switch to disable any kind of verbose messages

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.
        It will also remove the any present schedules with the same name for the specific job.

    .NOTES
        Tags: LogShipping
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbLogShipping

    .EXAMPLE
        PS C:\> $params = @{
        >> SourceSqlInstance = 'sql1'
        >> DestinationSqlInstance = 'sql2'
        >> Database = 'db1'
        >> SharedPath= '\\sql1\logshipping'
        >> LocalPath= 'D:\Data\logshipping'
        >> BackupScheduleFrequencyType = 'daily'
        >> BackupScheduleFrequencyInterval = 1
        >> CompressBackup = $true
        >> CopyScheduleFrequencyType = 'daily'
        >> CopyScheduleFrequencyInterval = 1
        >> GenerateFullBackup = $true
        >> RestoreScheduleFrequencyType = 'daily'
        >> RestoreScheduleFrequencyInterval = 1
        >> SecondaryDatabaseSuffix = 'DR'
        >> CopyDestinationFolder = '\\sql2\logshippingdest'
        >> Force = $true
        >> }
        >>
        PS C:\> Invoke-DbaDbLogShipping @params

        Sets up log shipping for database "db1" with the backup path to a network share allowing local backups.
        It creates daily schedules for the backup, copy and restore job with all the defaults to be executed every 15 minutes daily.
        The secondary database will be called "db1_LS".

    .EXAMPLE
        PS C:\> $params = @{
        >> SourceSqlInstance = 'sql1'
        >> DestinationSqlInstance = 'sql2'
        >> Database = 'db1'
        >> SharedPath= '\\sql1\logshipping'
        >> GenerateFullBackup = $true
        >> Force = $true
        >> }
        >>
        PS C:\> Invoke-DbaDbLogShipping @params

        Sets up log shipping with all defaults except that a backup file is generated.
        The script will show a message that the copy destination has not been supplied and asks if you want to use the default which would be the backup directory of the secondary server with the folder "logshipping" i.e. "D:\SQLBackup\Logshiping".

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]

    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("SourceServerInstance", "SourceSqlServerSqlServer", "Source")]
        [DbaInstanceParameter]$SourceSqlInstance,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("DestinationServerInstance", "DestinationSqlServer", "Destination")]
        [DbaInstanceParameter[]]$DestinationSqlInstance,
        [System.Management.Automation.PSCredential]
        $SourceSqlCredential,
        [System.Management.Automation.PSCredential]
        $SourceCredential,
        [System.Management.Automation.PSCredential]
        $DestinationSqlCredential,
        [System.Management.Automation.PSCredential]
        $DestinationCredential,
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Database,
        [parameter(Mandatory)]
        [Alias("BackupNetworkPath")]
        [string]$SharedPath,
        [Alias("BackupLocalPath")]
        [string]$LocalPath,
        [string]$BackupJob,
        [int]$BackupRetention,
        [string]$BackupSchedule,
        [switch]$BackupScheduleDisabled,
        [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
        [object]$BackupScheduleFrequencyType,
        [object[]]$BackupScheduleFrequencyInterval,
        [ValidateSet('Time', 'Seconds', 'Minutes', 'Hours')]
        [object]$BackupScheduleFrequencySubdayType,
        [int]$BackupScheduleFrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$BackupScheduleFrequencyRelativeInterval,
        [int]$BackupScheduleFrequencyRecurrenceFactor,
        [string]$BackupScheduleStartDate,
        [string]$BackupScheduleEndDate,
        [string]$BackupScheduleStartTime,
        [string]$BackupScheduleEndTime,
        [int]$BackupThreshold,
        [switch]$CompressBackup,
        [string]$CopyDestinationFolder,
        [string]$CopyJob,
        [int]$CopyRetention,
        [string]$CopySchedule,
        [switch]$CopyScheduleDisabled,
        [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
        [object]$CopyScheduleFrequencyType,
        [object[]]$CopyScheduleFrequencyInterval,
        [ValidateSet('Time', 'Seconds', 'Minutes', 'Hours')]
        [object]$CopyScheduleFrequencySubdayType,
        [int]$CopyScheduleFrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$CopyScheduleFrequencyRelativeInterval,
        [int]$CopyScheduleFrequencyRecurrenceFactor,
        [string]$CopyScheduleStartDate,
        [string]$CopyScheduleEndDate,
        [string]$CopyScheduleStartTime,
        [string]$CopyScheduleEndTime,
        [switch]$DisconnectUsers,
        [string]$FullBackupPath,
        [switch]$GenerateFullBackup,
        [int]$HistoryRetention,
        [switch]$NoRecovery,
        [switch]$NoInitialization,
        [string]$PrimaryMonitorServer,
        [System.Management.Automation.PSCredential]
        $PrimaryMonitorCredential,
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$PrimaryMonitorServerSecurityMode,
        [switch]$PrimaryThresholdAlertEnabled,
        [string]$RestoreDataFolder,
        [string]$RestoreLogFolder,
        [int]$RestoreDelay,
        [int]$RestoreAlertThreshold,
        [string]$RestoreJob,
        [int]$RestoreRetention,
        [string]$RestoreSchedule,
        [switch]$RestoreScheduleDisabled,
        [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
        [object]$RestoreScheduleFrequencyType,
        [object[]]$RestoreScheduleFrequencyInterval,
        [ValidateSet('Time', 'Seconds', 'Minutes', 'Hours')]
        [object]$RestoreScheduleFrequencySubdayType,
        [int]$RestoreScheduleFrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$RestoreScheduleFrequencyRelativeInterval,
        [int]$RestoreScheduleFrequencyRecurrenceFactor,
        [string]$RestoreScheduleStartDate,
        [string]$RestoreScheduleEndDate,
        [string]$RestoreScheduleStartTime,
        [string]$RestoreScheduleEndTime,
        [int]$RestoreThreshold,
        [string]$SecondaryDatabasePrefix,
        [string]$SecondaryDatabaseSuffix,
        [string]$SecondaryMonitorServer,
        [System.Management.Automation.PSCredential]
        $SecondaryMonitorCredential,
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$SecondaryMonitorServerSecurityMode,
        [switch]$SecondaryThresholdAlertEnabled,
        [switch]$Standby,
        [string]$StandbyDirectory,
        [switch]$UseExistingFullBackup,
        [string]$UseBackupFolder,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        Write-Message -Message "Started log shipping for $SourceSqlInstance to $DestinationSqlInstance" -Level Verbose

        # Try connecting to the instance
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SourceSqlInstance
            return
        }


        # Check the instance if it is a named instance
        $SourceServerName, $SourceInstanceName = $SourceSqlInstance.FullName.Split("\")

        if ($null -eq $SourceInstanceName) {
            $SourceInstanceName = "MSSQLSERVER"
        }

        # Set up regex strings for several checks
        $RegexDate = '(?<!\d)(?:(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:(?:0[13578]|1[02])31)|(?:(?:0[1,3-9]|1[0-2])(?:29|30)))|(?:(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00)))0229)|(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:0?[1-9])|(?:1[0-2]))(?:0?[1-9]|1\d|2[0-8]))(?!\d)'
        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'
        $RegexUnc = '^\\(?:\\[^<>:`"/\\|?*]+)+$'


        # Check the connection timeout
        if ($SourceServer.ConnectionContext.StatementTimeout -ne 0) {
            $SourceServer.ConnectionContext.StatementTimeout = 0
            Write-Message -Message "Connection timeout of $SourceServer is set to 0" -Level Verbose
        }

        # Check the backup network path
        Write-Message -Message "Testing backup network path $SharedPath" -Level Verbose
        if ((Test-DbaPath -Path $SharedPath -SqlInstance $SourceSqlInstance -SqlCredential $SourceCredential) -ne $true) {
            Stop-Function -Message "Backup network path $SharedPath is not valid or can't be reached." -Target $SourceSqlInstance
            return
        } elseif ($SharedPath -notmatch $RegexUnc) {
            Stop-Function -Message "Backup network path $SharedPath has to be in the form of \\server\share." -Target $SourceSqlInstance
            return
        }

        # Check the backup compression
        if ($SourceServer.Version.Major -gt 9) {
            if ($CompressBackup) {
                Write-Message -Message "Setting backup compression to 1." -Level Verbose
                [bool]$BackupCompression = 1
            } else {
                $backupServerSetting = (Get-DbaSpConfigure -SqlInstance $SourceSqlInstance -ConfigName DefaultBackupCompression).ConfiguredValue
                Write-Message -Message "Setting backup compression to default server setting $backupServerSetting." -Level Verbose
                [bool]$BackupCompression = $backupServerSetting
            }
        } else {
            Write-Message -Message "Source server $SourceServer does not support backup compression" -Level Verbose
        }

        # Check the database parameter
        if ($Database) {
            foreach ($db in $Database) {
                if ($db -notin $SourceServer.Databases.Name) {
                    Stop-Function -Message "Database $db cannot be found on instance $SourceSqlInstance" -Target $SourceSqlInstance
                }

                $DatabaseCollection = $SourceServer.Databases | Where-Object { $_.Name -in $Database }
            }
        } else {
            Stop-Function -Message "Please supply a database to set up log shipping for" -Target $SourceSqlInstance -Continue
        }

        # Set the database mode
        if ($Standby) {
            $DatabaseStatus = 1
            Write-Message -Message "Destination database status set to STANDBY" -Level Verbose
        } else {
            $DatabaseStatus = 0
            Write-Message -Message "Destination database status set to NO RECOVERY" -Level Verbose
        }

        # Setting defaults
        if (-not $BackupRetention) {
            $BackupRetention = 4320
            Write-Message -Message "Backup retention set to $BackupRetention" -Level Verbose
        }
        if (-not $BackupThreshold) {
            $BackupThreshold = 60
            Write-Message -Message "Backup Threshold set to $BackupThreshold" -Level Verbose
        }
        if (-not $CopyRetention) {
            $CopyRetention = 4320
            Write-Message -Message "Copy retention set to $CopyRetention" -Level Verbose
        }
        if (-not $HistoryRetention) {
            $HistoryRetention = 14420
            Write-Message -Message "History retention set to $HistoryRetention" -Level Verbose
        }
        if (-not $RestoreAlertThreshold) {
            $RestoreAlertThreshold = 45
            Write-Message -Message "Restore alert Threshold set to $RestoreAlertThreshold" -Level Verbose
        }
        if (-not $RestoreDelay) {
            $RestoreDelay = 0
            Write-Message -Message "Restore delay set to $RestoreDelay" -Level Verbose
        }
        if (-not $RestoreRetention) {
            $RestoreRetention = 4320
            Write-Message -Message "Restore retention set to $RestoreRetention" -Level Verbose
        }
        if (-not $RestoreThreshold) {
            $RestoreThreshold = 45
            Write-Message -Message "Restore Threshold set to $RestoreThreshold" -Level Verbose
        }
        if (-not $PrimaryMonitorServerSecurityMode) {
            $PrimaryMonitorServerSecurityMode = 1
            Write-Message -Message "Primary monitor server security mode set to $PrimaryMonitorServerSecurityMode" -Level Verbose
        }
        if (-not $SecondaryMonitorServerSecurityMode) {
            $SecondaryMonitorServerSecurityMode = 1
            Write-Message -Message "Secondary monitor server security mode set to $SecondaryMonitorServerSecurityMode" -Level Verbose
        }
        if (-not $BackupScheduleFrequencyType) {
            $BackupScheduleFrequencyType = "Daily"
            Write-Message -Message "Backup frequency type set to $BackupScheduleFrequencyType" -Level Verbose
        }
        if (-not $BackupScheduleFrequencyInterval) {
            $BackupScheduleFrequencyInterval = "EveryDay"
            Write-Message -Message "Backup frequency interval set to $BackupScheduleFrequencyInterval" -Level Verbose
        }
        if (-not $BackupScheduleFrequencySubdayType) {
            $BackupScheduleFrequencySubdayType = "Minutes"
            Write-Message -Message "Backup frequency subday type set to $BackupScheduleFrequencySubdayType" -Level Verbose
        }
        if (-not $BackupScheduleFrequencySubdayInterval) {
            $BackupScheduleFrequencySubdayInterval = 15
            Write-Message -Message "Backup frequency subday interval set to $BackupScheduleFrequencySubdayInterval" -Level Verbose
        }
        if (-not $BackupScheduleFrequencyRelativeInterval) {
            $BackupScheduleFrequencyRelativeInterval = "Unused"
            Write-Message -Message "Backup frequency relative interval set to $BackupScheduleFrequencyRelativeInterval" -Level Verbose
        }
        if (-not $BackupScheduleFrequencyRecurrenceFactor) {
            $BackupScheduleFrequencyRecurrenceFactor = 0
            Write-Message -Message "Backup frequency recurrence factor set to $BackupScheduleFrequencyRecurrenceFactor" -Level Verbose
        }
        if (-not $CopyScheduleFrequencyType) {
            $CopyScheduleFrequencyType = "Daily"
            Write-Message -Message "Copy frequency type set to $CopyScheduleFrequencyType" -Level Verbose
        }
        if (-not $CopyScheduleFrequencyInterval) {
            $CopyScheduleFrequencyInterval = "EveryDay"
            Write-Message -Message "Copy frequency interval set to $CopyScheduleFrequencyInterval" -Level Verbose
        }
        if (-not $CopyScheduleFrequencySubdayType) {
            $CopyScheduleFrequencySubdayType = "Minutes"
            Write-Message -Message "Copy frequency subday type set to $CopyScheduleFrequencySubdayType" -Level Verbose
        }
        if (-not $CopyScheduleFrequencySubdayInterval) {
            $CopyScheduleFrequencySubdayInterval = 15
            Write-Message -Message "Copy frequency subday interval set to $CopyScheduleFrequencySubdayInterval" -Level Verbose
        }
        if (-not $CopyScheduleFrequencyRelativeInterval) {
            $CopyScheduleFrequencyRelativeInterval = "Unused"
            Write-Message -Message "Copy frequency relative interval set to $CopyScheduleFrequencyRelativeInterval" -Level Verbose
        }
        if (-not $CopyScheduleFrequencyRecurrenceFactor) {
            $CopyScheduleFrequencyRecurrenceFactor = 0
            Write-Message -Message "Copy frequency recurrence factor set to $CopyScheduleFrequencyRecurrenceFactor" -Level Verbose
        }
        if (-not $RestoreScheduleFrequencyType) {
            $RestoreScheduleFrequencyType = "Daily"
            Write-Message -Message "Restore frequency type set to $RestoreScheduleFrequencyType" -Level Verbose
        }
        if (-not $RestoreScheduleFrequencyInterval) {
            $RestoreScheduleFrequencyInterval = "EveryDay"
            Write-Message -Message "Restore frequency interval set to $RestoreScheduleFrequencyInterval" -Level Verbose
        }
        if (-not $RestoreScheduleFrequencySubdayType) {
            $RestoreScheduleFrequencySubdayType = "Minutes"
            Write-Message -Message "Restore frequency subday type set to $RestoreScheduleFrequencySubdayType" -Level Verbose
        }
        if (-not $RestoreScheduleFrequencySubdayInterval) {
            $RestoreScheduleFrequencySubdayInterval = 15
            Write-Message -Message "Restore frequency subday interval set to $RestoreScheduleFrequencySubdayInterval" -Level Verbose
        }
        if (-not $RestoreScheduleFrequencyRelativeInterval) {
            $RestoreScheduleFrequencyRelativeInterval = "Unused"
            Write-Message -Message "Restore frequency relative interval set to $RestoreScheduleFrequencyRelativeInterval" -Level Verbose
        }
        if (-not $RestoreScheduleFrequencyRecurrenceFactor) {
            $RestoreScheduleFrequencyRecurrenceFactor = 0
            Write-Message -Message "Restore frequency recurrence factor set to $RestoreScheduleFrequencyRecurrenceFactor" -Level Verbose
        }

        # Checking for contradicting variables
        if ($NoInitialization -and ($GenerateFullBackup -or $UseExistingFullBackup)) {
            Stop-Function -Message "Cannot use -NoInitialization with -GenerateFullBackup or -UseExistingFullBackup" -Target $DestinationSqlInstance
            return
        }

        if ($UseBackupFolder -and ($GenerateFullBackup -or $NoInitialization -or $UseExistingFullBackup)) {
            Stop-Function -Message "Cannot use -UseBackupFolder with -GenerateFullBackup, -NoInitialization or -UseExistingFullBackup" -Target $DestinationSqlInstance
            return
        }

        # Check the subday interval
        if (($BackupScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($BackupScheduleFrequencySubdayInterval -ge 1 -or $BackupScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Backup subday interval $BackupScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $SourceSqlInstance
            return
        } elseif (($BackupScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($BackupScheduleFrequencySubdayInterval -ge 1 -and $BackupScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Backup Subday interval $BackupScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $SourceSqlInstance
            return
        }

        # Check the subday interval
        if (($CopyScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($CopyScheduleFrequencySubdayInterval -ge 1 -or $CopyScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Copy subday interval $CopyScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $DestinationSqlInstance
            return
        } elseif (($CopyScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($CopyScheduleFrequencySubdayInterval -ge 1 -and $CopyScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Copy subday interval $CopyScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours'" -Target $DestinationSqlInstance
            return
        }

        # Check the subday interval
        if (($RestoreScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($RestoreScheduleFrequencySubdayInterval -ge 1 -or $RestoreScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Restore subday interval $RestoreScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $DestinationSqlInstance
            return
        } elseif (($RestoreScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($RestoreScheduleFrequencySubdayInterval -ge 1 -and $RestoreScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Restore subday interval $RestoreScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $DestinationSqlInstance
            return
        }

        # Check the backup start date
        if (-not $BackupScheduleStartDate) {
            $BackupScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Backup start date set to $BackupScheduleStartDate" -Level Verbose
        } else {
            if ($BackupScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Backup start date $BackupScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
                return
            }
        }

        # Check the back start time
        if (-not $BackupScheduleStartTime) {
            $BackupScheduleStartTime = '000000'
            Write-Message -Message "Backup start time set to $BackupScheduleStartTime" -Level Verbose
        } elseif ($BackupScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Backup start time $BackupScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the back end time
        if (-not $BackupScheduleEndTime) {
            $BackupScheduleEndTime = '235959'
            Write-Message -Message "Backup end time set to $BackupScheduleEndTime" -Level Verbose
        } elseif ($BackupScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Backup end time $BackupScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the backup end date
        if (-not $BackupScheduleEndDate) {
            $BackupScheduleEndDate = '99991231'
        } elseif ($BackupScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Backup end date $BackupScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
            return
        }

        # Check the copy start date
        if (-not $CopyScheduleStartDate) {
            $CopyScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Copy start date set to $CopyScheduleStartDate" -Level Verbose
        } else {
            if ($CopyScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Copy start date $CopyScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
                return
            }
        }

        # Check the copy end date
        if (-not $CopyScheduleEndDate) {
            $CopyScheduleEndDate = '99991231'
        } elseif ($CopyScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Copy end date $CopyScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
            return
        }

        # Check the copy start time
        if (-not $CopyScheduleStartTime) {
            $CopyScheduleStartTime = '000000'
            Write-Message -Message "Copy start time set to $CopyScheduleStartTime" -Level Verbose
        } elseif ($CopyScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Copy start time $CopyScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the copy end time
        if (-not $CopyScheduleEndTime) {
            $CopyScheduleEndTime = '235959'
            Write-Message -Message "Copy end time set to $CopyScheduleEndTime" -Level Verbose
        } elseif ($CopyScheduleEndTime -notmatch $RegexTime) {
            Stop-Function -Message  "Copy end time $CopyScheduleEndTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the restore start date
        if (-not $RestoreScheduleStartDate) {
            $RestoreScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Restore start date set to $RestoreScheduleStartDate" -Level Verbose
        } else {
            if ($RestoreScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Restore start date $RestoreScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
                return
            }
        }

        # Check the restore end date
        if (-not $RestoreScheduleEndDate) {
            $RestoreScheduleEndDate = '99991231'
        } elseif ($RestoreScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Restore end date $RestoreScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
            return
        }

        # Check the restore start time
        if (-not $RestoreScheduleStartTime) {
            $RestoreScheduleStartTime = '000000'
            Write-Message -Message "Restore start time set to $RestoreScheduleStartTime" -Level Verbose
        } elseif ($RestoreScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Restore start time $RestoreScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the restore end time
        if (-not $RestoreScheduleEndTime) {
            $RestoreScheduleEndTime = '235959'
            Write-Message -Message "Restore end time set to $RestoreScheduleEndTime" -Level Verbose
        } elseif ($RestoreScheduleEndTime -notmatch $RegexTime) {
            Stop-Function -Message  "Restore end time $RestoreScheduleEndTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($destInstance in $DestinationSqlInstance) {

            $setupResult = "Success"
            $comment = ""

            # Try connecting to the instance
            try {
                $destinationServer = Connect-DbaInstance -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destInstance -Continue
            }

            $DestinationServerName, $DestinationInstanceName = $destInstance.FullName.Split("\")

            if ($null -eq $DestinationInstanceName) {
                $DestinationInstanceName = "MSSQLSERVER"
            }

            $IsDestinationLocal = $false

            # Check if it's local or remote
            if ($DestinationServerName -in ".", "localhost", $env:ServerName, "127.0.0.1") {
                $IsDestinationLocal = $true
            }

            # Check the instance names and the database settings
            if (($SourceSqlInstance -eq $destInstance) -and (-not $SecondaryDatabasePrefix -or $SecondaryDatabaseSuffix)) {
                $setupResult = "Failed"
                $comment = "The destination database is the same as the source"
                Stop-Function -Message "The destination database is the same as the source`nPlease enter a prefix or suffix using -SecondaryDatabasePrefix or -SecondaryDatabaseSuffix." -Target $SourceSqlInstance
                return
            }

            if ($DestinationServer.ConnectionContext.StatementTimeout -ne 0) {
                $DestinationServer.ConnectionContext.StatementTimeout = 0
                Write-Message -Message "Connection timeout of $DestinationServer is set to 0" -Level Verbose
            }

            # Check the copy destination
            if (-not $CopyDestinationFolder) {
                # Make a default copy destination by retrieving the backup folder and adding a directory
                $CopyDestinationFolder = "$($DestinationServer.Settings.BackupDirectory)\Logshipping"

                # Check to see if the path already exists
                Write-Message -Message "Testing copy destination path $CopyDestinationFolder" -Level Verbose
                if (Test-DbaPath -Path $CopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationCredential) {
                    Write-Message -Message "Copy destination $CopyDestinationFolder already exists" -Level Verbose
                } else {
                    # Check if force is being used
                    if (-not $Force) {
                        # Set up the confirm part
                        $message = "The copy destination is missing. Do you want to use the default $($CopyDestinationFolder)?"
                        $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
                        $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
                        $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
                        $result = $host.ui.PromptForChoice($title, $message, $options, 0)

                        # Check the result from the confirm
                        switch ($result) {
                            # If yes
                            0 {
                                # Try to create the new directory
                                try {
                                    # If the destination server is remote and the credential is set
                                    if (-not $IsDestinationLocal -and $DestinationCredential) {
                                        Invoke-Command2 -ComputerName $DestinationServerName -Credential $DestinationCredential -ScriptBlock {
                                            Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
                                            New-Item -Path $CopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
                                        }
                                    }
                                    # If the server is local and the credential is set
                                    elseif ($DestinationCredential) {
                                        Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                            Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
                                            New-Item -Path $CopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
                                        }
                                    }
                                    # If the server is local and the credential is not set
                                    else {
                                        Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
                                        New-Item -Path $CopyDestinationFolder -Force:$Force -ItemType Directory | Out-Null
                                    }
                                    Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose
                                } catch {
                                    $setupResult = "Failed"
                                    $comment = "Something went wrong creating the copy destination folder"
                                    Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $destInstance -ErrorRecord $_
                                    return
                                }
                            }
                            1 {
                                $setupResult = "Failed"
                                $comment = "Copy destination is a mandatory parameter"
                                Stop-Function -Message "Copy destination is a mandatory parameter. Please make sure the value is entered." -Target $destInstance
                                return
                            }
                        } # switch
                    } # if not force
                    else {
                        # Try to create the copy destination on the local server
                        try {
                            Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
                            New-Item $CopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
                            Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong creating the copy destination folder"
                            Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $destInstance -ErrorRecord $_
                            return
                        }
                    } # else not force
                } # if test path copy destination
            } # if not copy destination

            Write-Message -Message "Testing copy destination path $CopyDestinationFolder" -Level Verbose
            if ((Test-DbaPath -Path $CopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationCredential) -ne $true) {
                $setupResult = "Failed"
                $comment = "Copy destination folder $CopyDestinationFolder is not valid or can't be reached"
                Stop-Function -Message "Copy destination folder $CopyDestinationFolder is not valid or can't be reached." -Target $destInstance
                return
            } elseif ($CopyDestinationFolder.StartsWith("\\") -and $CopyDestinationFolder -notmatch $RegexUnc) {
                $setupResult = "Failed"
                $comment = "Copy destination folder $CopyDestinationFolder has to be in the form of \\server\share"
                Stop-Function -Message "Copy destination folder $CopyDestinationFolder has to be in the form of \\server\share." -Target $destInstance
                return
            }

            if (-not ($SecondaryDatabasePrefix -or $SecondaryDatabaseSuffix) -and ($SourceServer.Name -eq $DestinationServer.Name) -and ($SourceServer.InstanceName -eq $DestinationServer.InstanceName)) {
                if ($Force) {
                    $SecondaryDatabaseSuffix = "_LS"
                } else {
                    $setupResult = "Failed"
                    $comment = "Destination database is the same as source database"
                    Stop-Function -Message "Destination database is the same as source database.`nPlease check the secondary server, database prefix or suffix or use -Force to set the secondary database using a suffix." -Target $SourceSqlInstance
                    return
                }
            }

            # Check if standby is being used
            if ($Standby) {
                # Check the stand-by directory
                if ($StandbyDirectory) {
                    # Check if the path is reachable for the destination server
                    if ((Test-DbaPath -Path $StandbyDirectory -SqlInstance $destInstance -SqlCredential $DestinationCredential) -ne $true) {
                        $setupResult = "Failed"
                        $comment = "The directory $StandbyDirectory cannot be reached by the destination instance"
                        Stop-Function -Message "The directory $StandbyDirectory cannot be reached by the destination instance. Please check the permission and credentials." -Target $destInstance
                        return
                    }
                } elseif (-not $StandbyDirectory -and $Force) {
                    $StandbyDirectory = $destInstance.BackupDirectory
                    Write-Message -Message "Stand-by directory was not set. Setting it to $StandbyDirectory" -Level Verbose
                } else {
                    $setupResult = "Failed"
                    $comment = "Please set the parameter -StandbyDirectory when using -Standby"
                    Stop-Function -Message "Please set the parameter -StandbyDirectory when using -Standby" -Target $SourceSqlInstance
                    return
                }
            }

            # Loop through each of the databases
            foreach ($db in $DatabaseCollection) {

                # Check the status of the database
                if ($db.RecoveryModel -ne 'Full') {
                    $setupResult = "Failed"
                    $comment = "Database $db is not in FULL recovery mode"

                    Stop-Function -Message  "Database $db is not in FULL recovery mode" -Target $SourceSqlInstance -Continue
                }

                # Set the intital destination database
                $SecondaryDatabase = $db.Name

                # Set the database prefix
                if ($SecondaryDatabasePrefix) {
                    $SecondaryDatabase = "$SecondaryDatabasePrefix$($db.Name)"
                }

                # Set the database suffix
                if ($SecondaryDatabaseSuffix) {
                    $SecondaryDatabase += $SecondaryDatabaseSuffix
                }

                # Check is the database is already initialized a check if the database exists on the secondary instance
                if ($NoInitialization -and ($DestinationServer.Databases.Name -notcontains $SecondaryDatabase)) {
                    $setupResult = "Failed"
                    $comment = "Database $SecondaryDatabase needs to be initialized before log shipping setting can continue"

                    Stop-Function -Message "Database $SecondaryDatabase needs to be initialized before log shipping setting can continue." -Target $SourceSqlInstance -Continue
                }

                # Check the local backup path
                if ($LocalPath) {
                    if ($LocalPath.EndsWith("\")) {
                        $DatabaseLocalPath = "$LocalPath$($db.Name)"
                    } else {
                        $DatabaseLocalPath = "$LocalPath\$($db.Name)"
                    }
                } else {
                    $LocalPath = $SharedPath

                    if ($LocalPath.EndsWith("\")) {
                        $DatabaseLocalPath = "$LocalPath$($db.Name)"
                    } else {
                        $DatabaseLocalPath = "$LocalPath\$($db.Name)"
                    }
                }
                Write-Message -Message "Backup local path set to $DatabaseLocalPath." -Level Verbose

                # Setting the backup network path for the database
                if ($SharedPath.EndsWith("\")) {
                    $DatabaseSharedPath = "$SharedPath$($db.Name)"
                } else {
                    $DatabaseSharedPath = "$SharedPath\$($db.Name)"
                }
                Write-Message -Message "Backup network path set to $DatabaseSharedPath." -Level Verbose


                # Checking if the database network path exists
                if ($setupResult -ne 'Failed') {
                    Write-Message -Message "Testing database backup network path $DatabaseSharedPath" -Level Verbose
                    if ((Test-DbaPath -Path $DatabaseSharedPath -SqlInstance $SourceSqlInstance -SqlCredential $SourceCredential) -ne $true) {
                        # To to create the backup directory for the database
                        try {
                            Write-Message -Message "Database backup network path $DatabaseSharedPath not found. Trying to create it.." -Level Verbose

                            Invoke-Command2 -Credential $SourceCredential -ScriptBlock {
                                Write-Message -Message "Creating backup folder $DatabaseSharedPath" -Level Verbose
                                $null = New-Item -Path $DatabaseSharedPath -ItemType Directory -Credential $SourceCredential -Force:$Force
                            }
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong creating the backup directory"

                            Stop-Function -Message "Something went wrong creating the backup directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                        }
                    }
                }

                # Check if the backup job name is set
                if ($BackupJob) {
                    $DatabaseBackupJob = "$($BackupJob)$($db.Name)"
                } else {
                    $DatabaseBackupJob = "LSBackup_$($db.Name)"
                }
                Write-Message -Message "Backup job name set to $DatabaseBackupJob" -Level Verbose

                # Check if the backup job schedule name is set
                if ($BackupSchedule) {
                    $DatabaseBackupSchedule = "$($BackupSchedule)$($db.Name)"
                } else {
                    $DatabaseBackupSchedule = "LSBackupSchedule_$($db.Name)"
                }
                Write-Message -Message "Backup job schedule name set to $DatabaseBackupSchedule" -Level Verbose

                # Check if secondary database is present on secondary instance
                if (-not $Force -and -not $NoInitialization -and ($DestinationServer.Databases[$SecondaryDatabase].Status -ne 'Restoring') -and ($DestinationServer.Databases.Name -contains $SecondaryDatabase)) {
                    $setupResult = "Failed"
                    $comment = "Secondary database already exists on instance"

                    Stop-Function -Message "Secondary database already exists on instance $destInstance." -ErrorRecord $_ -Target $destInstance -Continue
                }

                # Check if the secondary database needs to be initialized
                if ($setupResult -ne 'Failed') {
                    if (-not $NoInitialization) {
                        # Check if the secondary database exists on the secondary instance
                        if ($DestinationServer.Databases.Name -notcontains $SecondaryDatabase) {
                            # Check if force is being used and no option to generate the full backup is set
                            if ($Force -and -not ($GenerateFullBackup -or $UseExistingFullBackup)) {
                                # Set the option to generate a full backup
                                Write-Message -Message "Set option to initialize secondary database with full backup" -Level Verbose
                                $GenerateFullBackup = $true
                            } elseif (-not $Force -and -not $GenerateFullBackup -and -not $UseExistingFullBackup -and -not $UseBackupFolder) {
                                # Set up the confirm part
                                $message = "The database $SecondaryDatabase does not exist on instance $destInstance. `nDo you want to initialize it by generating a full backup?"
                                $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
                                $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 0)

                                # Check the result from the confirm
                                switch ($result) {
                                    # If yes
                                    0 {
                                        # Set the option to generate a full backup
                                        Write-Message -Message "Set option to initialize secondary database with full backup." -Level Verbose
                                        $GenerateFullBackup = $true
                                    }
                                    1 {
                                        $setupResult = "Failed"
                                        $comment = "The database is not initialized on the secondary instance"

                                        Stop-Function -Message "The database is not initialized on the secondary instance. `nPlease initialize the database on the secondary instance, use -GenerateFullbackup or use -Force." -Target $destInstance
                                        return
                                    }
                                } # switch
                            }
                        }
                    }
                }


                # Check the parameters for initialization of the secondary database
                if (-not $NoInitialization -and ($GenerateFullBackup -or $UseExistingFullBackup -or $UseBackupFolder)) {
                    # Check if the restore data and log folder are set
                    if ($setupResult -ne 'Failed') {
                        if ($RestoreDataFolder) {
                            $DatabaseRestoreDataFolder = $RestoreDataFolder
                        } else {
                            Write-Message -Message "Restore data folder is not set. Using server default." -Level Verbose
                            $DatabaseRestoreDataFolder = $DestinationServer.DefaultFile
                        }
                        Write-Message -Message "Restore data folder is set to $DatabaseRestoreDataFolder" -Level Verbose

                        if ($RestoreLogFolder) {
                            $DatabaseRestoreLogFolder = $RestoreLogFolder
                        } else {
                            Write-Message -Message "Restore log folder is not set. Using server default." -Level Verbose
                            $DatabaseRestoreLogFolder = $DestinationServer.DefaultLog
                        }
                        Write-Message -Message "Restore log folder is set to $DatabaseRestoreLogFolder" -Level Verbose

                        # Check if the restore data folder exists
                        Write-Message -Message "Testing database restore data path $DatabaseRestoreDataFolder" -Level Verbose
                        if ((Test-DbaPath  -Path $DatabaseRestoreDataFolder -SqlInstance $destInstance -SqlCredential $DestinationCredential) -ne $true) {
                            if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating database restore data folder $DatabaseRestoreDataFolder on $DestinationServerName")) {
                                # Try creating the data folder
                                try {
                                    Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                        Write-Message -Message "Creating data folder $DatabaseRestoreDataFolder" -Level Verbose
                                        $null = New-Item -Path $DatabaseRestoreDataFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force
                                    }
                                } catch {
                                    $setupResult = "Failed"
                                    $comment = "Something went wrong creating the restore data directory"
                                    Stop-Function -Message "Something went wrong creating the restore data directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                                }
                            }
                        }

                        # Check if the restore log folder exists
                        Write-Message -Message "Testing database restore log path $DatabaseRestoreLogFolder" -Level Verbose
                        if ((Test-DbaPath  -Path $DatabaseRestoreLogFolder -SqlInstance $destInstance -SqlCredential $DestinationCredential) -ne $true) {
                            if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating database restore log folder $DatabaseRestoreLogFolder on $DestinationServerName")) {
                                # Try creating the log folder
                                try {
                                    Write-Message -Message "Restore log folder $DatabaseRestoreLogFolder not found. Trying to create it.." -Level Verbose

                                    Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                        Write-Message -Message "Restore log folder $DatabaseRestoreLogFolder not found. Trying to create it.." -Level Verbose
                                        $null = New-Item -Path $DatabaseRestoreLogFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force
                                    }
                                } catch {
                                    $setupResult = "Failed"
                                    $comment = "Something went wrong creating the restore log directory"
                                    Stop-Function -Message "Something went wrong creating the restore log directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                                }
                            }
                        }
                    }

                    # Check if the full backup path can be reached
                    if ($setupResult -ne 'Failed') {
                        if ($FullBackupPath) {
                            Write-Message -Message "Testing full backup path $FullBackupPath" -Level Verbose
                            if ((Test-DbaPath -Path $FullBackupPath -SqlInstance $destInstance -SqlCredential $DestinationCredential) -ne $true) {
                                $setupResult = "Failed"
                                $comment = "The path to the full backup could not be reached"
                                Stop-Function -Message ("The path to the full backup could not be reached. Check the path and/or the crdential") -ErrorRecord $_ -Target $destInstance -Continue
                            }

                            $BackupPath = $FullBackupPath
                        } elseif ($UseBackupFolder.Length -ge 1) {
                            Write-Message -Message "Testing backup folder $UseBackupFolder" -Level Verbose
                            if ((Test-DbaPath -Path $UseBackupFolder -SqlInstance $destInstance -SqlCredential $DestinationCredential) -ne $true) {
                                $setupResult = "Failed"
                                $comment = "The path to the backup folder could not be reached"
                                Stop-Function -Message ("The path to the backup folder could not be reached. Check the path and/or the crdential") -ErrorRecord $_ -Target $destInstance -Continue
                            }

                            $BackupPath = $UseBackupFolder
                        } elseif ($UseExistingFullBackup) {
                            Write-Message -Message "No path to the full backup is set. Trying to retrieve the last full backup for $db from $SourceSqlInstance" -Level Verbose

                            # Get the last full backup
                            $LastBackup = Get-DbaDbBackupHistory -SqlInstance $SourceSqlInstance -Database $($db.Name) -LastFull -SqlCredential $SourceSqlCredential

                            # Check if there was a last backup
                            if ($null -ne $LastBackup) {
                                # Test the path to the backup
                                Write-Message -Message "Testing last backup path $(($LastBackup[-1]).Path[-1])" -Level Verbose
                                if ((Test-DbaPath -Path ($LastBackup[-1]).Path[-1] -SqlInstance $SourceSqlInstance -SqlCredential $SourceCredential) -ne $true) {
                                    $setupResult = "Failed"
                                    $comment = "The full backup could not be found"
                                    Stop-Function -Message "The full backup could not be found on $($LastBackup.Path). Check path and/or credentials" -ErrorRecord $_ -Target $destInstance -Continue
                                }
                                # Check if the source for the last full backup is remote and the backup is on a shared location
                                elseif (($LastBackup.Computername -ne $SourceServerName) -and (($LastBackup[-1]).Path[-1].StartsWith('\\') -eq $false)) {
                                    $setupResult = "Failed"
                                    $comment = "The last full backup is not located on shared location"
                                    Stop-Function -Message "The last full backup is not located on shared location. `n$($_.Exception.Message)" -ErrorRecord $_ -Target $destInstance -Continue
                                } else {
                                    #$FullBackupPath = $LastBackup.Path
                                    $BackupPath = $LastBackup.Path
                                    Write-Message -Message "Full backup found for $db. Path $BackupPath" -Level Verbose
                                }
                            } else {
                                Write-Message -Message "No Full backup found for $db." -Level Verbose
                            }
                        }
                    }
                }

                # Set the copy destination folder to include the database name
                if ($CopyDestinationFolder.EndsWith("\")) {
                    $DatabaseCopyDestinationFolder = "$CopyDestinationFolder$($db.Name)"
                } else {
                    $DatabaseCopyDestinationFolder = "$CopyDestinationFolder\$($db.Name)"
                }
                Write-Message -Message "Copy destination folder set to $DatabaseCopyDestinationFolder." -Level Verbose

                # Check if the copy job name is set
                if ($CopyJob) {
                    $DatabaseCopyJob = "$($CopyJob)$($db.Name)"
                } else {
                    $DatabaseCopyJob = "LSCopy_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Copy job name set to $DatabaseCopyJob" -Level Verbose

                # Check if the copy job schedule name is set
                if ($CopySchedule) {
                    $DatabaseCopySchedule = "$($CopySchedule)$($db.Name)"
                } else {
                    $DatabaseCopySchedule = "LSCopySchedule_$($SourceServerName)_$($db.Name)"
                    Write-Message -Message "Copy job schedule name set to $DatabaseCopySchedule" -Level Verbose
                }

                # Check if the copy destination folder exists
                if ($setupResult -ne 'Failed') {
                    Write-Message -Message "Testing database copy destination path $DatabaseCopyDestinationFolder" -Level Verbose
                    if ((Test-DbaPath -Path $DatabaseCopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationCredential) -ne $true) {
                        if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating copy destination folder on $DestinationServerName")) {
                            try {
                                Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                    Write-Message -Message "Copy destination folder $DatabaseCopyDestinationFolder not found. Trying to create it.. ." -Level Verbose
                                    $null = New-Item -Path $DatabaseCopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force
                                }
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong creating the database copy destination folder"
                                Stop-Function -Message "Something went wrong creating the database copy destination folder. `n$($_.Exception.Message)" -ErrorRecord $_ -Target $DestinationServerName -Continue
                            }
                        }
                    }
                }

                # Check if the restore job name is set
                if ($RestoreJob) {
                    $DatabaseRestoreJob = "$($RestoreJob)$($db.Name)"
                } else {
                    $DatabaseRestoreJob = "LSRestore_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Restore job name set to $DatabaseRestoreJob" -Level Verbose

                # Check if the restore job schedule name is set
                if ($RestoreSchedule) {
                    $DatabaseRestoreSchedule = "$($RestoreSchedule)$($db.Name)"
                } else {
                    $DatabaseRestoreSchedule = "LSRestoreSchedule_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Restore job schedule name set to $DatabaseRestoreSchedule" -Level Verbose

                # If the database needs to be backed up first
                if ($setupResult -ne 'Failed') {
                    if ($GenerateFullBackup) {
                        if ($PSCmdlet.ShouldProcess($SourceSqlInstance, "Backing up database $db")) {

                            Write-Message -Message "Generating full backup." -Level Verbose
                            Write-Message -Message "Backing up database $db to $DatabaseSharedPath" -Level Verbose

                            try {
                                $Timestamp = Get-Date -format "yyyyMMddHHmmss"

                                $LastBackup = Backup-DbaDatabase -SqlInstance $SourceSqlInstance `
                                    -SqlCredential $SourceSqlCredential `
                                    -BackupDirectory $DatabaseSharedPath `
                                    -BackupFileName "FullBackup_$($db.Name)_PreLogShipping_$Timestamp.bak" `
                                    -Database $($db.Name) `
                                    -Type Full

                                Write-Message -Message "Backup completed." -Level Verbose

                                # Get the last full backup path
                                #$FullBackupPath = $LastBackup.BackupPath
                                $BackupPath = $LastBackup.BackupPath

                                Write-Message -Message "Backup is located at $BackupPath" -Level Verbose
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong generating the full backup"
                                Stop-Function -Message "Something went wrong generating the full backup" -ErrorRecord $_ -Target $DestinationServerName -Continue
                            }
                        }
                    }
                }

                # Check of the MonitorServerSecurityMode value is of type string and set the integer value
                if ($PrimaryMonitorServerSecurityMode -notin 0, 1) {
                    $PrimaryMonitorServerSecurityMode = switch ($PrimaryMonitorServerSecurityMode) {
                        "SQLSERVER" { 0 } "WINDOWS" { 1 } default { 1 }
                    }
                }

                # Check the primary monitor server
                if ($Force -and (-not $PrimaryMonitorServer -or [string]$PrimaryMonitorServer -eq '' -or $null -eq $PrimaryMonitorServer)) {
                    Write-Message -Message "Setting monitor server for primary server to $SourceSqlInstance." -Level Verbose
                    $PrimaryMonitorServer = $SourceSqlInstance
                }

                # Check the PrimaryMonitorServerSecurityMode if it's SQL Server authentication
                if ($PrimaryMonitorServerSecurityMode -eq 0) {
                    if ($PrimaryMonitorServerLogin) {
                        $setupResult = "Failed"
                        $comment = "The PrimaryMonitorServerLogin cannot be empty"
                        Stop-Function -Message "The PrimaryMonitorServerLogin cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue
                    }

                    if ($PrimaryMonitorServerPassword) {
                        $setupResult = "Failed"
                        $comment = "The PrimaryMonitorServerPassword cannot be empty"
                        Stop-Function -Message "The PrimaryMonitorServerPassword cannot be empty when using SQL Server authentication." -Target $ -Continue
                    }
                }

                # Check of the SecondaryMonitorServerSecurityMode value is of type string and set the integer value
                if ($SecondaryMonitorServerSecurityMode -notin 0, 1) {
                    $SecondaryMonitorServerSecurityMode = switch ($SecondaryMonitorServerSecurityMode) {
                        "SQLSERVER" { 0 } "WINDOWS" { 1 } default { 1 }
                    }
                }

                # Check the secondary monitor server
                if ($Force -and (-not $SecondaryMonitorServer -or [string]$SecondaryMonitorServer -eq '' -or $null -eq $SecondaryMonitorServer)) {
                    Write-Message -Message "Setting secondary monitor server for $destInstance to $SourceSqlInstance." -Level Verbose
                    $SecondaryMonitorServer = $SourceSqlInstance
                }

                # Check the MonitorServerSecurityMode if it's SQL Server authentication
                if ($SecondaryMonitorServerSecurityMode -eq 0) {
                    if ($SecondaryMonitorServerLogin) {
                        $setupResult = "Failed"
                        $comment = "The SecondaryMonitorServerLogin cannot be empty"
                        Stop-Function -Message "The SecondaryMonitorServerLogin cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue
                    }

                    if ($SecondaryMonitorServerPassword) {
                        $setupResult = "Failed"
                        $comment = "The SecondaryMonitorServerPassword cannot be empty"
                        Stop-Function -Message "The SecondaryMonitorServerPassword cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue
                    }
                }

                # Now that all the checks have been done we can start with the fun stuff !

                # Restore the full backup
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($destInstance, "Restoring database $db to $SecondaryDatabase on $destInstance")) {
                        if ($GenerateFullBackup -or $UseExistingFullBackup -or $UseBackupFolder) {
                            try {
                                Write-Message -Message "Start database restore" -Level Verbose
                                if ($NoRecovery -or (-not $Standby)) {
                                    if ($Force) {
                                        $null = Restore-DbaDatabase -SqlInstance $destInstance `
                                            -SqlCredential $DestinationSqlCredential `
                                            -Path $BackupPath `
                                            -DestinationFilePrefix $SecondaryDatabasePrefix `
                                            -DestinationFileSuffix $SecondaryDatabaseSuffix `
                                            -DestinationDataDirectory $DatabaseRestoreDataFolder `
                                            -DestinationLogDirectory $DatabaseRestoreLogFolder `
                                            -DatabaseName $SecondaryDatabase `
                                            -DirectoryRecurse `
                                            -NoRecovery `
                                            -WithReplace
                                    } else {
                                        $null = Restore-DbaDatabase -SqlInstance $destInstance `
                                            -SqlCredential $DestinationSqlCredential `
                                            -Path $BackupPath `
                                            -DestinationFilePrefix $SecondaryDatabasePrefix `
                                            -DestinationFileSuffix $SecondaryDatabaseSuffix `
                                            -DestinationDataDirectory $DatabaseRestoreDataFolder `
                                            -DestinationLogDirectory $DatabaseRestoreLogFolder `
                                            -DatabaseName $SecondaryDatabase `
                                            -DirectoryRecurse `
                                            -NoRecovery
                                    }
                                }

                                # If the database needs to be in standby
                                if ($Standby) {
                                    # Setup the path to the standby file
                                    $StandbyDirectory = "$DatabaseCopyDestinationFolder"

                                    # Check if credentials need to be used
                                    if ($DestinationSqlCredential) {
                                        $null = Restore-DbaDatabase -SqlInstance $destInstance `
                                            -SqlCredential $DestinationSqlCredential `
                                            -Path $BackupPath `
                                            -DestinationFilePrefix $SecondaryDatabasePrefix `
                                            -DestinationFileSuffix $SecondaryDatabaseSuffix `
                                            -DestinationDataDirectory $DatabaseRestoreDataFolder `
                                            -DestinationLogDirectory $DatabaseRestoreLogFolder `
                                            -DatabaseName $SecondaryDatabase `
                                            -DirectoryRecurse `
                                            -StandbyDirectory $StandbyDirectory
                                    } else {
                                        $null = Restore-DbaDatabase -SqlInstance $destInstance `
                                            -Path $BackupPath `
                                            -DestinationFilePrefix $SecondaryDatabasePrefix `
                                            -DestinationFileSuffix $SecondaryDatabaseSuffix `
                                            -DestinationDataDirectory $DatabaseRestoreDataFolder `
                                            -DestinationLogDirectory $DatabaseRestoreLogFolder `
                                            -DatabaseName $SecondaryDatabase `
                                            -DirectoryRecurse `
                                            -StandbyDirectory $StandbyDirectory
                                    }
                                }
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong restoring the secondary database"
                                Stop-Function -Message "Something went wrong restoring the secondary database" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                            }

                            Write-Message -Message "Restore completed." -Level Verbose
                        }
                    }
                }

                #region Set up log shipping on the primary instance
                # Set up log shipping on the primary instance
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($SourceSqlInstance, "Configuring logshipping for primary database $db on $SourceSqlInstance")) {
                        try {

                            Write-Message -Message "Configuring logshipping for primary database" -Level Verbose

                            New-DbaLogShippingPrimaryDatabase -SqlInstance $SourceSqlInstance `
                                -SqlCredential $SourceSqlCredential `
                                -Database $($db.Name) `
                                -BackupDirectory $DatabaseLocalPath `
                                -BackupJob $DatabaseBackupJob `
                                -BackupRetention $BackupRetention `
                                -BackupShare $DatabaseSharedPath `
                                -BackupThreshold $BackupThreshold `
                                -CompressBackup:$BackupCompression `
                                -HistoryRetention $HistoryRetention `
                                -MonitorServer $PrimaryMonitorServer `
                                -MonitorServerSecurityMode $PrimaryMonitorServerSecurityMode `
                                -MonitorCredential $PrimaryMonitorCredential `
                                -ThresholdAlertEnabled:$PrimaryThresholdAlertEnabled `
                                -Force:$Force

                            # Check if the backup job needs to be enabled or disabled
                            if ($BackupScheduleDisabled) {
                                $null = Set-DbaAgentJob -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Job $DatabaseBackupJob -Disabled
                                Write-Message -Message "Disabling backup job $DatabaseBackupJob" -Level Verbose
                            } else {
                                $null = Set-DbaAgentJob -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Job $DatabaseBackupJob -Enabled
                                Write-Message -Message "Enabling backup job $DatabaseBackupJob" -Level Verbose
                            }

                            Write-Message -Message "Create backup job schedule $DatabaseBackupSchedule" -Level Verbose

                            #Variable $BackupJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                            $null = New-DbaAgentSchedule -SqlInstance $SourceSqlInstance `
                                -SqlCredential $SourceSqlCredential `
                                -Job $DatabaseBackupJob `
                                -Schedule $DatabaseBackupSchedule `
                                -FrequencyType $BackupScheduleFrequencyType `
                                -FrequencyInterval $BackupScheduleFrequencyInterval `
                                -FrequencySubdayType $BackupScheduleFrequencySubdayType `
                                -FrequencySubdayInterval $BackupScheduleFrequencySubdayInterval `
                                -FrequencyRelativeInterval $BackupScheduleFrequencyRelativeInterval `
                                -FrequencyRecurrenceFactor $BackupScheduleFrequencyRecurrenceFactor `
                                -StartDate $BackupScheduleStartDate `
                                -EndDate $BackupScheduleEndDate `
                                -StartTime $BackupScheduleStartTime `
                                -EndTime $BackupScheduleEndTime `
                                -Force:$Force

                            Write-Message -Message "Configuring logshipping from primary to secondary database." -Level Verbose

                            New-DbaLogShippingPrimarySecondary -SqlInstance $SourceSqlInstance `
                                -SqlCredential $SourceSqlCredential `
                                -PrimaryDatabase $($db.Name) `
                                -SecondaryDatabase $SecondaryDatabase `
                                -SecondaryServer $destInstance `
                                -SecondarySqlCredential $DestinationSqlCredential
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong setting up log shipping for primary instance"
                            Stop-Function -Message "Something went wrong setting up log shipping for primary instance" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                        }
                    }
                }
                #endregion Set up log shipping on the primary instance

                #region Set up log shipping on the secondary instance
                # Set up log shipping on the secondary instance
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($destInstance, "Configuring logshipping for secondary database $SecondaryDatabase on $destInstance")) {
                        try {

                            Write-Message -Message "Configuring logshipping from secondary database $SecondaryDatabase to primary database $db." -Level Verbose

                            New-DbaLogShippingSecondaryPrimary -SqlInstance $destInstance `
                                -SqlCredential $DestinationSqlCredential `
                                -BackupSourceDirectory $DatabaseSharedPath `
                                -BackupDestinationDirectory $DatabaseCopyDestinationFolder `
                                -CopyJob $DatabaseCopyJob `
                                -FileRetentionPeriod $BackupRetention `
                                -MonitorServer $SecondaryMonitorServer `
                                -MonitorServerSecurityMode $SecondaryMonitorServerSecurityMode `
                                -MonitorCredential $SecondaryMonitorCredential `
                                -PrimaryServer $SourceSqlInstance `
                                -PrimaryDatabase $($db.Name) `
                                -RestoreJob $DatabaseRestoreJob `
                                -Force:$Force

                            Write-Message -Message "Create copy job schedule $DatabaseCopySchedule" -Level Verbose
                            #Variable $CopyJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                            $null = New-DbaAgentSchedule -SqlInstance $destInstance `
                                -SqlCredential $DestinationSqlCredential `
                                -Job $DatabaseCopyJob `
                                -Schedule $DatabaseCopySchedule `
                                -FrequencyType $CopyScheduleFrequencyType `
                                -FrequencyInterval $CopyScheduleFrequencyInterval `
                                -FrequencySubdayType $CopyScheduleFrequencySubdayType `
                                -FrequencySubdayInterval $CopyScheduleFrequencySubdayInterval `
                                -FrequencyRelativeInterval $CopyScheduleFrequencyRelativeInterval `
                                -FrequencyRecurrenceFactor $CopyScheduleFrequencyRecurrenceFactor `
                                -StartDate $CopyScheduleStartDate `
                                -EndDate $CopyScheduleEndDate `
                                -StartTime $CopyScheduleStartTime `
                                -EndTime $CopyScheduleEndTime `
                                -Force:$Force

                            Write-Message -Message "Create restore job schedule $DatabaseRestoreSchedule" -Level Verbose

                            #Variable $RestoreJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                            $null = New-DbaAgentSchedule -SqlInstance $destInstance `
                                -SqlCredential $DestinationSqlCredential `
                                -Job $DatabaseRestoreJob `
                                -Schedule $DatabaseRestoreSchedule `
                                -FrequencyType $RestoreScheduleFrequencyType `
                                -FrequencyInterval $RestoreScheduleFrequencyInterval `
                                -FrequencySubdayType $RestoreScheduleFrequencySubdayType `
                                -FrequencySubdayInterval $RestoreScheduleFrequencySubdayInterval `
                                -FrequencyRelativeInterval $RestoreScheduleFrequencyRelativeInterval `
                                -FrequencyRecurrenceFactor $RestoreScheduleFrequencyRecurrenceFactor `
                                -StartDate $RestoreScheduleStartDate `
                                -EndDate $RestoreScheduleEndDate `
                                -StartTime $RestoreScheduleStartTime `
                                -EndTime $RestoreScheduleEndTime `
                                -Force:$Force

                            Write-Message -Message "Configuring logshipping for secondary database." -Level Verbose

                            New-DbaLogShippingSecondaryDatabase -SqlInstance $destInstance `
                                -SqlCredential $DestinationSqlCredential `
                                -SecondaryDatabase $SecondaryDatabase `
                                -PrimaryServer $SourceSqlInstance `
                                -PrimaryDatabase $($db.Name) `
                                -RestoreDelay $RestoreDelay `
                                -RestoreMode $DatabaseStatus `
                                -DisconnectUsers:$DisconnectUsers `
                                -RestoreThreshold $RestoreThreshold `
                                -ThresholdAlertEnabled:$SecondaryThresholdAlertEnabled `
                                -HistoryRetention $HistoryRetention `
                                -MonitorServer $SecondaryMonitorServer `
                                -MonitorServerSecurityMode $SecondaryMonitorServerSecurityMode `
                                -MonitorCredential $SecondaryMonitorCredential

                            # Check if the copy job needs to be enabled or disabled
                            if ($CopyScheduleDisabled) {
                                $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Disabled
                            } else {
                                $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Enabled
                            }

                            # Check if the restore job needs to be enabled or disabled
                            if ($RestoreScheduleDisabled) {
                                $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseRestoreJob -Disabled
                            } else {
                                $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseRestoreJob -Enabled
                            }

                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong setting up log shipping for secondary instance"
                            Stop-Function -Message "Something went wrong setting up log shipping for secondary instance.`n$($_.Exception.Message)" -ErrorRecord $_ -Target $destInstance -Continue
                        }
                    }
                }
                #endregion Set up log shipping on the secondary instance

                Write-Message -Message "Completed configuring log shipping for database $db" -Level Verbose

                [PSCustomObject]@{
                    PrimaryInstance   = $SourceServer.DomainInstanceName
                    SecondaryInstance = $DestinationServer.DomainInstanceName
                    PrimaryDatabase   = $($db.Name)
                    SecondaryDatabase = $SecondaryDatabase
                    Result            = $setupResult
                    Comment           = $comment
                }

            } # for each database
        } # end for each destination server
    } # end process
    end {
        Write-Message -Message "Finished setting up log shipping." -Level Verbose
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUrinJU0TDM8lwDc0N9sqdiZvT
# cEmgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFOwwsQl8pyGWEPa97kO5UozLzh/HMA0G
# CSqGSIb3DQEBAQUABIIBAIOHJOSzhrvXr0KhDOtsVqKqXOXJwJP893umCwtp22+v
# WxBzrSV5jNNZcxIRPsMDL6uFgzscnqKczdz7lsUDiigxj8W66xgRA2qtTTU3sKiW
# Snd2fPJgs2JBcXDC2uO1ym2Dra56xEqH68khzAIBoWLmGcpmjymZtJyl29fc04Jb
# u2SG3X0LBEiJT4UVA4Owp8vUu6Fk86SPQPZXUV7iGtIQb7kN72SmO3DmTSVDlKxY
# 0GgYdNhBOXip2MgVMVya6gZVzcaChhsmGhRKw897Pr5odMc/WJ9sp0WYXW1pfIgf
# SAQ3LM0mfRoCBDZUglYnUjvMDzvrj2A4V+KSP8dWVpOhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU1WjAvBgkqhkiG9w0BCQQxIgQgoo+fxf1mWU3MrU9rRTf9
# yPjXsaQtlAShFEJ9fpACP50wDQYJKoZIhvcNAQEBBQAEggIAmD24EyPRUJm/kNN5
# Pp+K+/wmN6AeVi24W3mbhAqiUDroY9DCoyqB578qeMm7Yi45SkNCJkZ7g5QY3pJg
# HKaFCL54Rup0B0tgG29/W1cc42zgXiMrVLYr54+lnWXR3W98IMJnE/SHkyiRAn7F
# G4Jzy8fwyHwn00yAeKpg8ittdbmYMIEM+LkihybHqFmVuwJNqlgHW7HSv8sGpPQ6
# CatXQneKUWNqnjxn1odVKnhEJdH0/mFmarD8VwVt6sqqwH9jJ9bRhkt7Hikup+tb
# f5pmqnB9fLBk0woWawXA9Y7QSkZcYwwTHg58djVwchvHG5XvhT+eiEZ6ZAtD/AsH
# iF/Ois1EL0pcXgTFj1S0q1rAsy2YgxAyEUWSb31pQxdY/JQeyK0zQGKAhsy19Imo
# raegbnk395U/+62nY/Alp1PH6LujKEEKq0MrNLB2W4WPfKreSdaZK8okjDCOQue+
# 1przcc6Pm2ro5w7VLz+vu6/ybQA1+FOYj4fbWG+NItM+kOCYCK2gbmegaVqlxnmA
# mKjrX1Bq2jUUCRUQ2zTilaoX/+vj7nkLX302yAWCp7YwkzeYEsfr7wNDHSCPIf0g
# ZEQrwE9WQ6juwNGQqRkpE2ISnNWkuJFN1OVsBKk+xqJk8/SN83yuhvKeAYSibNIm
# xcRD3CmDLxQk85OgNSY73VHpCN4=
# SIG # End signature block
