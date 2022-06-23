function Expand-DbaDbLogFile {
    <#
    .SYNOPSIS
        This command will help you to automatically grow your transaction log file in a responsible way (preventing the generation of too many VLFs).

    .DESCRIPTION
        As you may already know, having a transaction log file with too many Virtual Log Files (VLFs) can hurt your database performance in many ways.

        Example:
        Too many VLFs can cause transaction log backups to slow down and can also slow down database recovery and, in extreme cases, even impact insert/update/delete performance.

        References:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/

        In order to get rid of this fragmentation we need to grow the file taking the following into consideration:
        - How many VLFs are created when we perform a grow operation or when an auto-grow is invoked?

        Note: In SQL Server 2014 this algorithm has changed (http://www.sqlskills.com/blogs/paul/important-change-vlf-creation-algorithm-sql-server-2014/)

        Attention:
        We are growing in MB instead of GB because of known issue prior to SQL 2012:
        More detail here:
        http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
        and
        http://connect.microsoft.com/SqlInstance/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
        or
        https://connect.microsoft.com/SqlInstance/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

        Understanding related problems:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/

        Known bug before SQL Server 2012
        http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
        http://connect.microsoft.com/SqlInstance/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
        https://connect.microsoft.com/SqlInstance/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

        How it works?
        The transaction log will grow in chunks until it reaches the desired size.
        Example: If you have a log file with 8192MB and you say that the target size is 81920MB (80GB) it will grow in chunks of 8192MB until it reaches 81920MB. 8192 -> 16384 -> 24576 ... 73728 -> 81920

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER TargetLogSize
        Specifies the target size of the transaction log file in megabytes.

    .PARAMETER IncrementSize
        Specifies the amount the transaction log should grow in megabytes. If this value differs from the suggested value based on your TargetLogSize, you will be prompted to confirm your choice.

        This value will be calculated if not specified.

    .PARAMETER LogFileId
        Specifies the file number(s) of additional transaction log files to grow.

        If this value is not specified, only the first transaction log file will be processed.

    .PARAMETER ShrinkLogFile
        If this switch is enabled, your transaction log files will be shrunk.

    .PARAMETER ShrinkSize
        Specifies the target size of the transaction log file for the shrink operation in megabytes.

    .PARAMETER BackupDirectory
        Specifies the location of your backups. Backups must be performed to shrink the transaction log.

        If this value is not specified, the SQL Server instance's default backup directory will be used.

    .PARAMETER ExcludeDiskSpaceValidation
        If this switch is enabled, the validation for enough disk space using Get-DbaDiskSpace command will be skipped.
        This can be useful when you know that you have enough space to grow your TLog but you don't have PowerShell Remoting enabled to validate it.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, LogFile
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: ALTER DATABASE permission
        Limitations: Freespace cannot be validated on the directory where the log file resides in SQL Server 2005.
        This script uses Get-DbaDiskSpace dbatools command to get the TLog's drive free space

    .LINK
        https://dbatools.io/Expand-DbaDbLogFile

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1 -TargetLogSize 50000

        Grows the transaction log for database db1 on sqlcluster to 50000 MB and calculates the increment size.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1, db2 -TargetLogSize 10000 -IncrementSize 200

        Grows the transaction logs for databases db1 and db2 on sqlcluster to 1000MB and sets the growth increment to 200MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1 -TargetLogSize 10000 -LogFileId 9

        Grows the transaction log file  with FileId 9 of the db1 database on sqlcluster instance to 10000MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database (Get-Content D:\DBs.txt) -TargetLogSize 50000

        Grows the transaction log of the databases specified in the file 'D:\DBs.txt' on sqlcluster instance to 50000MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance SqlInstance -Database db1,db2 -TargetLogSize 100 -IncrementSize 10 -ShrinkLogFile -ShrinkSize 10 -BackupDirectory R:\MSSQL\Backup

        Grows the transaction logs for databases db1 and db2 on SQL server SQLInstance to 100MB, sets the incremental growth to 10MB, shrinks the transaction log to 10MB and uses the directory R:\MSSQL\Backup for the required backups.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
    param (
        [parameter(Position = 1, Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(Position = 3)]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [parameter(Position = 4)]
        [object[]]$ExcludeDatabase,
        [parameter(Position = 5, Mandatory)]
        [int]$TargetLogSize,
        [parameter(Position = 6)]
        [int]$IncrementSize = -1,
        [parameter(Position = 7)]
        [int]$LogFileId = -1,
        [parameter(Position = 8, ParameterSetName = 'Shrink', Mandatory)]
        [switch]$ShrinkLogFile,
        [parameter(Position = 9, ParameterSetName = 'Shrink', Mandatory)]
        [int]$ShrinkSize,
        [parameter(Position = 10, ParameterSetName = 'Shrink')]
        [AllowEmptyString()]
        [string]$BackupDirectory,
        [switch]$ExcludeDiskSpaceValidation,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level Verbose -Message "Set ErrorActionPreference to Inquire."
        $ErrorActionPreference = 'Inquire'

        #Convert MB to KB (SMO works in KB)
        Write-Message -Level Verbose -Message "Convert variables MB to KB (SMO works in KB)."
        [int]$TargetLogSizeKB = $TargetLogSize * 1024
        [int]$LogIncrementSize = $IncrementSize * 1024
        [int]$ShrinkSizeKB = $ShrinkSize * 1024
        [int]$SuggestLogIncrementSize = 0
        [bool]$LogByFileID = if ($LogFileId -eq -1) {
            $false
        } else {
            $true
        }

        #Set base information
        Write-Message -Level Verbose -Message "Initialize the instance '$SqlInstance'."

        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
        }

        if ($ShrinkLogFile -eq $true) {
            if ($BackupDirectory.length -eq 0) {
                $backupdirectory = $server.Settings.BackupDirectory
            }

            $pathexists = Test-DbaPath -SqlInstance $server -Path $backupdirectory

            if ($pathexists -eq $false) {
                Stop-Function -Message "Backup directory does not exist."
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        try {

            [datetime]$initialTime = Get-Date

            #control the iteration number
            $databaseProgressbar = 0;

            Write-Message -Level Verbose -Message "Resolving FullComputerName name."
            # We don't have windows credentials here, so Resolve-DbaNetworkName has to respect that and work like Resolve-NetBiosName did before.
            $resolvedComputerName = Resolve-DbaComputerName -ComputerName $SqlInstance

            $databases = $server.Databases | Where-Object IsAccessible
            Write-Message -Level Verbose -Message "Number of databases found: $($databases.Count)."
            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            #go through all databases
            Write-Message -Level Verbose -Message "Processing...foreach database..."
            foreach ($db in $databases.Name) {
                Write-Message -Level Verbose -Message "Working on $db."
                $databaseProgressbar += 1

                #set step to reutilize on logging operations
                [string]$step = "$databaseProgressbar/$($Databases.Count)"

                if ($server.Databases[$db]) {
                    Write-Progress `
                        -Id 1 `
                        -Activity "Using database: $db on Instance: '$SqlInstance'" `
                        -PercentComplete ($databaseProgressbar / $Databases.Count * 100) `
                        -Status "Processing - $databaseProgressbar of $($Databases.Count)"

                    #Validate which file will grow
                    if ($LogByFileID) {
                        $logfile = $server.Databases[$db].LogFiles.ItemById($LogFileId)
                    } else {
                        $logfile = $server.Databases[$db].LogFiles[0]
                    }

                    $numLogfiles = $server.Databases[$db].LogFiles.Count

                    Write-Message -Level Verbose -Message "$step - Use log file: $logfile."
                    $currentSize = $logfile.Size
                    $currentSizeMB = $currentSize / 1024

                    #Get the number of VLFs
                    $initialVLFCount = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $db

                    Write-Message -Level Verbose -Message "$step - Log file current size: $([System.Math]::Round($($currentSize/1024.0), 2)) MB "
                    [long]$requiredSpace = ($TargetLogSizeKB - $currentSize)

                    if ($ExcludeDiskSpaceValidation -eq $false) {
                        Write-Message -Level Verbose -Message "Verifying if sufficient space exists ($([System.Math]::Round($($requiredSpace / 1024.0), 2))MB) on the volume to perform this task."

                        [long]$TotalTLogFreeDiskSpaceKB = 0
                        Write-Message -Level Verbose -Message "Get TLog drive free space"

                        try {
                            # That would need a Credential, but we don't have one...
                            [object]$AllDrivesFreeDiskSpace = Get-DbaDiskSpace -ComputerName $resolvedComputerName | Select-Object Name, SizeInKB

                            #Verify path using Split-Path on $logfile.FileName in backwards. This way we will catch the LUNs. Example: "K:\Log01" as LUN name. Need to add final backslash if not there
                            $DrivePath = Split-Path $logfile.FileName -parent
                            $DrivePath = if (!($DrivePath.EndsWith("\"))) { "$DrivePath\" }
                            else { $DrivePath }
                            Do {
                                if ($AllDrivesFreeDiskSpace | Where-Object { $DrivePath -eq "$($_.Name)" }) {
                                    $TotalTLogFreeDiskSpaceKB = ($AllDrivesFreeDiskSpace | Where-Object { $DrivePath -eq $_.Name }).SizeInKB
                                    $match = $true
                                    break
                                } else {
                                    $match = $false
                                    $DrivePath = Split-Path $DrivePath -parent
                                    $DrivePath = if (!($DrivePath.EndsWith("\"))) { "$DrivePath\" }
                                    else { $DrivePath }
                                }

                            }
                            while (!$match -or ([string]::IsNullOrEmpty($DrivePath)))

                            Write-Message -Level Verbose -Message "Total TLog Free Disk Space in MB: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))"

                        } catch {
                            #Could not validate the disk space. Will ask if we want to continue.
                            $TotalTLogFreeDiskSpaceKB = 0
                        }

                        if (($TotalTLogFreeDiskSpaceKB -le 0) -or ([string]::IsNullOrEmpty($TotalTLogFreeDiskSpaceKB))) {
                            $title = "Choose increment value for database '$db':"
                            $message = "Cannot validate freespace on drive where the log file resides. Do you wish to continue? (Y/N)"
                            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                            $result = $host.ui.PromptForChoice($title, $message, $options, 0)
                            #no
                            if ($result -eq 1) {
                                Write-Message -Level Warning -Message "You have cancelled the execution"
                                return
                            }
                        } elseif ($requiredSpace -gt $TotalTLogFreeDiskSpaceKB) {
                            Write-Message -Level Verbose -Message "There is not enough space on volume to perform this task. `r`n" `
                                "Available space: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))MB;`r`n" `
                                "Required space: $([System.Math]::Round($($requiredSpace / 1024.0), 2))MB;"
                            return
                        }
                    }

                    if ($currentSize -ige $TargetLogSizeKB -and ($ShrinkLogFile -eq $false)) {
                        Write-Message -Level Verbose -Message "$step - [INFO] The T-Log file '$logfile' size is already equal or greater than target size - No action required."
                    } else {
                        Write-Message -Level Verbose -Message "$step - [OK] There is sufficient free space to perform this task."

                        # If SQL Server version is greater or equal to 2012
                        if ($server.Version.Major -ge "11") {
                            switch ($TargetLogSize) {
                                { $_ -le 64 } { $SuggestLogIncrementSize = 64 }
                                { $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
                                { $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
                                { $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
                                { $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
                                { $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4096 }
                                { $_ -ge 16384 } { $SuggestLogIncrementSize = 8192 }
                            }
                        }
                        # 2008 R2 or under
                        else {
                            switch ($TargetLogSize) {
                                { $_ -le 64 } { $SuggestLogIncrementSize = 64 }
                                { $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
                                { $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
                                { $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
                                { $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
                                { $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4000 }
                                { $_ -ge 16384 } { $SuggestLogIncrementSize = 8000 }
                            }

                            if (($IncrementSize % 4096) -eq 0) {
                                Write-Message -Level Verbose -Message "Your instance version is below SQL 2012, remember the known BUG mentioned on HELP. `r`nUse Get-Help Expand-DbaTLogFileResponsibly to read help`r`nUse a different value for incremental size.`r`n"
                                return
                            }
                        }
                        Write-Message -Level Verbose -Message "Instance $server version: $($server.Version.Major) - Suggested TLog increment size: $($SuggestLogIncrementSize)MB"

                        # Shrink Log File to desired size before re-growth to desired size (You need to remove as many VLF's as possible to ensure proper growth)
                        $ShrinkSize = $ShrinkSizeKB / 1024
                        if ($ShrinkLogFile -eq $true) {
                            if ($server.Databases[$db].RecoveryModel -eq [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple) {
                                Write-Message -Level Warning -Message "Database '$db' is in Simple RecoveryModel which does not allow log backups. Do not specify -ShrinkLogFile and -ShrinkSize parameters."
                                Continue
                            }

                            try {
                                $sql = "SELECT last_log_backup_lsn FROM sys.database_recovery_status WHERE database_id = DB_ID('$db')"
                                $sqlResult = $server.ConnectionContext.ExecuteWithResults($sql);

                                if ($sqlResult.Tables[0].Rows[0]["last_log_backup_lsn"] -is [System.DBNull]) {
                                    Write-Message -Level Warning -Message "First, you need to make a full backup before you can do Tlog backup on database '$db' (last_log_backup_lsn is null)."
                                    Continue
                                }
                            } catch {
                                Stop-Function -Message "Can't execute SQL on $server. `r`n $($_)" -Continue
                            }

                            If ($Pscmdlet.ShouldProcess($($server.name), "Backing up TLog for $db")) {
                                Write-Message -Level Verbose -Message "We are about to backup the Tlog for database '$db' to '$backupdirectory' and shrink the log."
                                Write-Message -Level Verbose -Message "Starting Size = $currentSizeMB."

                                $DefaultCompression = $server.Configuration.DefaultBackupCompression.ConfigValue

                                if ($currentSizeMB -gt $ShrinkSize) {
                                    $backupRetries = 1
                                    Do {
                                        try {
                                            $percent = $null
                                            $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
                                            $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Log
                                            $backup.BackupSetDescription = "Transaction Log backup of " + $db
                                            $backup.BackupSetName = $db + " Backup"
                                            $backup.Database = $db
                                            $backup.MediaDescription = "Disk"
                                            $dt = Get-Date -format yyyyMMddHHmmssms
                                            $null = $backup.Devices.AddDevice($backupdirectory + "\" + $db + "_db_" + $dt + ".trn", 'File')
                                            if ($DefaultCompression -eq $true) {
                                                $backup.CompressionOption = 1
                                            } else {
                                                $backup.CompressionOption = 0
                                            }
                                            $null = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                                                Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                                            }
                                            $backup.add_PercentComplete($percent)
                                            $backup.PercentCompleteNotification = 10
                                            $backup.add_Complete($complete)
                                            Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -percentcomplete 0 -Status ([System.String]::Format("Progress: {0} %", 0))
                                            $backup.SqlBackup($server)
                                            Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -status "Complete" -Completed
                                            $logfile.Shrink($ShrinkSize, [Microsoft.SqlServer.Management.SMO.ShrinkMethod]::TruncateOnly)
                                            $logfile.Refresh()
                                        } catch {
                                            Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
                                            Stop-Function -Message "Backup failed for database" -ErrorRecord $_ -Target $db -Continue
                                            Continue
                                        }

                                    }
                                    while (($logfile.Size / 1024) -gt $ShrinkSize -and ++$backupRetries -lt 6)

                                    $currentSize = $logfile.Size
                                    Write-Message -Level Verbose -Message "TLog backup and truncate for database '$db' finished. Current TLog size after $backupRetries backups is $($currentSize/1024)MB"
                                }
                            }
                        }

                        # SMO uses values in KB
                        $SuggestLogIncrementSize = $SuggestLogIncrementSize * 1024

                        # If default, use $SuggestedLogIncrementSize
                        if ($IncrementSize -eq -1) {
                            $LogIncrementSize = $SuggestLogIncrementSize
                        } else {
                            if ($LogIncrementSize -lt $SuggestLogIncrementSize) {
                                Write-Message -Level Warning -Message "The input value for increment size is $([System.Math]::Round($LogIncrementSize / 1024, 0))MB, which is less than the suggested value of $($SuggestLogIncrementSize / 1024)MB."
                            }
                        }

                        #start growing file
                        If ($Pscmdlet.ShouldProcess($($server.name), "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$db'")) {
                            Write-Message -Level Verbose -Message "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$db'"

                            Write-Message -Level Verbose -Message "$step - While current size less than target log size."

                            while ($currentSize -lt $TargetLogSizeKB) {

                                Write-Progress `
                                    -Id 2 `
                                    -ParentId 1 `
                                    -Activity "Growing file $logfile on '$db' database" `
                                    -PercentComplete ($currentSize / $TargetLogSizeKB * 100) `
                                    -Status "Remaining - $([System.Math]::Round($($($TargetLogSizeKB - $currentSize) / 1024.0), 2)) MB"

                                Write-Message -Level Verbose -Message "$step - Verifying if the log can grow or if it's already at the desired size."
                                if (($TargetLogSizeKB - $currentSize) -lt $LogIncrementSize) {
                                    Write-Message -Level Verbose -Message "$step - Log size is lower than the increment size. Setting current size equals $TargetLogSizeKB."
                                    $currentSize = $TargetLogSizeKB
                                } else {
                                    Write-Message -Level Verbose -Message "$step - Grow the $logfile file in $([System.Math]::Round($($LogIncrementSize / 1024.0), 2)) MB"
                                    $currentSize += $LogIncrementSize
                                }

                                #When -WhatIf Switch, do not run
                                if ($PSCmdlet.ShouldProcess("$step - File will grow to $([System.Math]::Round($($currentSize/1024.0), 2)) MB", "This action will grow the file $logfile on database $db to $([System.Math]::Round($($currentSize/1024.0), 2)) MB .`r`nDo you wish to continue?", "Perform grow")) {
                                    Write-Message -Level Verbose -Message "$step - Set size $logfile to $([System.Math]::Round($($currentSize/1024.0), 2)) MB"
                                    $logfile.size = $currentSize

                                    Write-Message -Level Verbose -Message "$step - Applying changes"
                                    $logfile.Alter()
                                    Write-Message -Level Verbose -Message "$step - Changes have been applied"

                                    #Will put the info like VolumeFreeSpace up to date
                                    $logfile.Refresh()
                                }
                            }

                            Write-Message -Level Verbose -Message "`r`n$step - [OK] Growth process for logfile '$logfile' on database '$db', has been finished."

                            Write-Message -Level Verbose -Message "$step - Grow $logfile log file on $db database finished."
                        }
                    }
                }
                #else verifying existence
                else {
                    Write-Message -Level Verbose -Message "Database '$db' does not exist on instance '$SqlInstance'."
                }

                #Get the number of VLFs
                $currentVLFCount = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $db

                [pscustomobject]@{
                    ComputerName    = $server.ComputerName
                    InstanceName    = $server.ServiceName
                    SqlInstance     = $server.DomainInstanceName
                    Database        = $db
                    ID              = $logfile.ID
                    Name            = $logfile.Name
                    LogFileCount    = $numLogfiles
                    InitialSize     = [dbasize]($currentSizeMB * 1024 * 1024)
                    CurrentSize     = [dbasize]($TargetLogSize * 1024 * 1024)
                    InitialVLFCount = $initialVLFCount.Total
                    CurrentVLFCount = $currentVLFCount.Total
                } | Select-DefaultView -ExcludeProperty LogFileCount
            } #foreach database
        } catch {
            Stop-Function -Message "Logfile $logfile on database $db not processed. Error: $($_.Exception.Message). Line Number:  $($_InvocationInfo.ScriptLineNumber)" -Continue
        }
    }

    end {
        Write-Message -Level Verbose -Message "Process finished $((Get-Date) - ($initialTime))"
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU/TCudxUj8Q+J9FKbLrIM8b9p
# CUagghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFLNQlnNHgrmoxhQ5K9ZmCDkym8sfMA0G
# CSqGSIb3DQEBAQUABIIBAA0RhW16sGfABMdcDN21LyagFnYvkORgxp83vSCohgRQ
# ucdb1T0NlVOPU33QtY1cxYAfULAJW30D9oIXoKm3sEVWN0o98iDoryImtgfybC2h
# G2k5VZ7LYTu17dE7/l+aAd7JY+nFav/SCi17Jb2QtuPpoG4BUtAwvynQp09CuS9P
# gwXQwOygeRnYUih9PVrWPwNLkFy13dR0vIMapgtTJYHbeEWOrQfLa1lgdnkqUv6c
# 1qcVakvFOc50ZtVOtF02h0KMSr1Nkb2C2BlS/hNcU+pqWD/BM9gbea/MfixCsSl2
# LzwGPqcmQkP6o4IGXhX1r9L5KfIILo6IZ3Hzf1bsUzGhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzE3WjAvBgkqhkiG9w0BCQQxIgQgCSUiRXXD/nOO7sHl8wSm
# PcH85Q5Qwz7pt2BecQHfwzEwDQYJKoZIhvcNAQEBBQAEggIAPf/Xu4TFRgkQTZJm
# aUGQRGV1I6DsXQ0ARttCszlcU3gGM6AA5qwRFsHfes4k+NDyN9nL9mrOs/ZGdhCF
# VvprWI3wrVQCpLAVdZ0QOqpZ+xytV3Kq5HmI8wb1qrp+oOdxjcxiYLCAASWlFmsf
# B0RYPlaE+Sxg9+efejVkABDTtaxMelmkLDVF87pkRZlgoKUZhZBk0KI2yiTQMGcc
# lCrKiB9SZKqJdZ8gXMKnOFjChy10nv/26kqdypa3pRa+6w/+8pJ8SJhxUVSPV+ob
# KG5PzrbGOBHKa8k/ni720afyaCcqniPqHoLR8hDF2nPnseAF5pZn2YaagCZ6LySG
# rY2acDISfrfLhM9YIlqXd8Oc+uT3C9PbjMpW4SnP52yRNvNGNdtPo//m02SPTAoK
# NZIXVSelBIu8GV5s4IHhY9+gqeve861rF3sHV7b8M9ac+Emg5b0UZr/6Mqo4nibo
# UM2L/m5B2CFMvCUigWqZTSL7L9E7YODe5yUKxymdNVnWnZBAEx7xWJS/8QPtYxLW
# 7o4b0jbiASt/2zgAxLy7sw3DBmFhfMCRUcLQYU31ChuF4DL/eyO66Uj8l5qOaVWm
# MmTTX8DsZ6gf+lYmiWUZLCCL10wx6Q/gAn24F9lCeQJckvaPIpPow8T4WoQYPEgR
# NFezOojWSIiU+6XkmuO2PWv+aTE=
# SIG # End signature block
