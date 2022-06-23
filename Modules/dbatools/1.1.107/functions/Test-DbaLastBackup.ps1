function Test-DbaLastBackup {
    <#
    .SYNOPSIS
        Quickly and easily tests the last set of full backups for a server.

    .DESCRIPTION
        Restores all or some of the latest backups and performs a DBCC CHECKDB.

        1. Gathers information about the last full backups
        2. Restores the backups to the Destination with a new name. If no Destination is specified, the originating SQL Server instance wil be used.
        3. The database is restored as "dbatools-testrestore-$databaseName" by default, but you can change dbatools-testrestore to whatever you would like using -Prefix
        4. The internal file names are also renamed to prevent conflicts with original database
        5. A DBCC CHECKDB is then performed
        6. And the test database is finally dropped

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Unlike many of the other commands, you cannot specify more than one server.

    .PARAMETER Destination
        The destination server to use to test the restore. By default, the Destination will be set to the source server

        If a different Destination server is specified, you must ensure that the database backups are on a shared location

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database backups to test. If -Database is not provided, all database backups will be tested.

    .PARAMETER ExcludeDatabase
        Exclude specific Database backups to test.

    .PARAMETER DataDirectory
        Specifies an alternative directory for mdfs, ndfs and so on. The command uses the SQL Server's default data directory for all restores.

    .PARAMETER LogDirectory
        Specifies an alternative directory for ldfs. The command uses the SQL Server's default log directory for all restores.

    .PARAMETER FileStreamDirectory
        Specifies a directory for filestream data.

    .PARAMETER VerifyOnly
        If this switch is enabled, VERIFYONLY will be performed. An actual restore will not be executed.

    .PARAMETER NoCheck
        If this switch is enabled, DBCC CHECKDB will be skipped

    .PARAMETER NoDrop
        If this switch is enabled, the newly-created test database will not be dropped.

    .PARAMETER CopyFile
        If this switch is enabled, the backup file will be copied to the destination default backup location unless CopyPath is specified.

    .PARAMETER CopyPath
        Specifies a path relative to the SQL Server to copy backups when CopyFile is specified. If not specified will use destination default backup location. If destination SQL Server is not local, admin UNC paths will be utilized for the copy.

    .PARAMETER MaxSize
        Max size in MB. Databases larger than this value will not be restored.

    .PARAMETER MaxDop
        Allows you to pass in a MAXDOP setting to the DBCC CheckDB command to limit the number of parallel processes used.

    .PARAMETER DeviceType
        Specifies a filter for backup sets based on DeviceTypes. Valid options are 'Disk','Permanent Disk Device', 'Tape', 'Permanent Tape Device','Pipe','Permanent Pipe Device','Virtual Device', in addition to custom integers for your own DeviceTypes.

    .PARAMETER AzureCredential
        The name of the SQL Server credential on the destination instance that holds the key to the azure storage account.

    .PARAMETER IncludeCopyOnly
        If this switch is enabled, copy only backups will be counted as a last backup.

    .PARAMETER IgnoreLogBackup
        If this switch is enabled, transaction log backups will be ignored. The restore will stop at the latest full or differential backup point.

    .PARAMETER IgnoreDiffBackup
        If this switch is enabled, differential backuys will be ignored. The restore will only use Full and Log backups, so will take longer to complete

    .PARAMETER Prefix
        The database is restored as "dbatools-testrestore-$databaseName" by default. You can change dbatools-testrestore to whatever you would like using this parameter.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple of 64kb and a max of 4GB
        Parameter is used as passtrough for Restore-DbaDatabase.

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refererence: https://msdn.microsoft.com/en-us/library/ms178615.aspx#data-transfer-options
        Parameter is used as passtrough for Restore-DbaDatabase.

    .PARAMETER ReuseSourceFolderStructure
        By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure.
        The same structure on the SOURCE will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default Sql structure (MSSql12.INSTANCE, etc)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.


    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaLastBackup

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016

        Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure), then performs a DBCC CHECKDB. Once the test is complete, the test restore will be dropped.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -Database SharePoint_Config

        Determines the last full backup for SharePoint_Config, attempts to restore it, then performs a DBCC CHECKDB.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016, sql2017 | Test-DbaLastBackup

        Tests every database backup on sql2016 and sql2017

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016, sql2017 -Database SharePoint_Config | Test-DbaLastBackup

        Tests the database backup for the SharePoint_Config database on sql2016 and sql2017

    .EXAMPLE
       PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -Database model, master -VerifyOnly

       Skips performing an action restore of the database and simply verifies the backup using VERIFYONLY option of the restore.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -NoCheck -NoDrop

        Skips the DBCC CHECKDB check. This can help speed up the tests but makes it less tested. The test restores will remain on the server.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -DataDirectory E:\bigdrive -LogDirectory L:\bigdrive -MaxSize 10240

        Restores data and log files to alternative locations and only restores databases that are smaller than 10 GB.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile

        Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile -CopyPath "\\BackupShare\TestRestore\"

        Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -NoCheck -MaxTransferSize 4194302 -BufferCount 24

        Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure).
        The Restore will use more memory for reading the backup files. Do not set these values to high or you can get an Out of Memory error!!!
        When running the restore with these additional parameters and there is other server activity it could affect server OLTP performance. Please use with causion.
        Prior to running, you should check memory and server resources before configure it to run automatically.
        More information:
        https://www.mssqltips.com/sqlservertip/4935/optimize-sql-server-database-restore-performance/

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -MaxDop 4

        The use of the MaxDop parameter will limit the number of processors used during the DBCC command
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameters DestinationSqlCredential and AzureCredential")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [DbaInstanceParameter]$Destination,
        [object]$DestinationSqlCredential,
        [string]$DataDirectory,
        [string]$LogDirectory,
        [string]$FileStreamDirectory,
        [string]$Prefix = "dbatools-testrestore-",
        [switch]$VerifyOnly,
        [switch]$NoCheck,
        [switch]$NoDrop,
        [switch]$CopyFile,
        [string]$CopyPath,
        [int]$MaxSize,
        [string[]]$DeviceType,
        [switch]$IncludeCopyOnly,
        [switch]$IgnoreLogBackup,
        [string]$AzureCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [int]$MaxTransferSize,
        [int]$BufferCount,
        [switch]$IgnoreDiffBackup,
        [int]$MaxDop,
        [switch]$ReuseSourceFolderStructure,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if ($db.Name -eq "tempdb") {
                continue
            }

            $sourceserver = $db.Parent
            $source = $db.Parent.Name
            $instance = [DbaInstanceParameter]$source
            $copysuccess = $true
            $dbName = $db.Name
            $restoreresult = $null

            if (-not (Test-Bound -ParameterName Destination)) {
                $destination = $sourceserver.Name
                $DestinationSqlCredential = $SqlCredential
            }

            if ($db.LastFullBackup.Year -eq 1) {
                [pscustomobject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $db.name
                    FileExists     = $false
                    Size           = $null
                    RestoreResult  = "Skipped"
                    DbccResult     = "Skipped"
                    RestoreStart   = $null
                    RestoreEnd     = $null
                    RestoreElapsed = $null
                    DbccMaxDop     = $null
                    DbccStart      = $null
                    DbccEnd        = $null
                    DbccElapsed    = $null
                    BackupDates    = $null
                    BackupFiles    = $null
                }
                continue
            }

            try {
                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -Continue
            }

            if ($destserver.VersionMajor -lt $sourceserver.VersionMajor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
            }

            if ($destserver.VersionMajor -eq $sourceserver.VersionMajor -and $destserver.VersionMinor -lt $sourceserver.VersionMinor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
            }

            if ($CopyPath) {
                $testpath = Test-DbaPath -SqlInstance $destserver -Path $CopyPath
                if (-not $testpath) {
                    Stop-Function -Message "$destserver cannot access $CopyPath." -Continue
                }
            } else {
                # If not CopyPath is specified, use the destination server default backup directory
                $copyPath = $destserver.BackupDirectory
            }

            if ($instance -ne $destination -and -not $CopyFile) {
                $sourcerealname = $sourceserver.ComputerNetBiosName
                $destrealname = $destserver.ComputerNetBiosName

                if ($BackupFolder) {
                    if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcerealname -ne $destrealname) {
                        Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -Continue
                    }
                }
            }

            if ($datadirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $datadirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "Can't access $datadirectory Please check if $serviceAccount has permissions." -Continue
                }
            } else {
                $datadirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType mdf
            }

            if ($logdirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $logdirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "$Destination can't access its local directory $logdirectory. Please check if $serviceAccount has permissions." -Continue
                }
            } else {
                $logdirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType ldf
            }

            if ((Test-Bound -ParameterName AzureCredential) -and (Test-Bound -ParameterName CopyFile)) {
                Stop-Function -Message "Cannot use copyfile with Azure backups, set to false." -continue
                $CopyFile = $false
            }

            Write-Message -Level Verbose -Message "Getting recent backup history for $($db.Name) on $instance."

            if (Test-Bound "IgnoreLogBackup") {
                Write-Message -Level Verbose -Message "Skipping Log backups as requested."
                $lastbackup = @()
                $lastbackup += $full = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastFull -DeviceType $DeviceType -WarningAction SilentlyContinue
                if (-not (Test-Bound "IgnoreDiffBackup")) {
                    $diff = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastDiff -DeviceType $DeviceType -WarningAction SilentlyContinue
                }
                if ($full.start -le $diff.start) {
                    $lastbackup += $diff
                }
            } else {
                $lastbackup = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -Last -DeviceType $DeviceType -WarningAction SilentlyContinue -IgnoreDiffBackup:$IgnoreDiffBackup
            }

            if (-not $lastbackup) {
                Write-Message -Level Verbose -Message "No backups exist for this database."
                # This code should never be executed as there is already a test for databases without backup in line 241.
                continue
            }

            $totalSizeMB = ($lastbackup.TotalSize.Megabyte | Measure-Object -Sum).Sum
            if ($MaxSize -and $MaxSize -lt $totalSizeMB) {
                [pscustomobject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $db.name
                    FileExists     = $null
                    Size           = [dbasize](($lastbackup.TotalSize | Measure-Object -Sum).Sum)
                    RestoreResult  = "The backup size for $dbName ($totalSizeMB MB) exceeds the specified maximum size ($MaxSize MB)."
                    DbccResult     = "Skipped"
                    RestoreStart   = $null
                    RestoreEnd     = $null
                    RestoreElapsed = $null
                    DbccMaxDop     = $null
                    DbccStart      = $null
                    DbccEnd        = $null
                    DbccElapsed    = $null
                    BackupDates    = [String[]]($lastbackup.Start)
                    BackupFiles    = $lastbackup.FullName
                }
                continue
            }

            if ($CopyFile) {
                try {
                    Write-Message -Level Verbose -Message "Gathering information for file copy."
                    $removearray = @()

                    foreach ($backup in $lastbackup) {
                        foreach ($file in $backup) {
                            $filename = Split-Path -Path $file.FullName -Leaf
                            Write-Message -Level Verbose -Message "Processing $filename."

                            $sourcefile = Join-AdminUnc -servername $instance.ComputerName -filepath "$($file.Path)"

                            if ($instance.IsLocalHost) {
                                $remotedestdirectory = Join-AdminUnc -servername $instance.ComputerName -filepath $copyPath
                            } else {
                                $remotedestdirectory = $copyPath
                            }

                            $remotedestfile = "$remotedestdirectory\$filename"
                            $localdestfile = "$copyPath\$filename"
                            Write-Message -Level Verbose -Message "Destination directory is $destdirectory."
                            Write-Message -Level Verbose -Message "Destination filename is $remotedestfile."

                            try {
                                Write-Message -Level Verbose -Message "Copying $sourcefile to $remotedestfile."
                                Copy-Item -Path $sourcefile -Destination $remotedestfile -ErrorAction Stop
                                $backup.Path = $localdestfile
                                $backup.FullName = $localdestfile
                                $removearray += $remotedestfile
                            } catch {
                                $backup.Path = $sourcefile
                                $backup.FullName = $sourcefile
                            }
                        }
                    }
                    $copysuccess = $true
                } catch {
                    Write-Message -Level Warning -Message "Failed to copy backups for $dbName on $instance to $destdirectory - $_."
                    $copysuccess = $false
                }
            }
            if (-not $copysuccess) {
                Write-Message -Level Verbose -Message "Failed to copy backups."
                $lastbackup = @{
                    Path = "Failed to copy backups"
                }
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            } elseif (-not ($lastbackup | Where-Object { $_.type -eq 'Full' })) {
                Write-Message -Level Verbose -Message "No full backup returned from lastbackup."
                $lastbackup = @{
                    Path = "Not found"
                }
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            } elseif ($source -ne $destination -and $lastbackup[0].Path.StartsWith('\\') -eq $false -and -not $CopyFile) {
                Write-Message -Level Verbose -Message "Path not UNC and source does not match destination. Use -CopyFile to move the backup file."
                $fileexists = $dbccresult = "Skipped"
                $success = $restoreresult = "Restore not located on shared location"
            } elseif (($lastbackup[0].Path | ForEach-Object { Test-DbaPath -SqlInstance $destserver -Path $_ }) -eq $false) {
                Write-Message -Level Verbose -Message "SQL Server cannot find backup."
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            }
            if ($restoreresult -ne "Skipped" -or $lastbackup[0].Path -like 'http*') {
                Write-Message -Level Verbose -Message "Looking good."

                $fileexists = $true
                $ogdbname = $dbName
                $dbccElapsed = $restoreElapsed = $startRestore = $endRestore = $startDbcc = $endDbcc = $null
                $dbName = "$prefix$dbName"
                $destdb = $destserver.databases[$dbName]

                if ($destdb) {
                    Stop-Function -Message "$dbName already exists on $destination - skipping." -Continue
                }

                if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogdbname as $dbName.")) {
                    Write-Message -Level Verbose -Message "Performing restore."
                    $startRestore = Get-Date
                    try {
                        if ($ReuseSourceFolderStructure) {
                            $restoreSplat = @{
                                SqlInstance                = $destserver
                                RestoredDatabaseNamePrefix = $prefix
                                DestinationFilePrefix      = $Prefix
                                IgnoreLogBackup            = $IgnoreLogBackup
                                AzureCredential            = $AzureCredential
                                TrustDbBackupHistory       = $true
                                ReuseSourceFolderStructure = $true
                                EnableException            = $true
                            }
                        } else {
                            $restoreSplat = @{
                                SqlInstance                = $destserver
                                RestoredDatabaseNamePrefix = $prefix
                                DestinationFilePrefix      = $Prefix
                                DestinationDataDirectory   = $datadirectory
                                DestinationLogDirectory    = $logdirectory
                                IgnoreLogBackup            = $IgnoreLogBackup
                                AzureCredential            = $AzureCredential
                                TrustDbBackupHistory       = $true
                                EnableException            = $true
                            }
                        }

                        if (Test-Bound "MaxTransferSize") {
                            $restoreSplat.Add('MaxTransferSize', $MaxTransferSize)
                        }
                        if (Test-Bound "BufferCount") {
                            $restoreSplat.Add('BufferCount', $BufferCount)
                        }
                        if (Test-Bound "FileStreamDirectory") {
                            $restoreSplat.Add('DestinationFileStreamDirectory', $FileStreamDirectory)
                        }

                        if ($verifyonly) {
                            $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat -VerifyOnly:$VerifyOnly
                        } else {
                            $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat
                            Write-Message -Level Verbose -Message " Restore-DbaDatabase -SqlInstance $destserver -RestoredDatabaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $datadirectory -DestinationLogDirectory $logdirectory -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -TrustDbBackupHistory"
                        }
                    } catch {
                        $errormsg = Get-ErrorMessage -Record $_
                    }

                    $endRestore = Get-Date
                    $restorets = New-TimeSpan -Start $startRestore -End $endRestore
                    $ts = [timespan]::fromseconds($restorets.TotalSeconds)
                    $restoreElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                    if ($restoreresult.RestoreComplete -eq $true) {
                        $success = "Success"
                    } else {
                        if ($errormsg) {
                            $success = $errormsg
                        } else {
                            $success = "Failure"
                        }
                    }
                }

                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

                if (-not $NoCheck -and -not $VerifyOnly) {
                    # shouldprocess is taken care of in Start-DbccCheck
                    if ($ogdbname -eq "master") {
                        $dbccresult =
                        "DBCC CHECKDB skipped for restored master ($dbName) database. `
                            The master database cannot be copied off of a server and have a successful DBCC CHECKDB. `
                            See https://www.itprotoday.com/my-master-database-really-corrupt for more information."
                    } else {
                        if ($success -eq "Success") {
                            Write-Message -Level Verbose -Message "Starting DBCC."

                            $startDbcc = Get-Date
                            $dbccresult = Start-DbccCheck -Server $destserver -DbName $dbName -MaxDop $MaxDop 3>$null
                            $endDbcc = Get-Date

                            $dbccts = New-TimeSpan -Start $startDbcc -End $endDbcc
                            $ts = [timespan]::fromseconds($dbccts.TotalSeconds)
                            $dbccElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)
                        } else {
                            $dbccresult = "Skipped"
                        }
                    }
                }

                if ($VerifyOnly) {
                    $dbccresult = "Skipped"
                }

                if (-not $NoDrop -and $null -ne $destserver.databases[$dbName]) {
                    if ($Pscmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
                        Write-Message -Level Verbose -Message "Dropping database."

                        ## Drop the database
                        try {
                            #Variable $removeresult marked as unused by PSScriptAnalyzer replace with $null to catch output
                            $null = Remove-DbaDatabase -SqlInstance $destserver -Database $dbName -Confirm:$false
                            Write-Message -Level Verbose -Message "Dropped $dbName Database on $destination."
                        } catch {
                            $destserver.Databases.Refresh()
                            if ($destserver.databases[$dbName]) {
                                Write-Message -Level Warning -Message "Failed to Drop database $dbName on $destination."
                            }
                        }
                    }
                }

                #Cleanup BackupFiles if -CopyFile and backup was moved to destination

                $destserver.Databases.Refresh()
                if ($destserver.Databases[$dbName] -and -not $NoDrop) {
                    Write-Message -Level Warning -Message "$dbName was not dropped."
                }

                if ($CopyFile) {
                    Write-Message -Level Verbose -Message "Removing copied backup file from $destination."
                    try {
                        $removearray | Remove-Item -ErrorAction Stop
                    } catch {
                        Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess("console", "Showing results")) {
                [pscustomobject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $db.name
                    FileExists     = $fileexists
                    Size           = [dbasize](($lastbackup.TotalSize | Measure-Object -Sum).Sum)
                    RestoreResult  = $success
                    DbccResult     = $dbccresult
                    RestoreStart   = [dbadatetime]$startRestore
                    RestoreEnd     = [dbadatetime]$endRestore
                    RestoreElapsed = $restoreElapsed
                    DbccMaxDop     = [int]$MaxDop
                    DbccStart      = [dbadatetime]$startDbcc
                    DbccEnd        = [dbadatetime]$endDbcc
                    DbccElapsed    = $dbccElapsed
                    BackupDates    = [String[]]($lastbackup.Start)
                    BackupFiles    = $lastbackup.FullName
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD8WHJmpV73Q883
# iONhHEhesPOqfAJY747tMdYyL8xZLqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAgXSnMIQOe+NTiXM+IOPXupY8L1MNIpmNX
# 8gCpM7rlXzANBgkqhkiG9w0BAQEFAASCAQBAqsDyz8FuE6HXYgcprC2R0JPch4ye
# mcyUG9NI0qraJ11TwTN+kXPV4W6oHexxP3ECBkOeUv0NuDioZ9HqGGHbhkv3D4Ty
# YxyxFCrG9ZlEjF5FekD/XtWzc8WUm0LrmYe3+wFVlNgB1zDHa28ZP46J6TlXPbeq
# OZCiti9O+rc/c6ycLMzyN2YSQqmkladq5OMkl29ji9eBQTFhUZp+H++uZhHnF2Pq
# 4MIubYWFI6TlZ0axHYyac8B+ZOPjTq9G4aqXizqOP+gt5mQKKkrfUn6SbYrvrEoQ
# CV2mfjQcXz7bBGhA+eBztR83PD/SuoLdpLIEJKz2lisnOWPpX1XWc8dToYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQwOFowLwYJKoZIhvcNAQkEMSIEIDyu3sxT
# MyOmq1MVoOqeLle+o9KpXXmLIlLmB7w66jbgMA0GCSqGSIb3DQEBAQUABIICAHFe
# agbx08B78ympKLFSG2TuwY8rGfDM5V8WHahj4w8/vCrzc+vUd4Uetaept/LOUJ+B
# +lyZQkBuYhWuaRSMov0uhUG5X7U2qKhriet3iyPCVZjkEI1VByCU0HXdlHuN4Oi8
# INR/aWnAUnyH3VpppMJsa4XrKlaYUaHe4l3u9LSoII5vBtKfh/cQGLQg5mnPgGRA
# PzRrIL6NkiAKyHZJ6TTqZO7qRDP5dfd5YLOQoMmwmcNuYybPeghBQufaXfXKl6CG
# Kz/RA8SPhXt5pPV2VVM/WsXFyNz9FLQpLettg4j+EO9Yczdzybh4jL3SPgqSFHTb
# 9yEXK10l2B3TOXaOndpgPuJqD4aANRgHvkpoykoOiysj2A8FxA19YoFvQiGiGH3g
# nrk21NVO8VMmfJmsH2p3DnTncr77zd2Df8doRVBao6sGLbDKLic2cWhv6cQaoFYJ
# rf2pt9yXaTyFGeBOcLl3NwIwnSREgU+q6AgQ+WZ/Tvu2LPj3bFbgW+nS3wKIyUGI
# AauwfWu7lvDRiGS4NmBKUifa0nv5wNHMUAVIiDyCDWUajByefiP3iZvhqDSTCISG
# 28T3y57Jq3J3FYURNNTed8zKNuADpPIj2ujZRAW+/yYuMHXNfjtVKDed5kyYBvv+
# ypgAF2UtZ+z8BB7WXuOuVxLb01bP6ESwBPX+GGzV
# SIG # End signature block
