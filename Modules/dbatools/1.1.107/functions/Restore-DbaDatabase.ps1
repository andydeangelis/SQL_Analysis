function Restore-DbaDatabase {
    <#
    .SYNOPSIS
        Restores a SQL Server Database from a set of backup files.

    .DESCRIPTION
        Upon being passed a list of potential backups files this command will scan the files, select those that contain SQL Server
        backup sets. It will then filter those files down to a set that can perform the requested restore, checking that we have a
        full restore chain to the point in time requested by the caller.

        The function defaults to working on a remote instance. This means that all paths passed in must be relative to the remote instance.
        XpDirTree will be used to perform the file scans.

        Various means can be used to pass in a list of files to be considered. The default is to recursively scan the folder
        passed in.

    .PARAMETER SqlInstance
        The target SQL Server instance.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Path to SQL Server backup files.

        Paths passed in as strings will be scanned using the desired method, default is a recursive folder scan.
        Accepts multiple paths separated by ','.

        Or it can consist of FileInfo objects, such as the output of Get-ChildItem or Get-Item. This allows you to work with
        your own file structures as needed.

    .PARAMETER DatabaseName
        Name to restore the database under.
        Only works with a single database restore. If multiple database are found in the provided paths then we will exit.

    .PARAMETER DestinationDataDirectory
        Path to restore the SQL Server backups to on the target instance.
        If only this parameter is specified, then all database files (data and log) will be restored to this location.

    .PARAMETER DestinationLogDirectory
        Path to restore the database log files to.
        This parameter can only be specified alongside DestinationDataDirectory.

    .PARAMETER DestinationFileStreamDirectory
        Path to restore FileStream data to.
        This parameter can only be specified alongside DestinationDataDirectory.

    .PARAMETER RestoreTime
        Specify a DateTime object to which you want the database restored to. Default is to the latest point available in the specified backups.

    .PARAMETER NoRecovery
        Indicates if the databases should be recovered after last restore. Default is to recover.

    .PARAMETER WithReplace
        Switch indicated is the restore is allowed to replace an existing database.

    .PARAMETER XpDirTree
        Switch that indicated file scanning should be performed by the SQL Server instance using xp_dirtree.
        This will scan recursively from the passed in path.
        You must have sysadmin role membership on the instance for this to work.

    .PARAMETER OutputScriptOnly
        Switch indicates that ONLY T-SQL scripts should be generated, no restore takes place.
        Due to the limitations of SMO, this switch cannot be combined with VeriyOnly, and a warning will be raised if it is.

    .PARAMETER VerifyOnly
        Switch indicate that restore should be verified.
        Due to the limitations of SMO, this switch cannot be combined with OutputScriptOnly, and a warning will be raised if it is.

    .PARAMETER MaintenanceSolutionBackup
        Switch to indicate the backup files are in a folder structure as created by Ola Hallengreen's maintenance scripts.
        This switch enables a faster check for suitable backups. Other options require all files to be read first to ensure we have an anchoring full backup.
        Because we can rely on specific locations for backups performed with OlaHallengren's backup solution, we can rely on file locations.

    .PARAMETER FileMapping
        A hashtable that can be used to move specific files to a location.
        `$FileMapping = @{'DataFile1'='c:\restoredfiles\Datafile1.mdf';'DataFile3'='d:\DataFile3.mdf'}`
        And files not specified in the mapping will be restored to their original location.
        This Parameter is exclusive with DestinationDataDirectory.

    .PARAMETER IgnoreLogBackup
        This switch tells the function to ignore transaction log backups. The process will restore to the latest full or differential backup point only.

    .PARAMETER IgnoreDiffBackup
        This switch tells the function to ignore differential backups. The process will restore to the latest full and onwards with transaction log backups only.

    .PARAMETER UseDestinationDefaultDirectories
        Switch that tells the restore to use the default Data and Log locations on the target server. If they don't exist, the function will try to create them.

    .PARAMETER ReuseSourceFolderStructure
        By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure.
        The same structure on the SOURCE will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default Sql structure (MSSql12.INSTANCE, etc).

        *Note, to reuse destination folder structure, specify -WithReplace

    .PARAMETER DestinationFilePrefix
        This value will be prefixed to ALL restored files (log and data). This is just a simple string prefix.
        If you want to perform more complex rename operations then please use the FileMapping parameter.
        This will apply to all file move options, except for FileMapping.

    .PARAMETER DestinationFileSuffix
        This value will be suffixed to ALL restored files (log and data). This is just a simple string suffix.
        If you want to perform more complex rename operations then please use the FileMapping parameter.
        This will apply to all file move options, except for FileMapping.

    .PARAMETER RestoredDatabaseNamePrefix
        A string which will be prefixed to the start of the restore Database's Name.
        Useful if restoring a copy to the same sql server for testing.

    .PARAMETER TrustDbBackupHistory
        This switch can be used when piping the output of Get-DbaDbBackupHistory or Backup-DbaDatabase into this command.
        It allows the user to say that they trust that the output from those commands is correct, and skips the file header read portion of the process.
        This means a faster process, but at the risk of not knowing till halfway through the restore that something is wrong with a file.

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple by 64kb.

    .PARAMETER Blocksize
        Specifies the block size to use. Must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb or 64kb.
        Can be specified in bytes.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail.

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail.

    .PARAMETER NoXpDirRecurse
        If specified, prevents the XpDirTree process from recursing (its default behaviour).

    .PARAMETER DirectoryRecurse
        If specified the specified directory will be recursed into (overriding the default behaviour).

    .PARAMETER Continue
        If specified we will to attempt to recover more transaction log backups onto database(s) in Recovering or Standby states.

    .PARAMETER ExecuteAs
        If value provided the restore will be executed under this login's context. The login must exist, and have the relevant permissions to perform the restore.

    .PARAMETER StandbyDirectory
        If a directory is specified the database(s) will be restored into a standby state, with the standby file placed into this directory (which must exist, and be writable by the target Sql Server instance).

    .PARAMETER AzureCredential
        The name of the SQL Server credential to be used if restoring from an Azure hosted backup using Storage Access Keys.
        If a backup path beginning http is passed in and this parameter is not specified then if a credential with a name matching the URL.

    .PARAMETER ReplaceDbNameInFile
        If specified any occurrence of the original database's name in a data or log file will be replaced with the name specified in the DatabaseName parameter.

    .PARAMETER Recover
        If set will perform recovery on the indicated database.

    .PARAMETER GetBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Get-DbaBackupInformation.

    .PARAMETER SelectBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Select-DbaBackupInformation.

    .PARAMETER FormatBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Format-DbaBackupInformation.

    .PARAMETER TestBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Test-DbaBackupInformation.

    .PARAMETER StopAfterGetBackupInformation
        Switch which will cause the function to exit after returning GetBackupInformation.

    .PARAMETER StopAfterSelectBackupInformation
        Switch which will cause the function to exit after returning SelectBackupInformation.

    .PARAMETER StopAfterFormatBackupInformation
        Switch which will cause the function to exit after returning FormatBackupInformation.

    .PARAMETER StopAfterTestBackupInformation
        Switch which will cause the function to exit after returning TestBackupInformation.

    .PARAMETER StatementTimeOut
        Timeout in minutes. Defaults to infinity (restores can take a while).

    .PARAMETER KeepCDC
        Indicates whether CDC information should be restored as part of the database.

    .PARAMETER KeepReplication
        Indicates whether replication configuration should be restored as part of the database restore operation.

    .PARAMETER PageRestore
        Passes in an object from Get-DbaSuspectPages containing suspect pages from a single database.
        Setting this Parameter will cause an Online Page restore if the target Instance is Enterprise Edition, or offline if not.
        This will involve taking a tail log backup, so you must check your restore chain once it has completed.

    .PARAMETER PageRestoreTailFolder
        This parameter passes in a location for the tail log backup required for page level restore.

    .PARAMETER StopMark
        Marked point in the transaction log to stop the restore at (Mark is created via BEGIN TRANSACTION (https://docs.microsoft.com/en-us/sql/t-sql/language-elements/begin-transaction-transact-sql?view=sql-server-ver15)).

    .PARAMETER StopBefore
        Switch to indicate the restore should stop before StopMark occurs, default is to stop when mark is created.

    .PARAMETER StopAfterDate
        By default the restore will stop at the first occurence of StopMark found in the chain, passing a datetime where will cause it to stop the first StopMark atfer that datetime.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Prompts to confirm certain actions.

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Restore-DbaDatabase

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups

        Scans all the backup files in \\server2\backups, filters them and restores the database to server1\instance1

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores

        Scans all the backup files in \\server2\backups$ stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1

    .EXAMPLE
        PS C:\> Get-ChildItem c:\SQLbackups1\, \\server\sqlbackups2 | Restore-DbaDatabase -SqlInstance server1\instance1

        Takes the provided files from multiple directories and restores them on  server1\instance1

    .EXAMPLE
        PS C:\> $RestoreTime = Get-Date('11:19 23/12/2016')
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores -RestoreTime $RestoreTime

        Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1 up to 11:19 23/12/2016

    .EXAMPLE
        PS C:\> $result = Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -DestinationDataDirectory c:\restores -OutputScriptOnly
        PS C:\> $result | Out-File -Filepath c:\scripts\restore.sql

        Scans all the backup files in \\server2\backups, filters them and generate the T-SQL Scripts to restore the database to the latest point in time, and then stores the output in a file for later retrieval

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path c:\backups -DestinationDataDirectory c:\DataFiles -DestinationLogDirectory c:\LogFile

        Scans all the files in c:\backups and then restores them onto the SQL Server Instance server1\instance1, placing data files
        c:\DataFiles and all the log files into c:\LogFiles

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path http://demo.blob.core.windows.net/backups/dbbackup.bak -AzureCredential MyAzureCredential

        Will restore the backup held at  http://demo.blob.core.windows.net/backups/dbbackup.bak to server1\instance1. The connection to Azure will be made using the
        credential MyAzureCredential held on instance Server1\instance1

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path http://demo.blob.core.windows.net/backups/dbbackup.bak

        Will attempt to restore the backups from http://demo.blob.core.windows.net/backups/dbbackup.bak if a SAS credential with the name http://demo.blob.core.windows.net/backups exists on server1\instance1

    .EXAMPLE
        PS C:\> $File = Get-ChildItem c:\backups, \\server1\backups
        PS C:\> $File | Restore-DbaDatabase -SqlInstance Server1\Instance -UseDestinationDefaultDirectories

        This will take all of the files found under the folders c:\backups and \\server1\backups, and pipeline them into
        Restore-DbaDatabase. Restore-DbaDatabase will then scan all of the files, and restore all of the databases included
        to the latest point in time covered by their backups. All data and log files will be moved to the default SQL Server
        folder for those file types as defined on the target instance.

    .EXAMPLE
        PS C:\> $files = Get-ChildItem C:\dbatools\db1
        PS C:\> $params = @{
        >> SqlInstance = 'server\instance1'
        >> DestinationFilePrefix = 'prefix'
        >> DatabaseName ='Restored'
        >> RestoreTime = (get-date "14:58:30 22/05/2017")
        >> NoRecovery = $true
        >> WithReplace = $true
        >> StandbyDirectory = 'C:\dbatools\standby'
        >> }
        >>
        PS C:\> $files | Restore-DbaDatabase @params
        PS C:\> Invoke-DbaQuery -SQLInstance server\instance1 -Query "select top 1 * from Restored.dbo.steps order by dt desc"
        PS C:\> $params.RestoreTime = (get-date "15:09:30 22/05/2017")
        PS C:\> $params.NoRecovery = $false
        PS C:\> $params.Add("Continue",$true)
        PS C:\> $files | Restore-DbaDatabase @params
        PS C:\> Invoke-DbaQuery -SQLInstance server\instance1 -Query "select top 1 * from Restored.dbo.steps order by dt desc"
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -DestinationFilePrefix prefix -DatabaseName Restored -Continue -WithReplace

        In this example we step through the backup files held in c:\dbatools\db1 folder.
        First we restore the database to a point in time in standby mode. This means we can check some details in the databases
        We then roll it on a further 9 minutes to perform some more checks
        And finally we continue by rolling it all the way forward to the latest point in the backup.
        At each step, only the log files needed to roll the database forward are restored.

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -Path c:\backups -DatabaseName example1 -NoRecovery
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -Recover -DatabaseName example1

        In this example we restore example1 database with no recovery, and then the second call is to set the database to recovery.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory - SqlInstance server\instance1 -Database ProdFinance -Last | Restore-DbaDatabase -PageRestore
        PS C:\> $SuspectPage -PageRestoreTailFolder c:\temp -TrustDbBackupHistory

        Gets a list of Suspect Pages using Get-DbaSuspectPage. The uses Get-DbaDbBackupHistory and Restore-DbaDatabase to perform a restore of the suspect pages and bring them up to date
        If server\instance1 is Enterprise edition this will be done online, if not it will be performed offline

    .EXAMPLE
        PS C:\> $BackupHistory = Get-DbaBackupInformation -SqlInstance sql2005 -Path \\backups\sql2000\ProdDb
        PS C:\> $BackupHistory | Restore-DbaDatabase -SqlInstance sql2000 -TrustDbBackupHistory

        Due to SQL Server 2000 not returning all the backup headers we cannot restore directly. As this is an issues with the SQL engine all we can offer is the following workaround
        This will use a SQL Server instance > 2000 to read the headers, and then pass them in to Restore-DbaDatabase as a BackupHistory object.

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path "C:\Temp\devops_prod_full.bak" -DatabaseName "DevOps_DEV" -ReplaceDbNameInFile
        PS C:\> Rename-DbaDatabase -SqlInstance server1\instance1 -Database "DevOps_DEV" -LogicalName "<DBN>_<FT>"

        This will restore the database from the "C:\Temp\devops_prod_full.bak" file, with the new name "DevOps_DEV" and store the different physical files with the new name. It will use the system default configured data and log locations.
        After the restore the logical names of the database files will be renamed with the "DevOps_DEV_ROWS" for MDF/NDF and "DevOps_DEV_LOG" for LDF

    .EXAMPLE
        PS C:\> $FileStructure = @{
        >> 'database_data' = 'C:\Data\database_data.mdf'
        >> 'database_log' = 'C:\Log\database_log.ldf'
        >> }
        >>
        PS C:\> Restore-DbaDatabase -SqlInstance server1 -Path \\ServerName\ShareName\File -DatabaseName database -FileMapping $FileStructure

        Restores 'database' to 'server1' and moves the files to new locations. The format for the $FileStructure HashTable is the file logical name as the Key, and the new location as the Value.

    .EXAMPLE
        PS C:\> $filemap = Get-DbaDbFileMapping -SqlInstance sql2016 -Database test
        PS C:\> Get-ChildItem \\nas\db\backups\test | Restore-DbaDatabase -SqlInstance sql2019 -Database test -FileMapping $filemap.FileMapping

        Restores test to sql2019 using the file structure built from the existing database on sql2016

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1 -Path \\ServerName\ShareName\File -DatabaseName database -StopMark OvernightStart -StopBefore -StopAfterDate Get-Date('21:00 10/05/2020')

        Restores the backups from \\ServerName\ShareName\File as database, stops before the first 'OvernightStart' mark that occurs after '21:00 10/05/2020'.

        Note that Date time needs to be specified in your local SQL Server culture
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Restore")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "AzureCredential", Justification = "For Parameter AzureCredential")]
    param (
        [parameter(Mandatory)][DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Restore")][parameter(Mandatory, ValueFromPipeline, ParameterSetName = "RestorePage")][object[]]$Path,
        [parameter(ValueFromPipeline)][Alias("Name")][object[]]$DatabaseName,
        [parameter(ParameterSetName = "Restore")][String]$DestinationDataDirectory,
        [parameter(ParameterSetName = "Restore")][String]$DestinationLogDirectory,
        [parameter(ParameterSetName = "Restore")][String]$DestinationFileStreamDirectory,
        [parameter(ParameterSetName = "Restore")][DateTime]$RestoreTime = (Get-Date).AddYears(1),
        [parameter(ParameterSetName = "Restore")][switch]$NoRecovery,
        [parameter(ParameterSetName = "Restore")][switch]$WithReplace,
        [parameter(ParameterSetName = "Restore")][switch]$KeepReplication,
        [parameter(ParameterSetName = "Restore")][Switch]$XpDirTree,
        [parameter(ParameterSetName = "Restore")][Switch]$NoXpDirRecurse,
        [switch]$OutputScriptOnly,
        [parameter(ParameterSetName = "Restore")][switch]$VerifyOnly,
        [parameter(ParameterSetName = "Restore")][switch]$MaintenanceSolutionBackup,
        [parameter(ParameterSetName = "Restore", ValueFromPipelineByPropertyname)][hashtable]$FileMapping,
        [parameter(ParameterSetName = "Restore")][switch]$IgnoreLogBackup,
        [parameter(ParameterSetName = "Restore")][switch]$IgnoreDiffBackup,
        [parameter(ParameterSetName = "Restore")][switch]$UseDestinationDefaultDirectories,
        [parameter(ParameterSetName = "Restore")][switch]$ReuseSourceFolderStructure,
        [parameter(ParameterSetName = "Restore")][string]$DestinationFilePrefix = '',
        [parameter(ParameterSetName = "Restore")][string]$RestoredDatabaseNamePrefix,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][switch]$TrustDbBackupHistory,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$MaxTransferSize,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$BlockSize,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$BufferCount,
        [parameter(ParameterSetName = "Restore")][switch]$DirectoryRecurse,
        [switch]$EnableException,
        [parameter(ParameterSetName = "Restore")][string]$StandbyDirectory,
        [parameter(ParameterSetName = "Restore")][switch]$Continue,
        [parameter(ParameterSetName = "Restore")][string]$ExecuteAs,
        [string]$AzureCredential,
        [parameter(ParameterSetName = "Restore")][switch]$ReplaceDbNameInFile,
        [parameter(ParameterSetName = "Restore")][string]$DestinationFileSuffix,
        [parameter(ParameterSetName = "Recovery")][switch]$Recover,
        [parameter(ParameterSetName = "Restore")][switch]$KeepCDC,
        [string]$GetBackupInformation,
        [switch]$StopAfterGetBackupInformation,
        [string]$SelectBackupInformation,
        [switch]$StopAfterSelectBackupInformation,
        [string]$FormatBackupInformation,
        [switch]$StopAfterFormatBackupInformation,
        [string]$TestBackupInformation,
        [switch]$StopAfterTestBackupInformation,
        [parameter(Mandatory, ParameterSetName = "RestorePage")][object]$PageRestore,
        [parameter(Mandatory, ParameterSetName = "RestorePage")][string]$PageRestoreTailFolder,
        [switch]$StopBefore,
        [string]$StopMark,
        [datetime]$StopAfterDate = (Get-Date '01/01/1971'),
        [int]$StatementTimeout = 0
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"

        #region Validation
        try {
            $RestoreInstance = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database master
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        if ($RestoreInstance.DatabaseEngineEdition -eq "SqlManagedInstance") {
            Write-Message -Level Verbose -Message "Restore target is a Managed Instance, restricted feature set available"
            $MiParams = ("DestinationDataDirectory", "DestinationLogDirectory", "DestinationFileStreamDirectory", "XpDirTree", "FileMapping", "UseDestinationDefaultDirectories", "ReuseSourceFolderStructure", "DestinationFilePrefix", "StandbyDirecttory", "ReplaceDbNameInFile", "KeepCDC")
            ForEach ($MiParam in $MiParams) {
                if (Test-Bound $MiParam) {
                    # Write-Message -Level Warning "Restoring to a Managed SQL Instance, parameter $MiParm is not supported"
                    Stop-Function -Category InvalidArgument -Message "The parameter $MiParam cannot be used with a Managed SQL Instance"
                    return
                }
            }
        }

        if ($PSCmdlet.ParameterSetName -eq "Restore") {
            $UseDestinationDefaultDirectories = $true
            $paramCount = 0

            if (Test-Bound "FileMapping") {
                $paramCount += 1
            }
            If (Test-Bound "ExecuteAs") {
                if ((Get-DbaLogin -SqlInstance $RestoreInstance -Login $ExecuteAs).count -eq 0) {
                    Stop-Function -Category  InvalidArgument -Message "You specified a Login to execute the restore, but the login '$ExecuteAs' does not exist"
                    return
                }
            }
            if (Test-Bound "ReuseSourceFolderStructure") {
                $paramCount += 1
            }
            if (Test-Bound "DestinationDataDirectory") {
                $paramCount += 1
            }
            if ($paramCount -gt 1) {
                Stop-Function -Category InvalidArgument -Message "You've specified incompatible Location parameters. Please only specify one of FileMapping, ReuseSourceFolderStructure or DestinationDataDirectory"
                return
            }
            if (($ReplaceDbNameInFile) -and !(Test-Bound "DatabaseName")) {
                Stop-Function -Category InvalidArgument -Message "To use ReplaceDbNameInFile you must specify DatabaseName"
                return
            }

            if ((Test-Bound "DestinationLogDirectory") -and (Test-Bound "ReuseSourceFolderStructure")) {
                Stop-Function -Category InvalidArgument -Message "The parameters DestinationLogDirectory and UseDestinationDefaultDirectories are mutually exclusive"
                return
            }
            if ((Test-Bound "DestinationLogDirectory") -and -not (Test-Bound "DestinationDataDirectory")) {
                Stop-Function -Category InvalidArgument -Message "The parameter DestinationLogDirectory can only be specified together with DestinationDataDirectory"
                return
            }
            if ((Test-Bound "DestinationFileStreamDirectory") -and (Test-Bound "ReuseSourceFolderStructure")) {
                Stop-Function -Category InvalidArgument -Message "The parameters DestinationFileStreamDirectory and UseDestinationDefaultDirectories are mutually exclusive"
                return
            }
            if ((Test-Bound "DestinationFileStreamDirectory") -and -not (Test-Bound "DestinationDataDirectory")) {
                Stop-Function -Category InvalidArgument -Message "The parameter DestinationFileStreamDirectory can only be specified together with DestinationDataDirectory"
                return
            }
            if ((Test-Bound "ReuseSourceFolderStructure") -and (Test-Bound "UseDestinationDefaultDirectories")) {
                Stop-Function -Category InvalidArgument -Message "The parameters UseDestinationDefaultDirectories and ReuseSourceFolderStructure cannot both be applied "
                return
            }

            if (($null -ne $FileMapping) -or $ReuseSourceFolderStructure -or ($DestinationDataDirectory -ne '')) {
                $UseDestinationDefaultDirectories = $false
            }
            if (($MaxTransferSize % 64kb) -ne 0 -or $MaxTransferSize -gt 4mb) {
                Stop-Function -Category InvalidArgument -Message "MaxTransferSize value must be a multiple of 64kb and no greater than 4MB"
                return
            }
            if ($BlockSize) {
                if ($BlockSize -notin (0.5kb, 1kb, 2kb, 4kb, 8kb, 16kb, 32kb, 64kb)) {
                    Stop-Function -Category InvalidArgument -Message "Block size must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb,64kb"
                    return
                }
            }
            if ('' -ne $StandbyDirectory) {
                if (!(Test-DbaPath -Path $StandbyDirectory -SqlInstance $RestoreInstance)) {
                    Stop-Function -Message "$SqlServer cannot see the specified Standby Directory $StandbyDirectory" -Target $SqlInstance
                    return
                }
            }
            if ($KeepCDC -and ($NoRecovery -or ('' -ne $StandbyDirectory))) {
                Stop-Function -Category InvalidArgument -Message "KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
                return
            }
            if ($Continue) {
                Write-Message -Message "Called with continue, so assume we have an existing db in norecovery"
                $WithReplace = $True
                $ContinuePoints = Get-RestoreContinuableDatabase -SqlInstance $RestoreInstance
                $LastRestoreType = Get-DbaDbRestoreHistory -SqlInstance $RestoreInstance -Last
            }
            if (!($PSBoundParameters.ContainsKey("DataBasename"))) {
                $PipeDatabaseName = $true
            }
            if ($OutputScriptOnly -and $VerifyOnly) {
                Stop-Function -Category InvalidArgument -Message "The switches OutputScriptOnly and VerifyOnly cannot both be specified at the same time, stopping"
                return
            }
        }

        if ($StatementTimeout -eq 0) {
            Write-Message -Level Verbose -Message "Changing statement timeout to infinity"
        } else {
            Write-Message -Level Verbose -Message "Changing statement timeout to ($StatementTimeout) minutes"
        }
        $RestoreInstance.ConnectionContext.StatementTimeout = ($StatementTimeout * 60)
        #endregion Validation

        if ($UseDestinationDefaultDirectories) {
            $DefaultPath = (Get-DbaDefaultPath -SqlInstance $RestoreInstance)
            $DestinationDataDirectory = $DefaultPath.Data
            $DestinationLogDirectory = $DefaultPath.Log
        }

        $BackupHistory = @()
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($RestoreInstance.VersionMajor -eq 8 -and $true -ne $TrustDbBackupHistory) {
            foreach ($file in $Path) {
                $bh = Get-DbaBackupInformation -SqlInstance $RestoreInstance -Path $file
                $bound = $PSBoundParameters
                $bound['TrustDbBackupHistory'] = $true
                $bound['Path'] = $bh
                Restore-DbaDatabase @bound
            }
            # Flag function interrupt to silently not execute end
            ${__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r} = $true
            return
        }
        if ($PSCmdlet.ParameterSetName -like "Restore*") {
            if ($PipeDatabaseName -eq $true) {
                $DatabaseName = ''
            }
            Write-Message -message "ParameterSet  = Restore" -Level Verbose
            if ($TrustDbBackupHistory -or $path[0].GetType().ToString() -eq 'Sqlcollaborative.Dbatools.Database.BackupHistory') {
                foreach ($f in $path) {
                    Write-Message -Level Verbose -Message "Trust Database Backup History Set"
                    if ("BackupPath" -notin $f.PSObject.Properties.name) {
                        Write-Message -Level Verbose -Message "adding BackupPath - $($_.FullName)"
                        $f = $f | Select-Object *, @{ Name = "BackupPath"; Expression = { $_.FullName } }
                    }
                    if ("DatabaseName" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "DatabaseName"; Expression = { $_.Database } }
                    }
                    if ("Database" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "Database"; Expression = { $_.DatabaseName } }
                    }
                    if ("BackupSetGUID" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "BackupSetGUID"; Expression = { $_.BackupSetID } }
                    }
                    if ($f.BackupPath -like 'http*') {
                        if ('' -ne $AzureCredential) {
                            Write-Message -Message "At least one Azure backup passed in with a credential, assume correct" -Level Verbose
                            Write-Message -Message "Storage Account Identity access means striped backups cannot be restore"
                        } else {
                            if ($f.BackupPath.count -gt 1) {
                                $null = $f.BackupPath[0] -match '(http|https)://[^/]*/[^/]*'
                            } else {
                                $null = $f.BackupPath -match '(http|https)://[^/]*/[^/]*'
                            }
                            if (Get-DbaCredential -SqlInstance $RestoreInstance -Name $matches[0].trim('/') ) {
                                Write-Message -Message "We have a SAS credential to use with $($f.BackupPath)" -Level Verbose
                            } else {
                                Stop-Function -Message "A URL to a backup has been passed in, but no credential can be found to access it"
                                return
                            }
                        }
                    }
                    # Fix #5036 by implementing a deep copy of the FileList
                    $f.FileList = $f.FileList | Select-Object *
                    $BackupHistory += $f | Select-Object *, @{ Name = "ServerName"; Expression = { $_.SqlInstance } }, @{ Name = "BackupStartDate"; Expression = { $_.Start -as [DateTime] } }
                }
            } else {
                $files = @()
                foreach ($f in $Path) {
                    if ($f -is [System.IO.FileSystemInfo]) {
                        $files += $f.FullName
                    } else {
                        $files += $f
                    }
                }
                Write-Message -Level Verbose -Message "Unverified input, full scans - $($files -join ';')"
                if ($BackupHistory.GetType().ToString() -eq 'Sqlcollaborative.Dbatools.Database.BackupHistory') {
                    $BackupHistory = @($BackupHistory)
                }
                $BackupHistory += Get-DbaBackupInformation -SqlInstance $RestoreInstance -SqlCredential $SqlCredential -Path $files -DirectoryRecurse:$DirectoryRecurse -MaintenanceSolution:$MaintenanceSolutionBackup -IgnoreDiffBackup:$IgnoreDiffBackup -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -NoXpDirRecurse:$NoXpDirRecurse
            }
            if ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if (-not (Test-DbaPath -SqlInstance $RestoreInstance -Path $PageRestoreTailFolder)) {
                    Stop-Function -Message "Instance $RestoreInstance cannot read $PageRestoreTailFolder, cannot proceed" -Target $PageRestoreTailFolder
                    return
                }
                $WithReplace = $true
            }
        } elseif ($PSCmdlet.ParameterSetName -eq "Recovery") {
            Write-Message -Message "$($Database.Count) databases to recover" -level Verbose
            foreach ($Database in $DatabaseName) {
                if ($Database -is [object]) {
                    #We've got an object, try the normal options Database, DatabaseName, Name
                    if ("Database" -in $Database.PSObject.Properties.Name) {
                        [string]$DataBase = $Database.Database
                    } elseif ("DatabaseName" -in $Database.PSObject.Properties.Name) {
                        [string]$DataBase = $Database.DatabaseName
                    } elseif ("Name" -in $Database.PSObject.Properties.Name) {
                        [string]$Database = $Database.name
                    }
                }
                Write-Message -Level Verbose -Message "existence - $($RestoreInstance.Databases[$DataBase].State)"
                if ($RestoreInstance.Databases[$DataBase].State -ne 'Existing') {
                    Write-Message -Message "$Database does not exist on $RestoreInstance" -level Warning
                    continue
                }
                if ($RestoreInstance.Databases[$Database].Status -ne "Restoring") {
                    Write-Message -Message "$Database on $RestoreInstance is not in a Restoring State" -Level Warning
                    continue
                }
                $RestoreComplete = $true
                $RecoverSql = "RESTORE DATABASE [$Database] WITH RECOVERY"
                Write-Message -Message "Recovery Sql Query - $RecoverSql" -level verbose
                try {
                    $RestoreInstance.query($RecoverSql)
                } catch {
                    $RestoreComplete = $False
                    $ExitError = $_.Exception.InnerException
                    Write-Message -Level Warning -Message "Failed to recover $Database on $RestoreInstance, `n $ExitError"
                } finally {
                    [PSCustomObject]@{
                        SqlInstance     = $SqlInstance
                        DatabaseName    = $Database
                        RestoreComplete = $RestoreComplete
                        Scripts         = $RecoverSql
                    }
                }
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) {
            return
        }
        if (($BackupHistory.Database | Sort-Object -Unique).count -gt 1 -and ('' -ne $DatabaseName)) {
            Stop-Function -Message "Multiple Databases' backups passed in, but only 1 name to restore them under. Stopping as cannot work out how to proceed" -Category  InvalidArgument
            return
        }
        if ($PSCmdlet.ParameterSetName -like "Restore*") {
            if ($BackupHistory.Count -eq 0 -and $RestoreInstance.VersionMajor -ne 8) {
                Write-Message -Level Warning -Message "No backups passed through. `n This could mean the SQL instance cannot see the referenced files, the file's headers could not be read or some other issue"
                return
            }
            Write-Message -message "Processing DatabaseName - $DatabaseName" -Level Verbose
            $FilteredBackupHistory = @()
            if (Test-Bound -ParameterName GetBackupInformation) {
                Write-Message -Message "Setting $GetBackupInformation to BackupHistory" -Level Verbose
                Set-Variable -Name $GetBackupInformation -Value $BackupHistory -Scope Global
            }
            if ($StopAfterGetBackupInformation) {
                return
            }
            $pathSep = Get-DbaPathSep -Server $RestoreInstance
            $BackupHistory = $BackupHistory | Format-DbaBackupInformation -DataFileDirectory $DestinationDataDirectory -LogFileDirectory $DestinationLogDirectory -DestinationFileStreamDirectory $DestinationFileStreamDirectory -DatabaseFileSuffix $DestinationFileSuffix -DatabaseFilePrefix $DestinationFilePrefix -DatabaseNamePrefix $RestoredDatabaseNamePrefix -ReplaceDatabaseName $DatabaseName -Continue:$Continue -ReplaceDbNameInFile:$ReplaceDbNameInFile -FileMapping $FileMapping -PathSep $pathSep

            if (Test-Bound -ParameterName FormatBackupInformation) {
                Set-Variable -Name $FormatBackupInformation -Value $BackupHistory -Scope Global
            }
            if ($StopAfterFormatBackupInformation) {
                return
            }
            if ($VerifyOnly) {
                $FilteredBackupHistory = $BackupHistory
            } else {
                $FilteredBackupHistory = $BackupHistory | Select-DbaBackupInformation -RestoreTime $RestoreTime -IgnoreLogs:$IgnoreLogBackups -IgnoreDiffs:$IgnoreDiffBackup -ContinuePoints $ContinuePoints -LastRestoreType $LastRestoreType -DatabaseName $DatabaseName
            }
            if (Test-Bound -ParameterName SelectBackupInformation) {
                Write-Message -Message "Setting $SelectBackupInformation to FilteredBackupHistory" -Level Verbose
                Set-Variable -Name $SelectBackupInformation -Value $FilteredBackupHistory -Scope Global

            }
            if ($StopAfterSelectBackupInformation) {
                return
            }
            try {
                Write-Message -Level Verbose -Message "VerifyOnly = $VerifyOnly"
                $null = $FilteredBackupHistory | Test-DbaBackupInformation -SqlInstance $RestoreInstance -WithReplace:$WithReplace -Continue:$Continue -VerifyOnly:$VerifyOnly -EnableException:$true -OutputScriptOnly:$OutputScriptOnly
            } catch {
                Stop-Function -ErrorRecord $_ -Message "Failure" -Continue
            }
            if (Test-Bound -ParameterName TestBackupInformation) {
                Set-Variable -Name $TestBackupInformation -Value $FilteredBackupHistory -Scope Global
            }
            if ($StopAfterTestBackupInformation) {
                return
            }
            $DbVerfied = ($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $True } | Sort-Object -Property Database -Unique).Database -join ','
            Write-Message -Message "$DbVerfied passed testing" -Level Verbose
            if ((@($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $True })).count -lt $FilteredBackupHistory.count) {
                $DbUnVerified = ($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $False } | Sort-Object -Property Database -Unique).Database -join ','
                Write-Message -Level Warning -Message "Database $DbUnverified failed testing,  skipping"
            }
            If ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if (($FilteredBackupHistory.Database | Sort-Object -Unique | Measure-Object).count -ne 1) {
                    Stop-Function -Message "Must only 1 database passed in for Page Restore. Sorry"
                    return
                } else {
                    $WithReplace = $false
                }
            }
            Write-Message -Message "Passing in to restore" -Level Verbose

            if ($PSCmdlet.ParameterSetName -eq "RestorePage" -and $RestoreInstance.Edition -notlike '*Enterprise*') {
                Write-Message -Message "Taking Tail log backup for page restore for non-Enterprise" -Level Verbose
                $TailBackup = Backup-DbaDatabase -SqlInstance $RestoreInstance -Database $DatabaseName -Type Log -BackupDirectory $PageRestoreTailFolder -NoRecovery -CopyOnly
            }
            try {
                $FilteredBackupHistory | Where-Object { $_.IsVerified -eq $true } | Invoke-DbaAdvancedRestore -SqlInstance $RestoreInstance -WithReplace:$WithReplace -RestoreTime $RestoreTime -StandbyDirectory $StandbyDirectory -NoRecovery:$NoRecovery -Continue:$Continue -OutputScriptOnly:$OutputScriptOnly -BlockSize $BlockSize -MaxTransferSize $MaxTransferSize -BufferCount $Buffercount -KeepCDC:$KeepCDC -VerifyOnly:$VerifyOnly -PageRestore $PageRestore -EnableException -AzureCredential $AzureCredential -KeepReplication:$KeepReplication -StopMark:$StopMark -StopAfterDate:$StopAfterDate -StopBefore:$StopBefore -ExecuteAs $ExecuteAs
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -Target $RestoreInstance
            }
            if ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if ($RestoreInstance.Edition -like '*Enterprise*') {
                    Write-Message -Message "Taking Tail log backup for page restore for Enterprise" -Level Verbose
                    $TailBackup = Backup-DbaDatabase -SqlInstance $RestoreInstance -Database $DatabaseName -Type Log -BackupDirectory $PageRestoreTailFolder -NoRecovery -CopyOnly
                }
                Write-Message -Message "Restoring Tail log backup for page restore" -Level Verbose
                $TailBackup | Restore-DbaDatabase -SqlInstance $RestoreInstance -TrustDbBackupHistory -NoRecovery -OutputScriptOnly:$OutputScriptOnly -BlockSize $BlockSize -MaxTransferSize $MaxTransferSize -BufferCount $Buffercount -Continue
                Restore-DbaDatabase -SqlInstance $RestoreInstance -Recover -DatabaseName $DatabaseName -OutputScriptOnly:$OutputScriptOnly
            }
            # refresh the SMO as we probably used T-SQL, but only if we already got a SMO
            if ($SqlInstance.InputObject -is [Microsoft.SqlServer.Management.Smo.Server]) {
                $SqlInstance.InputObject.Databases.Refresh()
            }
        }
    }
}

# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCl4/8CqM9f4w1m
# axjIqd4TsNTRKppS5h5SEc+7ykzk+aCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDTrVYqJJJeBLaxAS0m0GqE8dwJEVVSEv7G
# JwwojqL8PTANBgkqhkiG9w0BAQEFAASCAQAC/qiwvc7AjVQYCKJrannCzVUiTwzs
# sFrsSi3SugP9yrG+HPJoKnGhcall8eElX3N+1tc8/xzY6ijeSABoM6BTynSLadaT
# 5lsyVto2TQgYxnfTgHo79EfoBuAPh0FZASlBHOiSazemquhVb8GxjPCCjaQEtmmr
# 1YScG1qE+Ia+r3g85qEb6igGWwulTjXz26avmpkMU+oeptF9qUNbtrzunKJ6/s1i
# 8+GW4MY3ZkWHywk58eeklZEukVhs9at3Ul6tqmuW1Y4618/7HAGECiZh5ES9WcR4
# r1Y7J6dnYTKwDE1cmkS17p42go+jxJlogoXUI4/6NUK0nwujP+N9T8hpoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDM1MlowLwYJKoZIhvcNAQkEMSIEIJ8JesuB
# wNURrj8v2JYwkwZMa+5ycDytKalXKma4O8epMA0GCSqGSIb3DQEBAQUABIICAEBY
# TnyH/xBB8/hkSFPGcm4aHVsT8OdhquH4SAuAMaKlQObzTR4QG+Hy5RwwhYSmUYaS
# 1CaGA9FpXSIMV/5vtaTNOue36kDHbFvxOY4M2VVESQ+DLhcnlQCastIUfwlOX/G1
# QXR0Ply81P3MQO3vrNGZ9zhAEAnsoblijxy9fnwyfOkhXEWEWc97hawAEu964Vew
# ezIFZKrsWdXprW3aARPM0Mx78Za9eZyRQDVJ/CbfFfGR2bODf/KEBcCNtggkPgHI
# hH1jrOHqwymySTr+VNeif8mh5NIiI1ryJa3B0L/OytMG0dDuk86QqRRZhIKmv4HO
# gsF8Gltm+okiuAu12zRRSzwFHyiinWabyigggD4fv0zZeiFmKolX65GdQ+xqkTMN
# /rX0av1lmkpZdE9jom1FoeqU/WWSzpWIRIzll/rnCtKHy3rva/5K/nXPDM/itQYO
# aS9oOxoZsHGMsUC7LgnKAMx3OtO/lrsLIm50aBEsnQC9fRghn7GYlDkxVQUMJpiV
# OiGk9Tzx10wh5CeZqqIp0vediVUtEtDZoVdiGiiUgqinMqNgnpV2fFfv14ZWKRli
# hQO42wrjy9BxMcEWdXc6GZuFHzCExJG++8OjieO3ToyhsRASLbPlof2feFrHNkBp
# R4m4ZKAMjbTEJO3wj0g3skDuvIU5g9MMk2UcDBG3
# SIG # End signature block
