function Get-DbaDbBackupHistory {
    <#
    .SYNOPSIS
        Returns backup history details for databases on a SQL Server.

    .DESCRIPTION
        Returns backup history details for some or all databases on a SQL Server.

        You can even get detailed information (including file path) for latest full, differential and log files.

        Backups taken with the CopyOnly option will NOT be returned, unless the IncludeCopyOnly switch is present.

        Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER IncludeCopyOnly
        By default Get-DbaDbBackupHistory will ignore backups taken with the CopyOnly option. This switch will include them.

    .PARAMETER Force
        If this switch is enabled, a large amount of information is returned, similar to what SQL Server itself returns.

    .PARAMETER Since
        Specifies a DateTime object to use as the starting point for the search for backups.

    .PARAMETER RecoveryFork
        Specifies the Recovery Fork you want backup history for.

    .PARAMETER Last
        If this switch is enabled, the most recent full chain of full, diff and log backup sets is returned.

    .PARAMETER LastFull
        If this switch is enabled, the most recent full backup set is returned.

    .PARAMETER LastDiff
        If this switch is enabled, the most recent differential backup set is returned.

    .PARAMETER LastLog
        If this switch is enabled, the most recent log backup is returned.

    .PARAMETER DeviceType
        Specifies a filter for backup sets based on DeviceType. Valid options are 'Disk','Permanent Disk Device', 'Tape', 'Permanent Tape Device','Pipe','Permanent Pipe Device','Virtual Device','URL', in addition to custom integers for your own DeviceType.

    .PARAMETER Raw
        If this switch is enabled, one object per backup file is returned. Otherwise, media sets (striped backups across multiple files) will be grouped into a single return object.

    .PARAMETER Type
        Specifies one or more types of backups to return. Valid options are 'Full', 'Log', 'Differential', 'File', 'Differential File', 'Partial Full', and 'Partial Differential'. Otherwise, all types of backups will be returned unless one of the -Last* switches is enabled.

    .PARAMETER LastLsn
        Specifies a minimum LSN to use in filtering backup history. Only backups with an LSN greater than this value will be returned, which helps speed the retrieval process.

    .PARAMETER IncludeMirror
        By default mirrors of backups are not returned, this switch will cause them to be returned.

    .PARAMETER AgCheck
        Deprecated. The functionality to also get the history from all replicas if SqlInstance is part on an availability group has been moved to Get-DbaAgBackupHistory.

    .PARAMETER IgnoreDiffBackup
        When this switch is enabled, Differential backups will be ignored.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Backup
        Author: Chrissy LeMaire (@cl) | Stuart Moore (@napalmgram)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbBackupHistory

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a

        Returns server name, database, username, backup type, date for all database backups still in msdb history on SqlInstance2014a. This may return many rows; consider using filters that are included in other examples.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a -SqlCredential $cred

        Does the same as above but connect to SqlInstance2014a as SQL user "sqladmin"

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a -Database db1, db2 -Since '2016-07-01 10:47:00'

        Returns backup information only for databases db1 and db2 on SqlInstance2014a since July 1, 2016 at 10:47 AM.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs -Force | Format-Table

        Returns information only for AdventureWorks2014 and pubs and formats the results as a table.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType Disk

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups to disk.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType 148,107

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups with device_type 148 and 107.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -LastFull

        Returns information about the most recent full backup for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Type Full

        Returns information about all Full backups for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2016 | Get-DbaDbBackupHistory

        Returns database backup information for every database on every server listed in the Central Management Server on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a, sql2016 -Force

        Returns detailed backup history for all databases on SqlInstance2014a and sql2016.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2016 -Database db1 -RecoveryFork 38e5e84a-3557-4643-a5d5-eed607bef9c6 -Last

        If db1 has multiple recovery forks, specifying the RecoveryFork GUID will restrict the search to that fork.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance,
        [PsCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeCopyOnly,
        [Parameter(ParameterSetName = "NoLast")]
        [switch]$Force,
        [DateTime]$Since = (Get-Date '01/01/1970'),
        [ValidateScript( { ($_ -match '^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$') -or ('' -eq $_) })]
        [string]$RecoveryFork,
        [switch]$Last,
        [switch]$LastFull,
        [switch]$LastDiff,
        [switch]$LastLog,
        [string[]]$DeviceType,
        [switch]$Raw,
        [bigint]$LastLsn,
        [switch]$IncludeMirror,
        [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
        [string[]]$Type,
        [switch]$AgCheck,
        [switch]$IgnoreDiffBackup,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level System -Message "Active Parameter set: $($PSCmdlet.ParameterSetName)."
        Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        $deviceTypeMapping = @{
            'Disk'                  = 2
            'Permanent Disk Device' = 102
            'Tape'                  = 5
            'Permanent Tape Device' = 105
            'Pipe'                  = 6
            'Permanent Pipe Device' = 106
            'Virtual Device'        = 7
            'URL'                   = 9
        }
        $deviceTypeFilter = @()
        foreach ($devType in $DeviceType) {
            if ($devType -in $deviceTypeMapping.Keys) {
                $deviceTypeFilter += $deviceTypeMapping[$devType]
            } else {
                $deviceTypeFilter += $devType
            }
        }
        $backupTypeMapping = @{
            'Log'                  = 'L'
            'Full'                 = 'D'
            'File'                 = 'F'
            'Differential'         = 'I'
            'Differential File'    = 'G'
            'Partial Full'         = 'P'
            'Partial Differential' = 'Q'
        }
        $backupTypeFilter = @()
        foreach ($typeFilter in $Type) {
            $backupTypeFilter += $backupTypeMapping[$typeFilter]
        }

    }

    process {
        if ($AgCheck) {
            Stop-Function -Message "Parameter AGCheck is deprecated. This command does not check for history from replicas even if this paramater is not provided. The functionality to also get the history from all replicas if SqlInstance is part on an availability group has been moved to Get-DbaAgBackupHistory."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -ge 12) {
                $compressedFlag = $true
                # 2014 introduced encryption
                $backupCols = "
                backupset.backup_size AS TotalSize,
                backupset.compressed_backup_size as CompressedBackupSize,
                encryptor_thumbprint as EncryptorThumbprint,
                encryptor_type as EncryptorType,
                key_algorithm AS KeyAlgorithm"

            } elseif ($server.VersionMajor -ge 10 -and $server.VersionMajor -lt 12) {
                $compressedFlag = $true
                # 2008 introduced compressed_backup_size
                $backupCols = "
                backupset.backup_size AS TotalSize,
                backupset.compressed_backup_size as CompressedBackupSize,
                NULL as EncryptorThumbprint,
                NULL as EncryptorType,
                NULL AS KeyAlgorithm"
            } else {
                $compressedFlag = $false
                $backupCols = "
                backupset.backup_size AS TotalSize,
                NULL as CompressedBackupSize,
                NULL as EncryptorThumbprint,
                NULL as EncryptorType,
                NULL AS KeyAlgorithm"
            }

            $databases = @()
            if ($null -ne $Database) {
                foreach ($db in $Database) {
                    $databases += [PSCustomObject]@{ name = $db }
                }
            } else {
                $databases = $server.Databases
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }
            foreach ($d in $deviceTypeFilter) {
                $deviceTypeFilterRight = "IN ('" + ($deviceTypeFilter -Join "','") + "')"
            }
            foreach ($b in $backupTypeFilter) {
                $backupTypeFilterRight = "IN ('" + ($backupTypeFilter -Join "','") + "')"
            }

            if ($last) {
                foreach ($db in $databases) {
                    if ($since) {
                        $sinceSqlFilter = "AND backupset.backup_finish_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                    }
                    if ($RecoveryFork) {
                        $recoveryForkSqlFilter = "AND backupset.last_recovery_fork_guid ='$RecoveryFork'"
                    }
                    if ($null -eq (Get-PSCallStack)[1].Command -or '{ScriptBlock}' -eq (Get-PSCallStack)[1].Command) {
                        $forkCheckSql = "
                                SELECT
                                    database_name,
                                    MIN(database_backup_lsn) as 'FirstLsn',
                                    MAX(database_backup_lsn) as 'FinalLsn',
                                    MIN(backup_start_date) as 'MinDate',
                                    MAX(backup_finish_date) as 'MaxDate',
                                    last_recovery_fork_guid 'RecFork',
                                    count(1) as 'backupcount'
                                FROM msdb.dbo.backupset
                                WHERE database_name='$($db.name)'
                                $sinceSqlFilter
                                $recoveryForkSqlFilter
                                GROUP by database_name, last_recovery_fork_guid
                                ORDER by MaxDate Asc
                                "

                        $results = $server.ConnectionContext.ExecuteWithResults($forkCheckSql).Tables.Rows
                        if ($results.count -gt 1) {
                            if (-not $LastFull) {
                                Write-Message -Message "Found backups from multiple recovery forks for $($db.name) on $($server.name), this may affect your results" -Level Warning
                                foreach ($result in $results) {
                                    Write-Message -Message "Between $($result.MinDate)/$($result.FirstLsn) and $($result.MaxDate)/$($result.FinalLsn) $($result.database_name) was on Recovery Fork GUID $($result.RecFork) ($($result.backupcount) backups)" -Level Warning
                                }
                            }
                            if ($null -eq $RecoveryFork) {
                                $RecoveryFork = $results[-1].RecFork
                                Write-Message -Message "Defaulting to last Recovery Fork, ID - $RecoveryFork"
                            }
                        }
                    }
                    #Get the full and build upwards
                    $allBackups = @()
                    $allBackups += $fullDb = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -LastFull -raw:$Raw -DeviceType $DeviceType -IncludeCopyOnly:$IncludeCopyOnly -Since:$since -RecoveryFork $RecoveryFork
                    if ($null -eq $fullDb) {
                        Write-Message -Level Verbose -Message "No Backup found for database $($db.Name), skipping"
                        continue
                    }
                    if (-not $IgnoreDiffBackup) {
                        $diffDb = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -LastDiff -raw:$Raw -DeviceType $DeviceType -IncludeCopyOnly:$IncludeCopyOnly -Since:$since -RecoveryFork $RecoveryFork
                    }
                    if ($diffDb.LastLsn -gt $fullDb.LastLsn -and $diffDb.DatabaseBackupLSN -eq $fullDb.CheckPointLSN ) {
                        Write-Message -Level Verbose -Message "Valid Differential backup "
                        $allBackups += $diffDb
                        $tlogStartDsn = $diffDb.FirstLsn
                    } else {
                        if ($IgnoreDiffBackup) {
                            Write-Message -Level Verbose -Message "Ignoring Diff backups, so using Full backup FirstLSN"
                        } else {
                            Write-Message -Level Verbose -Message "No Diff found"
                        }
                        $tlogStartDsn = $fullDb.FirstLsn
                    }

                    if ($IncludeCopyOnly -eq $true) {
                        Write-Message -Level Verbose -Message 'Copy Only check'
                        $allBackups += Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -raw:$raw -DeviceType $DeviceType -LastLsn $tlogStartDsn -IncludeCopyOnly:$IncludeCopyOnly -Since:$since -RecoveryFork $RecoveryFork | Where-Object { $_.Type -eq 'Log' -and [bigint]$_.LastLsn -gt [bigint]$tlogStartDsn -and $_.LastRecoveryForkGuid -eq $fullDb.LastRecoveryForkGuid }
                    } else {
                        $allBackups += Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -raw:$raw -DeviceType $DeviceType -LastLsn $tlogStartDsn -IncludeCopyOnly:$IncludeCopyOnly -Since:$since -RecoveryFork $RecoveryFork | Where-Object { $_.Type -eq 'Log' -and [bigint]$_.LastLsn -gt [bigint]$tlogStartDsn -and [bigint]$_.DatabaseBackupLSN -eq [bigint]$fullDb.CheckPointLSN -and $_.LastRecoveryForkGuid -eq $fullDb.LastRecoveryForkGuid }
                    }
                    #This line does the output for -Last!!!
                    $allBackups | Sort-Object -Property LastLsn, Type
                }
                continue
            }

            if ($LastFull -or $LastDiff -or $LastLog) {
                if ($LastFull) {
                    $first = 'D'; $second = 'P'
                }
                if ($LastDiff) {
                    $first = 'I'; $second = 'Q'
                }
                if ($LastLog) {
                    $first = 'L'; $second = 'L'
                }
                $databases = $databases | Select-Object -Unique -Property Name
                $sql = ""
                foreach ($db in $databases) {
                    Write-Message -Level Verbose -Message "Processing $($db.name)" -Target $db
                    if ($since) {
                        $sinceSqlFilter = "AND backupset.backup_finish_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                    }
                    if ($RecoveryFork) {
                        $recoveryForkSqlFilter = "AND backupset.last_recovery_fork_guid ='$RecoveryFork'"
                    }
                    if ((Get-PSCallStack)[1].Command -notlike ' Get-DbaDbBackupHistory*') {
                        $forkCheckSql = "
                            SELECT
                                database_name,
                                MIN(database_backup_lsn) as 'FirstLsn',
                                MAX(database_backup_lsn) as 'FinalLsn',
                                MIN(backup_start_date) as 'MinDate',
                                MAX(backup_finish_date) as 'MaxDate',
                                last_recovery_fork_guid 'RecFork',
                                count(1) as 'backupcount'
                            FROM msdb.dbo.backupset
                            WHERE database_name='$($db.name)'
                            $sinceSqlFilter
                            $recoveryForkSqlFilter
                            GROUP by database_name, last_recovery_fork_guid
                        "

                        $results = $server.ConnectionContext.ExecuteWithResults($forkCheckSql).Tables.Rows
                        if ($results.count -gt 1) {
                            if (-not $LastFull) {
                                Write-Message -Message "Found backups from multiple recovery forks for $($db.name) on $($server.name), this may affect your results" -Level Warning
                                foreach ($result in $results) {
                                    Write-Message -Message "Between $($result.MinDate)/$($result.FirstLsn) and $($result.MaxDate)/$($result.FinalLsn) $($result.database_name) was on Recovery Fork GUID $($result.RecFork) ($($result.backupcount) backups)" -Level Warning
                                }
                            }
                        }
                    }
                    $whereCopyOnly = $null
                    if ($true -ne $IncludeCopyOnly) {
                        $whereCopyOnly = " AND is_copy_only='0' "
                    }
                    if ($true -ne $IncludeMirror) {
                        $whereMirror = " AND mediafamily.mirror='0' "
                    }
                    if ($deviceTypeFilter) {
                        $devTypeFilterWhere = "AND mediafamily.device_type $deviceTypeFilterRight"
                    }
                    if ($since) {
                        $sinceSqlFilter = "AND backupset.backup_finish_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                    }
                    # recap for future editors (as this has been discussed over and over):
                    #   - original editors (from hereon referred as "we") rank over backupset.last_lsn desc, backupset.backup_finish_date desc for a good reason: DST
                    #     all times are recorded with the timezone of the server
                    #   - we thought about ranking over backupset.backup_set_id desc, backupset.last_lsn desc, backupset.backup_finish_date desc
                    #     but there is no explicit documentation about "when" a row gets inserted into backupset. Theoretically it _could_
                    #     happen that backup_set_id for the same database has not the same order of last_lsn.
                    #   - given ultimately to restore something lsn IS the source of truth, we decided to trust that and only that
                    #   - we know that sometimes it happens to drop a database without deleting the history. Assuming then to create a database with the same name,
                    #     and given the lsn are composed in the first part by the VLF SeqID, it happens seldomly that for the same database_name backupset holds
                    #     last_lsn out of order. To avoid this behaviour, we filter by database_guid choosing the guid that has MAX(backup_finish_date), as we know
                    #     last_lsn cannot be out-of-order for the same database, and the same database cannot have different database_guid
                    #   - because someone could restore a very old backup with low lsn values and continue to use this database we filter
                    #     not only by database_guid but also by the recovery fork of the last backup (see issue #6730 for more details)
                    $sql += "SELECT
                        a.BackupSetRank,
                        a.Server,
                        '' as AvailabilityGroupName,
                        a.[Database],
                        a.Username,
                        a.Start,
                        a.[End],
                        a.Duration,
                        a.[Path],
                        a.Type,
                        a.TotalSize,
                        a.CompressedBackupSize,
                        a.MediaSetId,
                        a.BackupSetID,
                        a.Software,
                        a.position,
                        a.first_lsn,
                        a.database_backup_lsn,
                        a.checkpoint_lsn,
                        a.last_lsn,
                        a.first_lsn as 'FirstLSN',
                        a.database_backup_lsn as 'DatabaseBackupLsn',
                        a.checkpoint_lsn as 'CheckpointLsn',
                        a.last_lsn as 'LastLsn',
                        a.software_major_version,
                        a.DeviceType,
                        a.is_copy_only,
                        a.last_recovery_fork_guid,
                        a.recovery_model,
                        a.EncryptorThumbprint,
                        a.EncryptorType,
                        a.KeyAlgorithm
                    FROM (
                        SELECT
                        RANK() OVER (ORDER BY backupset.last_lsn desc, backupset.backup_finish_date DESC) AS 'BackupSetRank',
                        backupset.database_name AS [Database],
                        backupset.user_name AS Username,
                        backupset.backup_start_date AS Start,
                        backupset.server_name as [Server],
                        backupset.backup_finish_date AS [End],
                        DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
                        mediafamily.physical_device_name AS Path,
                        $backupCols,
                        CASE backupset.type
                        WHEN 'L' THEN 'Log'
                        WHEN 'D' THEN 'Full'
                        WHEN 'F' THEN 'File'
                        WHEN 'I' THEN 'Differential'
                        WHEN 'G' THEN 'Differential File'
                        WHEN 'P' THEN 'Partial Full'
                        WHEN 'Q' THEN 'Partial Differential'
                        ELSE NULL
                        END AS Type,
                        backupset.media_set_id AS MediaSetId,
                        mediafamily.media_family_id as mediafamilyid,
                        backupset.backup_set_id as BackupSetID,
                        CASE mediafamily.device_type
                        WHEN 2 THEN 'Disk'
                        WHEN 102 THEN 'Permanent Disk Device'
                        WHEN 5 THEN 'Tape'
                        WHEN 105 THEN 'Permanent Tape Device'
                        WHEN 6 THEN 'Pipe'
                        WHEN 106 THEN 'Permanent Pipe Device'
                        WHEN 7 THEN 'Virtual Device'
                        WHEN 9 THEN 'URL'
                        ELSE 'Unknown'
                        END AS DeviceType,
                        backupset.position,
                        backupset.first_lsn,
                        backupset.database_backup_lsn,
                        backupset.checkpoint_lsn,
                        backupset.last_lsn,
                        backupset.software_major_version,
                        mediaset.software_name AS Software,
                        backupset.is_copy_only,
                        backupset.last_recovery_fork_guid,
                        backupset.recovery_model
                        FROM msdb..backupmediafamily AS mediafamily
                        JOIN msdb..backupmediaset AS mediaset ON mediafamily.media_set_id = mediaset.media_set_id
                        JOIN msdb..backupset AS backupset ON backupset.media_set_id = mediaset.media_set_id
                        JOIN (
                            SELECT TOP 1 database_name, database_guid, last_recovery_fork_guid
                            FROM msdb..backupset
                            WHERE database_name = '$($db.Name)'
                            ORDER BY backup_finish_date DESC
                            ) AS last_guids ON last_guids.database_name = backupset.database_name AND last_guids.database_guid = backupset.database_guid AND last_guids.last_recovery_fork_guid = backupset.last_recovery_fork_guid
                    WHERE (type = '$first' OR type = '$second')
                    $whereCopyOnly
                    $devTypeFilterWhere
                    $sinceSqlFilter
                    $recoveryForkSqlFilter
                    $whereMirror
                    ) AS a
                    WHERE a.BackupSetRank = 1
                    ORDER BY a.Type;
                    "
                }
                $sql = $sql -join "; "
            } else {
                if ($Force -eq $true) {
                    $select = "SELECT * "
                } else {
                    $select = "
                    SELECT
                        backupset.database_name AS [Database],
                        backupset.user_name AS Username,
                        backupset.server_name as [server],
                        backupset.backup_start_date AS [Start],
                        backupset.backup_finish_date AS [End],
                        DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
                        mediafamily.physical_device_name AS Path,
                        $backupCols,
                        CASE backupset.type
                            WHEN 'L' THEN 'Log'
                            WHEN 'D' THEN 'Full'
                            WHEN 'F' THEN 'File'
                            WHEN 'I' THEN 'Differential'
                            WHEN 'G' THEN 'Differential File'
                            WHEN 'P' THEN 'Partial Full'
                            WHEN 'Q' THEN 'Partial Differential'
                            ELSE NULL
                        END AS Type,
                        backupset.media_set_id AS MediaSetId,
                        mediafamily.media_family_id as MediaFamilyId,
                        backupset.backup_set_id as BackupSetId,
                        CASE mediafamily.device_type
                            WHEN 2 THEN 'Disk'
                            WHEN 102 THEN 'Permanent Disk Device'
                            WHEN 5 THEN 'Tape'
                            WHEN 105 THEN 'Permanent Tape Device'
                            WHEN 6 THEN 'Pipe'
                            WHEN 106 THEN 'Permanent Pipe Device'
                            WHEN 7 THEN 'Virtual Device'
                            WHEN 9 THEN 'URL'
                            ELSE 'Unknown'
                        END AS DeviceType,
                        backupset.position,
                        backupset.first_lsn,
                        backupset.database_backup_lsn,
                        backupset.checkpoint_lsn,
                        backupset.last_lsn,
                        backupset.first_lsn as 'FirstLSN',
                        backupset.database_backup_lsn as 'DatabaseBackupLsn',
                        backupset.checkpoint_lsn as 'CheckpointLsn',
                        backupset.last_lsn as 'LastLsn',
                        backupset.software_major_version,
                        mediaset.software_name AS Software,
                        backupset.is_copy_only,
                        backupset.last_recovery_fork_guid,
                        backupset.recovery_model"
                }

                $from = " FROM msdb..backupmediafamily mediafamily
                INNER JOIN msdb..backupmediaset mediaset ON mediafamily.media_set_id = mediaset.media_set_id
                INNER JOIN msdb..backupset backupset ON backupset.media_set_id = mediaset.media_set_id"
                if ($Database -or $ExcludeDatabase -or $Since -or $Last -or $LastFull -or $LastLog -or $LastDiff -or $deviceTypeFilter -or $LastLsn -or $backupTypeFilter) {
                    $where = " WHERE "
                }

                $whereArray = @()

                if ($Database.length -gt 0 -or $ExcludeDatabase.length -gt 0) {
                    $dbList = $databases.Name -join "','"
                    $whereArray += "database_name IN ('$dbList')"
                }

                if ($true -ne $IncludeCopyOnly) {
                    $whereArray += "is_copy_only='0'"
                }

                if ($Last -or $LastFull -or $LastLog -or $LastDiff) {
                    $tempWhere = $whereArray -join " AND "
                    $whereArray += "type = 'Full' AND mediaset.media_set_id = (SELECT TOP 1 mediaset.media_set_id $from $tempWhere ORDER BY backupset.last_lsn DESC)"
                }

                if ($IgnoreDiffBackup) {
                    $whereArray += "backupset.type not in ('I','G','Q')"
                }

                if ($null -ne $Since) {
                    $whereArray += "backupset.backup_finish_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                }

                if ($deviceTypeFilter) {
                    $whereArray += "mediafamily.device_type $deviceTypeFilterRight"
                }
                if ($backupTypeFilter) {
                    $whereArray += "backupset.type $backupTypeFilterRight"
                }

                if ($LastLsn) {
                    $whereArray += "backupset.last_lsn > $LastLsn"
                }
                if ($where.Length -gt 0) {
                    $whereArray = $whereArray -join " AND "
                    $where = "$where $whereArray"
                }

                $sql = "$select $from $where ORDER BY backupset.last_lsn DESC"
            }

            Write-Message -Level Debug -Message "SQL Statement: `n$sql"
            Write-Message -Level SomewhatVerbose -Message "Executing sql query on $server."
            $results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows | Select-Object * -ExcludeProperty BackupSetRank, RowError, RowState, Table, ItemArray, HasErrors

            if ($raw) {
                Write-Message -Level SomewhatVerbose -Message "Processing as Raw Output."
                $results | Select-Object *, @{ Name = "FullName"; Expression = { $_.Path } }
                Write-Message -Level SomewhatVerbose -Message "$($results.Count) result sets found."
            } else {
                Write-Message -Level SomewhatVerbose -Message "Processing as grouped output."
                $groupedResults = $results | Group-Object -Property BackupsetId
                Write-Message -Level SomewhatVerbose -Message "$($groupedResults.Count) result-groups found."
                $groupResults = @()
                $backupSetIds = $groupedResults.Name
                $backupSetIdsList = "Insert into #BackupSetIds( backup_set_id ) Values (" + ($backupSetIds -join ");Insert into #BackupSetIds( backup_set_id ) Values (") + ")"
                if ($groupedResults.Count -gt 0) {
                    $TempTable = "Create table #BackupSetIds ( backup_set_id int ); $backupSetIdsList;"
                    $fileAllSql = "$TempTable SELECT bf.backup_set_id, file_type as FileType, logical_name as LogicalName, physical_name as PhysicalName
                    FROM msdb..backupfile bf
                    join #BackupSetIds bs
                        on bs.backup_set_id = bf.backup_set_id
                    WHERE [state] <> 8;
                    Drop Table #BackupSetIds;" # <> 8 Used to eliminate data files that no longer exist
                    Write-Message -Level Debug -Message "FileSQL: $fileAllSql"
                    $fileListResults = $server.Query($fileAllSql)
                } else {
                    $fileListResults = @()
                }
                $fileListHash = @{ }
                foreach ($fl in $fileListResults) {
                    if (-not($fileListHash.ContainsKey($fl.backup_set_id))) {
                        $fileListHash[$fl.backup_set_id] = @()
                    }
                    $fileListHash[$fl.backup_set_id] += $fl
                }
                foreach ($group in $groupedResults) {
                    $commonFields = $group.Group[0]
                    $groupLength = $group.Group.Count
                    if ($groupLength -eq 1) {
                        $start = $commonFields.Start
                        $end = $commonFields.End
                        $duration = New-TimeSpan -Seconds $commonFields.Duration
                    } else {
                        $start = ($group.Group.Start | Measure-Object -Minimum).Minimum
                        $end = ($group.Group.End | Measure-Object -Maximum).Maximum
                        $duration = New-TimeSpan -Seconds ($group.Group.Duration | Measure-Object -Maximum).Maximum
                    }
                    $compressedBackupSize = $commonFields.CompressedBackupSize
                    if ($compressedFlag -eq $true) {
                        $ratio = [Math]::Round(($commonFields.TotalSize) / ($compressedBackupSize), 2)
                    } else {
                        $compressedBackupSize = $null
                        $ratio = 1
                    }
                    $historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
                    $historyObject.ComputerName = $server.ComputerName
                    $historyObject.InstanceName = $server.ServiceName
                    $historyObject.SqlInstance = $server.DomainInstanceName
                    $historyObject.Database = $commonFields.Database
                    $historyObject.UserName = $commonFields.UserName
                    $historyObject.Start = $start
                    $historyObject.End = $end
                    $historyObject.Duration = $duration
                    $historyObject.Path = $group.Group.Path
                    $historyObject.TotalSize = $commonFields.TotalSize
                    $historyObject.CompressedBackupSize = $compressedBackupSize
                    $historyObject.CompressionRatio = $ratio
                    $historyObject.Type = $commonFields.Type
                    $historyObject.BackupSetId = $commonFields.BackupSetId
                    $historyObject.DeviceType = $commonFields.DeviceType
                    $historyObject.Software = $commonFields.Software
                    $historyObject.FullName = $group.Group.Path
                    $historyObject.FileList = $fileListHash[$commonFields.BackupSetID] | Select-Object FileType, LogicalName, PhysicalName
                    $historyObject.Position = $commonFields.Position
                    $historyObject.FirstLsn = $commonFields.First_LSN
                    $historyObject.DatabaseBackupLsn = $commonFields.database_backup_lsn
                    $historyObject.CheckpointLsn = $commonFields.checkpoint_lsn
                    $historyObject.LastLsn = $commonFields.Last_Lsn
                    $historyObject.SoftwareVersionMajor = $commonFields.Software_Major_Version
                    $historyObject.IsCopyOnly = ($commonFields.is_copy_only -eq 1)
                    $historyObject.LastRecoveryForkGuid = $commonFields.last_recovery_fork_guid
                    $historyObject.RecoveryModel = $commonFields.recovery_model
                    $historyObject.EncryptorType = $commonFields.EncryptorType
                    $historyObject.EncryptorThumbprint = $commonFields.EncryptorThumbprint
                    $historyObject.KeyAlgorithm = $commonFields.KeyAlgorithm
                    $historyObject
                }
                $groupResults | Sort-Object -Property LastLsn, Type
            }
        }
    }
}

# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBAN/EVczSzvy7R
# WV6x6LESxLc89YWFwbe4mpX4izPGs6CCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBcjYCrUPRMvpN0rlIOo5dbSkFQ0l76MeVj
# nnnlJqYrtDANBgkqhkiG9w0BAQEFAASCAQA+mQxWkAhd4VsSCAcDLxwaGo2KI+zT
# XgQEOrSuwAosNFMH+roLiZaAE+iSY7h5Mb7YgPIRC5RyAktZ+xcDSRDS7mB0CDWl
# 9PzhsfONMRhCp4UIfus/pacqhChQxa1rsHAL2WQ+DgT+PnXsZCvwW69Ip1PXOTUv
# LMfxkwVceLOyDZCLW4/KV6SitbOKSq+kZMgZ2EW7VhSWaUQAUKIE+8y2/ecj//0P
# J8161wTRNiUwQKFLb3x1jwoLsrTuvwoe14WAzMIndaprz4NjoMcbVjIYTKxZp37L
# k6rub1U4dIdMYFc5QgFhRXMVmHOpvmN2+kmSNwpqP1c9LccCxIgmusPgoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI1NFowLwYJKoZIhvcNAQkEMSIEIHRxKVmZ
# PXovj1TpBYuntPVNxIUSC81VfIQcQuI8Ai7ZMA0GCSqGSIb3DQEBAQUABIICAB63
# Ztm71tKUaNb6J1MPOp5yklhTvgDE3WU6d39ovelTnggoQUAa0emoYsf9QeB4S7Lf
# LAUSXEYxEFDI6jQsHhnMZDyvj+XZHsPmFuZ+dM+Gg12TAZ2dhJpPIo68KYsu9aue
# YmKpgMT5gK4AOOCR3mTbEu16v+QsWt6QvF9tn12D/eYKmFU9Gd4GkU9hlD+fGKcl
# biCKaaQiH3cGcSqnr19cVzyVzAI7BKpXuecuT/T+yv+wJRuZPM9gigh/FKHbhvOC
# AYr1pX0orNliixOK0gKhJxgV0wdHWRJt3k/MN6AQpMcrvdPWmY9vItcnw5YYlV1o
# CpQ37xf1XoEZS+pzJHl/dylI3VyaLZ6EzTuD5nTI6wh7c0Ik4A5gqu/kYxSUzG+q
# KMfJp0c+BBFBnCBxPTAIu6+BoO3JrP8QfcZtUqGhvIiae3QwM1BmHHadM2u2Fujz
# /K6DU2l7A4iBjhuek1McDixI+dnnclvskNxTn7M/CsFs9gqJJO+1davHNlmuZVF5
# 58usHFOhUrMJFgmpWCMU9VPCiV0ggbluE6hT2efF0hiox8z+O9q6C6V3Ya0KKU9F
# 1XWGI92Mov9CD1ZlpUUYUweoysDFnNSYm3Q1Qe4u3Ww5i4V7CiXbYNyCBDh+nyJE
# UQ8YPqz162RoAQqHexh2x0DM9Tu1Kbcw3MLfpf/r
# SIG # End signature block
