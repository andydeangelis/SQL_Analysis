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
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAvltJG6RciKABc
# AtSOQRivDoOxfstkM0+ajI6mRcBJfKCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDKUPgoek4w+4Syrz50ggL+3g6hsWVsFOML
# sxwjKxj+SzANBgkqhkiG9w0BAQEFAASCAQBiKXzeTW7PlH6Ad8T/k0AJcYw8ocqd
# eZp4va9GCPqZzjfRZVdnWjOXolwQ3QdXP25uQercB3EalSTWk0/UtjSEuCCHUY53
# p9Ht1ZGXjZAEpQ/2j1dQDhzjjggv4Q3Qcx7dvdhr86/DAMKjVSGCHxjsKHjlLN2I
# dl9Wn5/0QNdQ8OVwFB2L55JLK0T5TE32qnNnxSC246T9fflLQQFF+e9jeeV+CY2z
# GTkgB37UhO0fLsTLRn+SF6MMeg5D2cpuBF0ZuGZ7L4+xskNRrqUso6qtGwLpoqi1
# d56BU3jMOWR5KwP8C4x0oP9QBxqqyXBltU/OlCyBJ5X8QyozV+XZrxrBoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI0MlowLwYJKoZIhvcNAQkEMSIEIHcQ/tsc
# JClZ+RY2m+iTYF45ERNjaB1lq+h4699zjDN6MA0GCSqGSIb3DQEBAQUABIICAJax
# Fg5EmcvrCVTTFrnNXZ/DjI2VKKZKcXt68L5I6L2KlYF43BYcgmVdXhlPSIO7Adsv
# Rr1aTbvpHorbh1j7aUVQcMX0gb3MmpnhT8yXA/uI1nwwg6Qt2MV9Y91efdRMZxFq
# c8aRgpo39NoA+CkHGcon4lQTazR0kYds2LYJFoQxGm1RM/ILM68Z/KnwtoGBBDIB
# jJWoiZk0SrJnW1enYflWuTiaHpbDj2jv6EWQsP7COSdo+pJFyGqMW8Q/7OiDYmnn
# cxP2QTvwBJcAj+MioEaGjk3XXvitgBtPQLuN5H1jJAuM6+HQGPt7URCFV0C9laBx
# U99bgdB5NNWfC6LNAQbzn3ViUS23ozhGL29QgR8fAsq6S4Q7fUr/xLfMd9nR9ui9
# 9snuHvYig9hmOcF6dL3HDIFWijCHIKmoK/e5PDPQE4BI65iBLkV06bl6NkjyqdLd
# 9nQhrqDwkReD0ZczYM0Bcu/nEZNGUJAI7gK6d+s1p6Ii8H9hTe5jixu30g+6eJot
# 6VdktmP2+hvU2qdorJW9tn2Lzer9rR3+p2FYvn5PDIWtg/nx2cu07yDNLqojLE+g
# WHg94sw5wpWwEICbtbCEDaC3ptrUnaxAymsCo6ObC+CgUn4r7dMzAmsMJXPHkfYo
# IFp4KNuihnTUZNat+YfKlVkPsXBWzzF9kwJ+PsjF
# SIG # End signature block
