function Add-DbaAgDatabase {
    <#
    .SYNOPSIS
        Adds database(s) to an Availability Group on a SQL Server instance.

    .DESCRIPTION
        Adds database(s) to an Availability Group on a SQL Server instance.

        After checking for prerequisites, the commands runs these five steps for every database:
        * Step 1: Setting seeding mode if needed.
          - If -SeedingMode is used and the current seeding mode of the replica is not in the desired mode, the seeding mode of the replica is changed.
          - The seeding mode will not be changed back but stay in this mode.
          - If the seeding mode is changed to Automatic, the necessary rights to create databases will be granted.
        * Step 2: Running backup and restore if needed.
          - Action is only taken for replicas with a desired seeding mode of Manual and where the database does not yet exist.
          - If -UseLastBackup is used, the restore will be performed based on the backup history of the database.
          - Otherwise a full and log backup will be taken at the primary and those will be restored at the replica using the same folder structure.
        * Step 3: Add the database to the Availability Group on the primary replica.
          - This step is skipped, if the database is already part of the Availability Group.
        * Step 4: Add the database to the Availability Group on the secondary replicas.
          - This step is skipped for those replicas, where the database is already joined to the Availability Group.
        * Step 5: Wait for the database to finish joining the Availability Group on the secondary replicas.

        Use Test-DbaAvailabilityGroup with -AddDatabase to test if all prerequisites are met.

        If you have special requirements for the setup for the database at the replicas,
        perform the backup and restore part with Backup-DbaDatabase and Restore-DbaDatabase in advance.
        Please make sure that the last log backup has been restored before running Add-DbaAgDatabase.

    .PARAMETER SqlInstance
        The primary replica of the Availability Group. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to add.

    .PARAMETER AvailabilityGroup
        The name of the Availability Group where the databases will be added.

    .PARAMETER Secondary
        Not required - the command will figure this out. But use this parameter if secondary replicas listen on a non default port.
        This parameter can be used to only add the databases on specific secondary replicas.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase, Get-DbaDbSharePoint and more.

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual uses full and log backup to initially transfer the data to the secondary replica. The command skips this if the database is found in restoring state at the secondary replica.

        If not specified, the setting from the availability group replica will be used. Otherwise the setting will be updated.

    .PARAMETER SharedPath
        The network share where the backups will be backed up and restored from.

        Each SQL Server service account must have access to this share.

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER UseLastBackup
        Use the last full and log backup of the database. A log backup must be the last backup.

    .PARAMETER AdvancedBackupParams
        Provide additional parameters to the backup command as a hashtable.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net | Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaAgDatabase

    .EXAMPLE
        PS C:\> Add-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup ag1 -Database db1, db2 -Confirm

        Adds db1 and db2 to ag1 on sql2017a. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a | Out-GridView -Passthru | Add-DbaAgDatabase -AvailabilityGroup ag1

        Adds selected databases from sql2017a to ag1

    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster | Add-DbaAgDatabase -AvailabilityGroup SharePoint

        Adds SharePoint databases as found in SharePoint_Config on sqlcluster to ag1 on sqlcluster

    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster -ConfigDatabase SharePoint_Config_2019 | Add-DbaAgDatabase -AvailabilityGroup SharePoint

        Adds SharePoint databases as found in SharePoint_Config_2019 on sqlcluster to ag1 on sqlcluster

    .EXAMPLE
        PS C:\> Add-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup ag1 -Database db1 -Secondary sql2017b -SeedingMode Manual -SharedPath \\FS\Backup -AdvancedBackupParams @{ CompressBackup = $true ; FileCount = 3 }

        Adds db1 to ag1 on sql2017a and sql2017b. Uses compression and three files while taking the backups.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Pipeline', Mandatory = $true, Position = 0)]
        [string]$AvailabilityGroup,
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true)]
        [string[]]$Database,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [DbaInstanceParameter[]]$Secondary,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [PSCredential]$SecondarySqlCredential,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [string]$SharedPath,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$UseLastBackup,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [hashtable]$AdvancedBackupParams,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        # We have three while loops, that need a timeout to not loop forever if somethings goes wrong:
        # while ($agDb.State -ne 'Existing')         - should only take milliseconds, so we set a default timeout of one minute
        # while ($replicaAgDb.State -ne 'Existing')  - should only take milliseconds, so we set a default timeout of one minute
        # while ($stillWaiting)                      - can take a long time with automatic seeding, but progress is displayed, so we set a default timeout of one day
        # We will use two timeout configuration values, as we don't want to add more timeout parameters to the command. We will store the timeouts in seconds.
        # The timout for synchronization can be set to a lower value to end the command even when the synchronization is not finished yet.
        # The synchronization will continue even the command or the powershell session stops.
        # Even when the SQL Server instance is restarted, the synchronization will continue after the restart.
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.timeout.existing -Value 60
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.timeout.synchronization -Value 86400
        $timeoutExisting = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.timeout.existing -Fallback 60
        $timeoutSynchronization = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.timeout.synchronization -Fallback 86400

        # While in a while loop, configure the time in milliseconds to wait for the next test:
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.wait.while -Value 100
        $waitWhile = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.wait.while -Fallback 100

        # With automatic seeding we add the current seeding progress in verbose output and a progress bar. This can be disabled:
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.report.seeding -Value $true
        $reportSeeding = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.report.seeding -Fallback $true
    }

    process {
        # We store information for the progress bar in a hashtable suitable for splatting.
        $progress = @{ }
        $progress['Id'] = Get-Random
        $progress['Activity'] = "Adding database(s) to Availability Group $AvailabilityGroup."

        $testResult = @( )

        foreach ($dbName in $Database) {
            try {
                $progress['Status'] = "Test prerequisites for joining database $dbName."
                Write-Progress @progress
                $testSplat = @{
                    SqlInstance            = $SqlInstance
                    SqlCredential          = $SqlCredential
                    Secondary              = $Secondary
                    SecondarySqlCredential = $SecondarySqlCredential
                    AvailabilityGroup      = $AvailabilityGroup
                    AddDatabase            = $dbName
                    UseLastBackup          = $UseLastBackup
                    EnableException        = $true
                }
                if ($SeedingMode) { $testSplat['SeedingMode'] = $SeedingMode }
                if ($SharedPath) { $testSplat['SharedPath'] = $SharedPath }
                $testResult += Test-DbaAvailabilityGroup @testSplat
            } catch {
                Stop-Function -Message "Testing prerequisites for joining database $dbName to Availability Group $AvailabilityGroup failed." -ErrorRecord $_ -Continue
            }
        }

        foreach ($db in $InputObject) {
            try {
                $progress['Status'] = "Test prerequisites for joining database $($db.Name)."
                Write-Progress @progress
                $testSplat = @{
                    SqlInstance            = $db.Parent
                    Secondary              = $Secondary
                    SecondarySqlCredential = $SecondarySqlCredential
                    AvailabilityGroup      = $AvailabilityGroup
                    AddDatabase            = $db.Name
                    UseLastBackup          = $UseLastBackup
                    EnableException        = $true
                }
                if ($SeedingMode) { $testSplat['SeedingMode'] = $SeedingMode }
                if ($SharedPath) { $testSplat['SharedPath'] = $SharedPath }
                $testResult += Test-DbaAvailabilityGroup @testSplat
            } catch {
                Stop-Function -Message "Testing prerequisites for joining database $($db.Name) to Availability Group $AvailabilityGroup failed." -ErrorRecord $_ -Continue
            }
        }

        Write-Message -Level Verbose -Message "Test for prerequisites returned $($testResult.Count) databases that will be joined to the Availability Group $AvailabilityGroup."

        foreach ($result in $testResult) {
            $server = $result.PrimaryServerSMO
            $ag = $result.AvailabilityGroupSMO
            $db = $result.DatabaseSMO
            $replicaServerSMO = $result.ReplicaServerSMO
            $restoreNeeded = $result.RestoreNeeded
            $backups = $result.Backups
            $replicaAgDbSMO = @{ }
            $targetSynchronizationState = @{ }
            $output = @( )

            $progress['Activity'] = "Adding database $($db.Name) to Availability Group $AvailabilityGroup."

            $progress['Status'] = "Step 1/5: Setting seeding mode if needed."
            Write-Message -Level Verbose -Message $progress['Status']
            Write-Progress @progress

            if ($SeedingMode) {
                Write-Message -Level Verbose -Message "Setting seeding mode to $SeedingMode."
                $failure = $false
                foreach ($replicaName in $replicaServerSMO.Keys) {
                    $replica = $ag.AvailabilityReplicas[$replicaName]
                    if ($replica.SeedingMode -ne $SeedingMode) {
                        if ($Pscmdlet.ShouldProcess($server, "Setting seeding mode for replica $replica to $SeedingMode")) {
                            try {
                                Write-Message -Level Verbose -Message "Setting seeding mode for replica $replica to $SeedingMode."
                                $replica.SeedingMode = $SeedingMode
                                $replica.Alter()
                                if ($SeedingMode -eq 'Automatic') {
                                    Write-Message -Level Verbose -Message "Setting GrantAvailabilityGroupCreateDatabasePrivilege on server $($replicaServerSMO[$replicaName]) for Availability Group $AvailabilityGroup."
                                    $null = Grant-DbaAgPermission -SqlInstance $replicaServerSMO[$replicaName] -Type AvailabilityGroup -AvailabilityGroup $AvailabilityGroup -Permission CreateAnyDatabase
                                }
                            } catch {
                                $failure = $true
                                Stop-Function -Message "Failed setting seeding mode for replica $replica to $SeedingMode." -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }
                if ($failure) {
                    Stop-Function -Message "Failed setting seeding mode to $SeedingMode." -Continue
                }
            }

            $progress['Status'] = "Step 2/5: Running backup and restore if needed."
            Write-Message -Level Verbose -Message $progress['Status']
            Write-Progress @progress

            if ($restoreNeeded.Count -gt 0) {
                if (-not $backups) {
                    if ($Pscmdlet.ShouldProcess($server, "Taking full and log backup of database $($db.Name)")) {
                        try {
                            Write-Message -Level Verbose -Message "Taking full and log backup of database $($db.Name)."
                            if ($AdvancedBackupParams) {
                                $fullbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException @AdvancedBackupParams
                                $logbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException @AdvancedBackupParams
                            } else {
                                $fullbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException
                                $logbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException
                            }
                            $backups = $fullbackup, $logbackup
                        } catch {
                            Stop-Function -Message "Failed to take full and log backup of database $($db.Name)." -ErrorRecord $_ -Continue
                        }
                    }
                }
                $failure = $false
                foreach ($replicaName in $restoreNeeded.Keys) {
                    if ($Pscmdlet.ShouldProcess($replicaServerSMO[$replicaName], "Restore database $($db.Name) to replica $replicaName")) {
                        try {
                            Write-Message -Level Verbose -Message "Restore database $($db.Name) to replica $replicaName."
                            $null = $backups | Restore-DbaDatabase -SqlInstance $replicaServerSMO[$replicaName] -NoRecovery -TrustDbBackupHistory -ReuseSourceFolderStructure -EnableException
                        } catch {
                            $failure = $true
                            Stop-Function -Message "Failed to restore database $($db.Name) to replica $replicaName." -ErrorRecord $_ -Continue
                        }
                    }
                }
                if ($failure) {
                    Stop-Function -Message "Failed to restore database $($db.Name)." -Continue
                }
            }

            $progress['Status'] = "Step 3/5: Add the database to the Availability Group on the primary replica."
            Write-Message -Level Verbose -Message $progress['Status']

            if ($Pscmdlet.ShouldProcess($server, "Add database $($db.Name) to Availability Group $AvailabilityGroup on the primary replica")) {
                try {
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on is not yet known."
                    Write-Message -Level Verbose -Message "Object of type AvailabilityDatabase for $($db.Name) will be created. $($progress['CurrentOperation'])"
                    Write-Progress @progress

                    if ($ag.AvailabilityDatabases.Name -contains $db.Name) {
                        Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the primary replica."
                    } else {
                        $agDb = Get-DbaAgDatabase -SqlInstance $server -AvailabilityGroup $ag.Name -Database $db.Name
                        $agDb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($ag, $db.Name)
                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State)."
                        Write-Message -Level Verbose -Message "Object of type AvailabilityDatabase for $($db.Name) is created. $($progress['CurrentOperation'])"
                        Write-Progress @progress

                        $agDb.Create()
                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State)."
                        Write-Message -Level Verbose -Message "Method Create of AvailabilityDatabase for $($db.Name) is executed. $($progress['CurrentOperation'])"
                        Write-Progress @progress

                        # Wait for state to become Existing
                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
                        $timeout = (Get-Date).AddSeconds($timeoutExisting)
                        while ($agDb.State -ne 'Existing') {
                            $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State), waiting for Existing."
                            Write-Message -Level Verbose -Message $progress['CurrentOperation']
                            Write-Progress @progress

                            if ((Get-Date) -gt $timeout) {
                                Stop-Function -Message "Failed to add database $($db.Name) to Availability Group $AvailabilityGroup. Timeout of $timeoutExisting seconds is reached. State of AvailabilityDatabase for $($db.Name) is still $($agDb.State)." -Continue
                            }
                            Start-Sleep -Milliseconds $waitWhile
                            $agDb.Refresh()
                        }

                        # Get customized SMO for the output
                        $output += Get-DbaAgDatabase -SqlInstance $server -AvailabilityGroup $AvailabilityGroup -Database $db.Name -EnableException
                    }
                } catch {
                    Stop-Function -Message "Failed to add database $($db.Name) to Availability Group $AvailabilityGroup" -ErrorRecord $_ -Continue
                }
            }

            $progress['Status'] = "Step 4/5: Add the database to the Availability Group on the secondary replicas."
            Write-Message -Level Verbose -Message $progress['Status']

            $failure = $false
            foreach ($replicaName in $replicaServerSMO.Keys) {
                if ($Pscmdlet.ShouldProcess($replicaServerSMO[$replicaName], "Add database $($db.Name) to Availability Group $AvailabilityGroup on replica $replicaName")) {
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is not yet known."
                    Write-Message -Level Verbose -Message $progress['CurrentOperation']
                    Write-Progress @progress

                    try {
                        $replicaAgDb = Get-DbaAgDatabase -SqlInstance $replicaServerSMO[$replicaName] -AvailabilityGroup $AvailabilityGroup -Database $db.Name -EnableException
                    } catch {
                        $failure = $true
                        Stop-Function -Message "Failed to get database $($db.Name) on replica $replicaName." -ErrorRecord $_ -Continue
                    }

                    if ($replicaAgDb.IsJoined) {
                        Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the replica $replicaName."
                        $replicaAgDbSMO[$replicaName] = $replicaAgDb
                    } else {
                        # Save SMO in array for the output
                        $output += $replicaAgDb
                        # Save SMO in hashtable for further processing
                        $replicaAgDbSMO[$replicaName] = $replicaAgDb
                        # Save target targetSynchronizationState for further processing
                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.availabilityreplicaavailabilitymode
                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.availabilitydatabasesynchronizationstate
                        $availabilityMode = $ag.AvailabilityReplicas[$replicaName].AvailabilityMode
                        if ($availabilityMode -eq 'AsynchronousCommit') {
                            $targetSynchronizationState[$replicaName] = 'Synchronizing'
                        } elseif ($availabilityMode -eq 'SynchronousCommit') {
                            $targetSynchronizationState[$replicaName] = 'Synchronized'
                        } else {
                            $failure = $true
                            Stop-Function -Message "Unexpected value '$availabilityMode' for AvailabilityMode on replica $replicaName." -Continue
                        }

                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is $($replicaAgDb.State)."
                        Write-Message -Level Verbose -Message $progress['CurrentOperation']
                        Write-Progress @progress

                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
                        $timeout = (Get-Date).AddSeconds($timeoutExisting)
                        while ($replicaAgDb.State -ne 'Existing') {
                            $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is $($replicaAgDb.State), waiting for Existing."
                            Write-Message -Level Verbose -Message $progress['CurrentOperation']
                            Write-Progress @progress

                            if ((Get-Date) -gt $timeout) {
                                Stop-Function -Message "Failed to add database $($db.Name) on replica $replicaName. Timeout of $timeoutExisting seconds is reached. State of AvailabilityDatabase for $db is still $($replicaAgDb.State)." -Continue
                            }
                            Start-Sleep -Milliseconds $waitWhile
                            $replicaAgDb.Refresh()
                        }

                        # With automatic seeding, .JoinAvailablityGroup() is not needed, just wait for the magic to happen
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -ne 'Automatic') {
                            try {
                                $progress['CurrentOperation'] = "Joining database $($db.Name) on replica $replicaName."
                                Write-Message -Level Verbose -Message $progress['CurrentOperation']
                                Write-Progress @progress

                                $replicaAgDb.JoinAvailablityGroup()
                            } catch {
                                $failure = $true
                                Stop-Function -Message "Failed to join database $($db.Name) on replica $replicaName." -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }
            }
            if ($failure) {
                Stop-Function -Message "Failed to add or join database $($db.Name)." -Continue
            }

            # Now we have configured everything and we only have to wait...

            $progress['Status'] = "Step 5/5: Wait for the database to finish joining the Availability Group on the secondary replicas."
            $progress['CurrentOperation'] = ''
            Write-Message -Level Verbose -Message $progress['Status']
            Write-Progress @progress

            if ($Pscmdlet.ShouldProcess($server, "Wait for the database $($db.Name) to finish joining the Availability Group $AvailabilityGroup on the secondary replicas.")) {
                # We need to setup a progress bar for every replica to display them all at once.
                $syncProgressId = @{ }
                foreach ($replicaName in $replicaServerSMO.Keys) {
                    $syncProgressId[$replicaName] = Get-Random
                }

                $stillWaiting = $true
                $timeout = (Get-Date).AddSeconds($timeoutSynchronization)
                while ($stillWaiting) {
                    $stillWaiting = $false
                    $failure = $false
                    foreach ($replicaName in $replicaServerSMO.Keys) {
                        if (-not $targetSynchronizationState[$replicaName]) {
                            Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the replica $replicaName."
                            continue
                        }

                        if (-not $replicaAgDbSMO[$replicaName].IsJoined -or $replicaAgDbSMO[$replicaName].SynchronizationState -ne $targetSynchronizationState[$replicaName]) {
                            $stillWaiting = $true
                        }

                        $syncProgress = @{ }
                        $syncProgress['Id'] = $syncProgressId[$replicaName]
                        $syncProgress['ParentId'] = $progress['Id']
                        $syncProgress['Activity'] = "Adding database(s) to Availability Group $AvailabilityGroup."
                        if ($replicaAgDbSMO[$replicaName].SynchronizationState -ne $targetSynchronizationState[$replicaName]) {
                            $syncProgress['Status'] = "IsJoined is $($replicaAgDbSMO[$replicaName].IsJoined), SynchronizationState is $($replicaAgDbSMO[$replicaName].SynchronizationState), waiting for $($targetSynchronizationState[$replicaName])."
                        } else {
                            $syncProgress['Status'] = "IsJoined is $($replicaAgDbSMO[$replicaName].IsJoined), SynchronizationState is $($replicaAgDbSMO[$replicaName].SynchronizationState), replica is in desired state."
                        }
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic' -and $reportSeeding) {
                            $seedingStats = $server.Query("SELECT TOP 1 * FROM sys.dm_hadr_physical_seeding_stats WHERE local_database_name = '$($db.Name)' AND remote_machine_name = '$($ag.AvailabilityReplicas[$replicaName].EndpointUrl)' ORDER BY start_time_utc DESC")
                            if ($seedingStats) {
                                if ($seedingStats.failure_message -ne [DBNull]::Value) {
                                    $failure = $true
                                    Stop-Function -Message "Failed while seeding database $($db.Name) to $replicaName. failure_message: $($seedingStats.failure_message)." -Continue
                                }

                                $syncProgress['PercentComplete'] = [int]($seedingStats.transferred_size_bytes * 100.0 / $seedingStats.database_size_bytes)
                                $syncProgress['SecondsRemaining'] = [int](($seedingStats.estimate_time_complete_utc - (Get-Date).ToUniversalTime()).TotalSeconds)
                                $syncProgress['CurrentOperation'] = "Seeding state: $($seedingStats.internal_state_desc), $([int]($seedingStats.transferred_size_bytes/1024/1024)) out of $([int]($seedingStats.database_size_bytes/1024/1024)) MB transferred."
                            }
                        }
                        Write-Message -Level Verbose -Message ($syncProgress['Status'] + $syncProgress['CurrentOperation'])
                        Write-Progress @syncProgress
                    }
                    if ($failure) {
                        $stillWaiting = $false
                        Stop-Function -Message "Failed while seeding database $($db.Name)." -Continue
                    }

                    if ((Get-Date) -gt $timeout) {
                        $stillWaiting = $false
                        $failure = $true
                        Stop-Function -Message "Failed to join or synchronize database $($db.Name). Timeout of $timeoutSynchronization seconds is reached. $progressOperation" -Continue
                    }
                    Start-Sleep -Milliseconds $waitWhile

                    foreach ($replicaName in $replicaServerSMO.Keys) {
                        $replicaAgDbSMO[$replicaName].Refresh()
                    }
                }
                if ($failure) {
                    Stop-Function -Message "Failed to join or synchronize database $($db.Name)." -Continue
                }
            }
            $output
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUf0QIjz6Xna5DwDEPbmz8YY9j
# UXWgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFAS+FbJdG4sC8SBfUi7Km69PEni0MA0G
# CSqGSIb3DQEBAQUABIIBAE544eoM/rqcnFbTFKEkANQ5XaQ7Irl3Lvu0hTHGUtu9
# jcf6Er3zwt+oF+D2NoTiR3Ao8NyM38PAzh699SqUAhgh/l72wY8O3eVywpBhRnAc
# KHh8dt3ULcPf4aVnrhRfncn8sDPCKWHHOsItuocvp2gsWpAieVenBdehiFWxL+YJ
# 4N2Rb1BwD+lteqwOPGXo33byLWeBYT31O+g8xGkAsVhSr7gody2gnsbDfar7c9HU
# beXHmK0mWsFN1SDaNybIIwr3K67DWBlJCSgv3OHdkLDJF3tmEyZBqIbG5J/hLodV
# W2hEtkeMNJ9jItv1vP73N1221sLfJ70simHTMqPnjr6hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzA3WjAvBgkqhkiG9w0BCQQxIgQgeo00RFEnC5hKaIe9AhNq
# bef1UxnTugQEiEUmtJWd7gYwDQYJKoZIhvcNAQEBBQAEggIAIpyV8fV17WSz5hNH
# GfRGjSKWLJgs0xC9vv3rtflhdhD9w/m6vOUunHuHIo0Z8Ft/x8N1F3RwZGXqmxC0
# 5w0+zsu+0SfG/pdLyeAKPQYS2pKGTTWHHGAkUm4+Loe0nF+wuphuaHIg5lc0XHJd
# /i6jJmdxqOW5CXnygbdYSbhpzg+6hl70Jpbr5GgnafLEcTPyKTj4MxSRQ4h0FzkX
# zBOErS2hfyGseubHhSRCXndZUEmx85GKFtWWhmkAJR110+I1AjZ6hDrNofzywecl
# XajFeGHmqYYXT1PFLaTd4MtcO4d/OsHgabHirwQYc4Zp5ifG79OeAz+lC9n4rORi
# qAE+17vFf8VuDUvMF3aT4gGTbi+VEgzANG9MlIcC69tKgCJiFQvnNCIdF+1YO6rO
# tAt3FqxfNwc2A24mhNaITVc8OWw+a4us8o6rhjB+w8cuVvHGon9rJ/Z9mlNzZ2z5
# /NuTjAeIF85wqlFPicwv6h8eonWnsqIsIAye7ABsgUrEVQJHH+wBD4uPiKFE+LTQ
# AUsKE7cq8ZIMGZdir1CaysTTFZuyDO8kWrAbTrz7sbfAnsq8TbWKC/HdR7cs2SjA
# 17IiSRaWH2t7/SWLQwaARB/GcDlTAg6vG19yza+VY+RPgdd1X6E+k0OyDQEVKYdN
# 7fpffUN7dtJOxtIFBmQgti3ZLtU=
# SIG # End signature block
