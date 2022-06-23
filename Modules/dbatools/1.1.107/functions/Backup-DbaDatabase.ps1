function Backup-DbaDatabase {
    <#
    .SYNOPSIS
        Backup one or more SQL Server databases from a single SQL Server SqlInstance.

    .DESCRIPTION
        Performs a backup of a specified type of 1 or more databases on a single SQL Server Instance. These backups may be Full, Differential or Transaction log backups.

    .PARAMETER SqlInstance
        The SQL Server instance hosting the databases to be backed up.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER FilePath
        The name of the file to backup to. This is only accepted for single database backups.
        If no name is specified then the backup files will be named DatabaseName_yyyyMMddHHmm (i.e. "Database1_201714022131") with the appropriate extension.

        If the same name is used repeatedly, SQL Server will add backups to the same file at an incrementing position.

        SQL Server needs permissions to write to the specified location. Path names are based on the SQL Server (C:\ is the C drive on the SQL Server, not the machine running the script).

        Passing in NUL as the FilePath will backup to the NUL: device

    .PARAMETER IncrementPrefix
        If enabled, this will prefix backup files with an incrementing integer (ie; '1-', '2-'). Using this has been alleged to improved restore times on some Azure based SQL Database platforms

    .PARAMETER TimeStampFormat
        By default the command timestamps backups using the format yyyyMMddHHmm. Using this parameter this can be overridden. The timestamp format should be defined using the Get-Date formats, illegal formats will cause an error to be thrown

    .PARAMETER Path
        Path in which to place the backup files. If not specified, the backups will be placed in the default backup location for SqlInstance.
        If multiple paths are specified, the backups will be striped across these locations. This will overwrite the FileCount option.

        If the path does not exist, Sql Server will attempt to create it. Folders are created by the Sql Instance, and checks will be made for write permissions.

        File Names with be suffixed with x-of-y to enable identifying striped sets, where y is the number of files in the set and x ranges from 1 to y.

    .PARAMETER ReplaceInName
        If this switch is set, the following list of strings will be replaced in the FilePath and Path strings:
            instancename - will be replaced with the instance Name
            servername - will be replaced with the server name
            dbname - will be replaced with the database name
            timestamp - will be replaced with the timestamp (either the default, or the format provided)
            backuptype - will be replaced with Full, Log or Differential as appropriate

    .PARAMETER CopyOnly
        If this switch is enabled, CopyOnly backups will be taken. By default function performs a normal backup, these backups interfere with the restore chain of the database. CopyOnly backups will not interfere with the restore chain of the database.

        For more details please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms191495.aspx

    .PARAMETER Type
        The type of SQL Server backup to perform. Accepted values are "Full", "Log", "Differential", "Diff", "Database"

    .PARAMETER FileCount
        This is the number of striped copies of the backups you wish to create.    This value is overwritten if you specify multiple Backup Directories.

    .PARAMETER CreateFolder
        If this switch is enabled, each database will be backed up into a separate folder on each of the paths specified by Path.

    .PARAMETER CompressBackup
        If this switch is enabled, the function will try to perform a compressed backup if supported by the version and edition of SQL Server. Otherwise, this function will use the server(s) default setting for compression.

    .PARAMETER MaxTransferSize
        Sets the size of the unit of transfer. Values must be a multiple of 64kb.

    .PARAMETER Blocksize
        Specifies the block size to use. Must be one of 0.5KB, 1KB, 2KB, 4KB, 8KB, 16KB, 32KB or 64KB. This can be specified in bytes.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER Checksum
        If this switch is enabled, the backup checksum will be calculated.

    .PARAMETER Verify
        If this switch is enabled, the backup will be verified by running a RESTORE VERIFYONLY against the SqlInstance

    .PARAMETER WithFormat
        Formats the media as the first step of the backup operation. NOTE: This will set Initialize and SkipTapeHeader to $true.

    .PARAMETER Initialize
        Initializes the media as part of the backup operation.

    .PARAMETER SkipTapeHeader
        Initializes the media as part of the backup operation.

    .PARAMETER InputObject
        Internal parameter

    .PARAMETER AzureBaseUrl
        The URL(s) to the base container of an Azure Storage account to write backups to.
        If specifying the AzureCredential parameter you can only provide 1 value as page blobs do not support multiple URLs
        If using Shared Access keys, you may specify as many URLs as you want, as long as a corresponding credential exists on the source server.
        If specified, the only other parameters than can be used are "CopyOnly", "Type", "CompressBackup", "Checksum", "Verify", "AzureCredential", "CreateFolder".

    .PARAMETER AzureCredential
        The name of the credential on the SQL instance that can write to the AzureBaseUrl, only needed if using Storage access keys
        If using SAS credentials, the command will look for a credential with a name matching the AzureBaseUrl. As page blobs are used with this option we force the number of files to 1 and ignore any value passed in for BlockSize or MaxTransferSize

    .PARAMETER NoRecovery
        This is passed in to perform a tail log backup if needed

    .PARAMETER BuildPath
        By default this command will not attempt to create missing paths, this switch will change the behaviour so that it will

    .PARAMETER IgnoreFileChecks
        This switch stops the function from checking for the validity of paths. This can be useful if SQL Server only has read access to the backup area.
        Note, that as we cannot check the path you may well end up with errors.

    .PARAMETER OutputScriptOnly
        Switch causes only the T-SQL script for the backup to be generated. Will not create any paths if they do not exist

    .PARAMETER EncryptionAlgorithm
        Specified the Encryption Algorithm to used. Must be one of 'AES128','AES192','AES256' or 'TRIPLEDES'
        Must specify one of EncryptionCertificate or EncryptionKey as well.

    .PARAMETER EncryptionCertificate
        The name of the certificate to be used to encrypt the backups. The existence of the certificate will be checked, and will not proceed if it does not exist
        Is mutually exclusive with the EncryptionKey option

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Backup-DbaDatabase

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Server1 -Database HR, Finance

        This will perform a full database backup on the databases HR and Finance on SQL Server Instance Server1 to Server1 default backup directory.

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance sql2016 -Path C:\temp -Database AdventureWorks2014 -Type Full

        Backs up AdventureWorks2014 to sql2016 C:\temp folder.

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance sql2016 -AzureBaseUrl https://dbatoolsaz.blob.core.windows.net/azbackups/ -AzureCredential dbatoolscred -Type Full -CreateFolder

        Performs a full backup of all databases on the sql2016 instance to their own containers under the https://dbatoolsaz.blob.core.windows.net/azbackups/ container on Azure blob storage using the sql credential "dbatoolscred" registered on the sql2016 instance.

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance sql2016 -AzureBaseUrl https://dbatoolsaz.blob.core.windows.net/azbackups/  -Type Full

        Performs a full backup of all databases on the sql2016 instance to the https://dbatoolsaz.blob.core.windows.net/azbackups/ container on Azure blob storage using the Shared Access Signature sql credential "https://dbatoolsaz.blob.core.windows.net/azbackups" registered on the sql2016 instance.

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Server1\Prod -Database db1 -Path \\filestore\backups\servername\instancename\dbname\backuptype -Type Full -ReplaceInName

        Performs a full backup of db1 into the folder \\filestore\backups\server1\prod\db1\Full

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Server1\Prod -Path \\filestore\backups\servername\instancename\dbname\backuptype -FilePath dbname-backuptype-timestamp.trn -Type Log -ReplaceInName

        Performs a log backup for every database. For the database db1 this would results in backup files in \\filestore\backups\server1\prod\db1\Log\db1-log-31102018.trn

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Sql2017 -Database master -FilePath NUL

        Performs a backup of master, but sends the output to the NUL device (ie; throws it away)

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Sql2016 -Database stripetest -AzureBaseUrl https://az.blob.core.windows.net/sql,https://dbatools.blob.core.windows.net/sql

        Performs a backup of the database stripetest, striping it across the 2 Azure blob containers at https://az.blob.core.windows.net/sql and https://dbatools.blob.core.windows.net/sql, assuming that Shared Access Signature credentials for both containers exist on the source instance

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Sql2017 -Database master -EncryptionAlgorithm AES256 -EncryptionCertificate BackupCert

        Backs up the master database using the BackupCert certificate and the AES256 algorithm.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")] #For AzureCredential
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias('BackupDirectory')]
        [string[]]$Path,
        [Alias('BackupFileName')]
        [string]$FilePath,
        [switch]$IncrementPrefix,
        [switch]$ReplaceInName,
        [switch]$CopyOnly,
        [ValidateSet('Full', 'Log', 'Differential', 'Diff', 'Database')]
        [string]$Type = 'Database',
        [parameter(ParameterSetName = "NoPipe", Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$CreateFolder,
        [int]$FileCount = 0,
        [switch]$CompressBackup,
        [switch]$Checksum,
        [switch]$Verify,
        [int]$MaxTransferSize,
        [int]$BlockSize,
        [int]$BufferCount,
        [string[]]$AzureBaseUrl,
        [string]$AzureCredential,
        [switch]$NoRecovery,
        [switch]$BuildPath,
        [switch]$WithFormat,
        [switch]$Initialize,
        [switch]$SkipTapeHeader,
        [string]$TimeStampFormat,
        [switch]$IgnoreFileChecks,
        [switch]$OutputScriptOnly,
        [ValidateSet('AES128', 'AES192', 'AES256', 'TRIPLEDES')]
        [String]$EncryptionAlgorithm,
        [String]$EncryptionCertificate,
        [switch]$EnableException
    )

    begin {
        # This is here ready to go when get EKM working so we can do encrption with asymmetric encryption.
        $EncryptionKey = $null

        if (-not (Test-Bound 'TimeStampFormat')) {
            Write-Message -Message 'Setting Default timestampformat' -Level Verbose
            $TimeStampFormat = "yyyyMMddHHmm"
        }

        if ((Test-Bound 'AzureBaseUrl') -and (Test-Bound 'CreateFolder')) {
            Stop-Function -Message 'CreateFolder cannot be specified with an Azure Backup, the container must exist and be referenced by the URL'
            return
        }

        if ((Test-Bound 'AzureCredential') -and (Test-Bound 'BlockSize')) {
            Write-Message -Level Warning -Message 'BlockSize cannot be specified when backup up to an Azure page blob, ignoring'
            $BlockSize = $null
        }

        if ((Test-Bound 'AzureCredential') -and (Test-Bound 'MaxTransferSize')) {
            Write-Message -Level Warning -Message 'MaxTransferSize cannot be specified when backup up to an Azure page blob ignoring'
            $MaxTransferSize = $null
        }

        if ($SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AzureUnsupported -Database master
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }

            $InputObject = $server.Databases | Where-Object Name -ne 'tempdb'

            if ($Database) {
                $InputObject = $InputObject | Where-Object Name -in $Database
            }

            if ($ExcludeDatabase) {
                $InputObject = $InputObject | Where-Object Name -notin $ExcludeDatabase
            }

            if ($Path.Count -gt 1) {
                Write-Message -Level Verbose -Message "Multiple Backup Directories, striping"
                $FileCount = $Path.Count
            }

            if ($InputObject.Count -gt 1 -and $FilePath -ne '' -and $True -ne $ReplaceInName) {
                Stop-Function -Message "1 BackupFile specified, but more than 1 database."
                return
            }
        }

        # this had to be a function. making it a variable killed something. I'm guessing scoping issues
        Function Convert-BackupPath ($object) {
            if ($object -match "/|\\") {
                if ($isdestlinux -and $object) {
                    $object = $object.Replace("\", "/")
                } elseif ($transformedbackupfolder) {
                    $object = $object.Replace("/", "\")
                }
            }
            $object
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        if ($IsMacOS -or $IsLinux) {
            $nonwindows = $true
        }
        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "You must specify a server and database or pipe some databases"
            return
        }

        Write-Message -Level Verbose -Message "$($InputObject.Count) database to backup"

        if ($Database) {
            $InputObject = $InputObject | Where-Object Name -in $Database
        }

        if ($ExcludeDatabase) {
            $InputObject = $InputObject | Where-Object Name -notin $ExcludeDatabase
        }

        if ($InputObject.count -eq 0) {
            Write-Message -Level Warning -Message "No databases match the request for backups"
        }

        $topProgressId = Get-Random
        $topProgressTarget = $InputObject.Count
        $topProgressNumber = 0
        foreach ($db in $InputObject) {
            $topProgressPercent = [int]($topProgressNumber * 100 / $topProgressTarget)
            $topProgressNumber++
            if (-not $PSCmdlet.MyInvocation.ExpectingInput) {
                # Only when the databases to be processed are not piped to the command
                Write-Progress -Id $topProgressId -Activity "Backing up database $topProgressNumber of $topProgressTarget" -PercentComplete $topProgressPercent -Status ([System.String]::Format("Progress: {0} %", $topProgressPercent))
            }

            $ProgressId = Get-Random
            $failures = @()
            $dbName = $db.Name
            $server = $db.Parent
            $null = $server.Refresh()
            $isdestlinux = Test-HostOSLinux -SqlInstance $server

            if (Test-Bound 'EncryptionAlgorithm') {
                if (!((Test-Bound 'EncryptionCertificate') -xor (Test-Bound 'EncryptionKey'))) {
                    Stop-Function -Message 'EncryptionCertifcate and EncryptionKey are mutually exclusive, only provide on of them'
                    return
                } else {
                    $encryptionOptions = New-Object Microsoft.SqlServer.Management.Smo.BackupEncryptionOptions
                    if (Test-Bound 'EncryptionCertificate') {
                        $tCertCheck = Get-DbaDbCertificate -SqlInstance $server -Database master -Certificate $EncryptionCertificate
                        if ($null -eq $tCertCheck) {
                            Stop-Function -Message "Certificate $EncryptionCertificate does not exist on $server so cannot be used for backups"
                            return
                        } else {
                            $encryptionOptions.encryptorType = [Microsoft.SqlServer.Management.Smo.BackupEncryptorType]::ServerCertificate
                            $encryptionOptions.encryptorName = $EncryptionCertificate
                            $encryptionOptions.Algorithm = [Microsoft.SqlServer.Management.Smo.BackupEncryptionAlgorithm]::$EncryptionAlgorithm
                        }
                    }
                    if (Test-Bound 'EncryptionKey') {
                        # Should not end up here until Key encryption in implemented
                        $tKeyCheck = Get-DbaDbAsymmetricKey -SqlInstance $server -Database master -Name $EncrytptionKey
                        if ($null -eq $tKeyCheck) {
                            Stop-Function -Message "AsymmetricKey $Encryptionkey does not exist on $server so cannot be used for backups"
                            return
                        } else {
                            $encryptionOptions.encryptorType = [Microsoft.SqlServer.Management.Smo.BackupEncryptorType]::ServerAsymmetricKey
                            $encryptionOptions.encryptorName = $EncryptionKey
                            $encryptionOptions.Algorithm = [Microsoft.SqlServer.Management.Smo.BackupEncryptionAlgorithm]::$EncryptionAlgorithm
                        }
                    }
                }
            }


            if ( (Test-Bound AzureBaseUrl -Not) -and (Test-Bound Path -Not) -and $FilePath -ne 'NUL') {
                Write-Message -Message 'No backup folder passed in, setting it to instance default' -Level Verbose
                $Path = (Get-DbaDefaultPath -SqlInstance $server).Backup
                if ($Path) {
                    # it's very picky, don't cut corners
                    $lastchar = $Path.substring($Path.length - 1, 1)
                    if ($lastchar -eq "/" -or $lastchar -eq "\") {
                        $Path = $Path.TrimEnd("/")
                        $Path = $Path.TrimEnd("\")
                    }
                }
            }

            if (($MaxTransferSize % 64kb) -ne 0 -or $MaxTransferSize -gt 4mb) {
                Stop-Function -Message "MaxTransferSize value must be a multiple of 64kb and no greater than 4MB"
                return
            }

            if ($BlockSize) {
                if ($BlockSize -notin (0.5kb, 1kb, 2kb, 4kb, 8kb, 16kb, 32kb, 64kb)) {

                    Stop-Function -Message "Block size must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb,64kb"
                    return
                }
            }

            if ($null -ne $AzureBaseUrl) {
                $AzureBaseUrl = $AzureBaseUrl.Trim("/")
                if ('' -ne $AzureCredential) {
                    Write-Message -Message "Azure Credential name passed in, will proceed assuming it's value" -Level Verbose
                    $FileCount = 1
                } else {
                    foreach ($baseUrl in $AzureBaseUrl) {
                        $base = $baseUrl -split "/"
                        if ( $base.Count -gt 4) {
                            Write-Message "AzureURL contains a folder"
                            $credentialName = $base[0] + "//" + $base[2] + "/" + $base[3]
                        }
                        Write-Message -Message "AzureUrl and no credential, testing for SAS credential"
                        if (Get-DbaCredential -SqlInstance $server -Name $credentialName) {
                            Write-Message -Message "Found a SAS backup credential" -Level Verbose
                        } else {
                            Stop-Function -Message "You must provide the credential name for the Azure Storage Account"
                            return
                        }
                    }
                }
                $FileCount = $AzureBaseUrl.count
                $Path = $AzureBaseUrl
            }

            if ($OutputScriptOnly) {
                $IgnoreFileChecks = $true
            }

            if ($null -eq $PSBoundParameters.Path -and $PSBoundParameters.FilePath -ne 'NUL' -and $server.VersionMajor -eq 8) {
                Write-Message -Message 'No backup folder passed in, setting it to instance default' -Level Verbose
                $Path = (Get-DbaDefaultPath -SqlInstance $server).Backup
            }

            if ($dbName -eq "tempdb") {
                Stop-Function -Message "Backing up tempdb not supported" -Continue
            }

            if ('Normal' -notin ($db.Status -split ',')) {
                Stop-Function -Message "Database status not Normal. $dbName skipped." -Continue
            }

            if ($db.DatabaseSnapshotBaseName) {
                Stop-Function -Message "Backing up snapshots not supported. $dbName skipped." -Continue
            }

            Write-Message -Level Verbose -Message "Backup database $db"

            if ($null -eq $db.RecoveryModel) {
                $db.RecoveryModel = $server.Databases[$db.Name].RecoveryModel
                Write-Message -Level Verbose -Message "$dbName is in $($db.RecoveryModel) recovery model"
            }

            # Fixes one-off cases of StackOverflowException crashes, see issue 1481
            $dbRecovery = $db.RecoveryModel.ToString()
            if ($dbRecovery -eq 'Simple' -and $Type -eq 'Log') {
                $failreason = "$db is in simple recovery mode, cannot take log backup"
                $failures += $failreason
                Write-Message -Level Warning -Message "$failreason"
            }

            $db.Refresh()
            $lastfull = $db.LastBackupDate.Year

            if ($Type -notin @("Database", "Full") -and $lastfull -eq 1) {
                $failreason = "$db does not have an existing full backup, cannot take log or differentialbackup"
                $failures += $failreason
                Write-Message -Level Warning -Message "$failreason"
            }

            if ($CopyOnly -ne $true) {
                $CopyOnly = $false
            }

            $server.ConnectionContext.StatementTimeout = 0
            $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
            $backup.Database = $db.Name
            $Suffix = "bak"

            if ($null -ne $encryptionOptions) {
                $backup.EncryptionOption = $encryptionOptions
            }

            if ($CompressBackup) {
                if ($db.EncryptionEnabled) {
                    # Newer versions of SQL Server automatically set the MAXTRANSFERSIZE to 128k
                    # so let's do that for people as well
                    $minVerForTDECompression = [version]'13.0.4446.0' #SQL Server 2016 CU 4
                    $flagTDESQLVersion = $minVerForTDECompression -le $Server.version
                    if (-not (Test-Bound 'MaxTransferSize')) {
                        $MaxTransferSize = 128kb
                    }
                    $flagCorrectMaxTransferSize = ($MaxTransferSize -gt 64kb)
                    if ($flagTDESQLVersion -and $flagCorrectMaxTransferSize) {
                        Write-Message -Level Verbose -Message "$dbName is enabled for encryption but will compress"
                        $backup.CompressionOption = 1
                    } else {
                        Write-Message -Level Warning -Message "$dbName is enabled for encryption, will not compress"
                        $backup.CompressionOption = 2
                    }
                } elseif ($server.Edition -like 'Express*' -or ($server.VersionMajor -eq 10 -and $server.VersionMinor -eq 0 -and $server.Edition -notlike '*enterprise*') -or $server.VersionMajor -lt 10) {
                    Write-Message -Level Warning -Message "Compression is not supported with this version/edition of Sql Server"
                } else {
                    Write-Message -Level Verbose -Message "Compression enabled"
                    $backup.CompressionOption = 1
                }
            }

            if ($Checksum) {
                $backup.Checksum = $true
            }

            if ($Type -in 'Diff', 'Differential') {
                Write-Message -Level VeryVerbose -Message "Creating differential backup"
                $SMOBackuptype = "Database"
                $backup.Incremental = $true
                $outputType = 'Differential'
                $gbhSwitch = @{'LastDiff' = $true }
            }
            $Backup.NoRecovery = $false
            if ($Type -eq "Log") {
                Write-Message -Level VeryVerbose -Message "Creating log backup"
                $Suffix = "trn"
                $OutputType = 'Log'
                $SMOBackupType = 'Log'
                $Backup.NoRecovery = $NoRecovery
                $gbhSwitch = @{'LastLog' = $true }
            }

            if ($Type -in 'Full', 'Database') {
                Write-Message -Level VeryVerbose -Message "Creating full backup"
                $SMOBackupType = "Database"
                $OutputType = 'Full'
                $gbhSwitch = @{'LastFull' = $true }
            }

            $backup.CopyOnly = $CopyOnly
            $backup.Action = $SMOBackupType
            if ($null -ne $AzureBaseUrl -and $null -ne $AzureCredential) {
                $backup.CredentialName = $AzureCredential
            }

            Write-Message -Level Verbose -Message "Building file name"
            $BackupFinalName = ''
            $FinalBackupPath = @()
            $timestamp = Get-Date -Format $TimeStampFormat
            if ('NUL' -eq $FilePath) {
                $FinalBackupPath += 'NUL:'
                $IgnoreFileChecks = $true
            } elseif ('' -ne $FilePath) {
                $File = New-Object System.IO.FileInfo($FilePath)
                $BackupFinalName = $file.Name
                $suffix = $file.extension -Replace '^\.', ''
                if ( '' -ne (Split-Path $FilePath)) {
                    Write-Message -Level Verbose -Message "Fully qualified path passed in"
                    # Because of #7860, don't use [IO.Path]::GetFullPath on MacOS
                    if ($nonwindows -or $isdestlinux) {
                        $FinalBackupPath += $file.DirectoryName
                    } else {
                        $FinalBackupPath += [IO.Path]::GetFullPath($file.DirectoryName)
                    }
                }
            } else {
                Write-Message -Level VeryVerbose -Message "Setting filename - $timestamp"
                $BackupFinalName = "$($dbName)_$timestamp.$suffix"
            }

            Write-Message -Level Verbose -Message "Building backup path"
            if ($FinalBackupPath.Count -eq 0) {
                $FinalBackupPath += $Path
            }

            if ($Path.Count -eq 1 -and $FileCount -gt 1) {
                for ($i = 0; $i -lt ($FileCount - 1); $i++) {
                    $FinalBackupPath += $FinalBackupPath[0]
                }
            }

            if ($AzureBaseUrl -or $AzureCredential -or $isdestlinux) {
                $slash = "/"
            } else {
                $slash = "\"
            }

            if ($FinalBackupPath.Count -gt 1) {
                $File = New-Object System.IO.FileInfo($BackupFinalName)
                for ($i = 0; $i -lt $FinalBackupPath.Count; $i++) {
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] + $slash + ("$($i+1)-" * $IncrementPrefix.ToBool() ) + $($File.BaseName) + "-$($i+1)-of-$FileCount.$suffix"
                }
            } elseif ($FinalBackupPath[0] -ne 'NUL:') {
                $FinalBackupPath[0] = $FinalBackupPath[0] + $slash + $BackupFinalName
            }

            if ($CreateFolder -and $FinalBackupPath[0] -ne 'NUL:') {
                for ($i = 0; $i -lt $FinalBackupPath.Count; $i++) {
                    $parent = [IO.Path]::GetDirectoryName($FinalBackupPath[$i])
                    $leaf = [IO.Path]::GetFileName($FinalBackupPath[$i])
                    $FinalBackupPath[$i] = [IO.Path]::Combine($parent, $dbName, $leaf)
                }
            }

            if ($True -eq $ReplaceInName) {
                for ($i = 0; $i -lt $FinalBackupPath.count; $i++) {
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('dbname', $dbName)
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('instancename', $server.ServiceName)
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('servername', $server.ComputerName)
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('timestamp', $timestamp)
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('backuptype', $outputType)
                }
            }

            # Linux can't support making new directories yet, and it's likely that databases
            # will be in one place
            if (-not $IgnoreFileChecks -and -not $AzureBaseUrl -and -not $isdestlinux) {
                $parentPaths = ($FinalBackupPath | ForEach-Object { Split-Path $_ } | Select-Object -Unique)
                foreach ($parentPath in $parentPaths) {
                    if (-not (Test-DbaPath -SqlInstance $server -Path $parentPath)) {
                        if (($BuildPath -eq $true) -or ($CreateFolder -eq $True)) {
                            $null = New-DbaDirectory -SqlInstance $server -Path $parentPath
                        } else {
                            $failreason += "SQL Server cannot check if $parentPath exists. You can try disabling this check with -IgnoreFileChecks"
                            $failures += $failreason
                            Write-Message -Level Warning -Message "$failreason"
                        }
                    }
                }
            }

            # Because of #7860, don't use [IO.Path]::GetFullPath on MacOS
            if ($null -eq $AzureBaseUrl -and $Path -and -not $nonwindows -and -not $isdestlinux) {
                $FinalBackupPath = $FinalBackupPath | ForEach-Object { [IO.Path]::GetFullPath($_) }
            }


            $script = $null
            $backupComplete = $false

            if (!$failures) {
                $FileCount = $FinalBackupPath.Count

                foreach ($backupfile in $FinalBackupPath) {
                    $device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                    if ($null -ne $AzureBaseUrl) {
                        $device.DeviceType = "URL"
                    } else {
                        $device.DeviceType = "File"
                    }

                    if ($WithFormat) {
                        Write-Message -Message "WithFormat specified. Ensuring Initialize and SkipTapeHeader are set to true." -Level Verbose
                        $Initialize = $true
                        $SkipTapeHeader = $true
                    }

                    $backup.FormatMedia = $WithFormat
                    $backup.Initialize = $Initialize
                    $backup.SkipTapeHeader = $SkipTapeHeader
                    $device.Name = $backupfile
                    $backup.Devices.Add($device)
                }
                $humanBackupFile = $FinalBackupPath -Join ','
                Write-Message -Level Verbose -Message "Devices added"
                $percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                    Write-Progress -Id $ProgressId -Activity "Backing up database $dbName to $humanBackupFile" -PercentComplete $_.Percent -Status ([System.String]::Format("Progress: {0} %", $_.Percent))
                }
                $backup.add_PercentComplete($percent)
                $backup.PercentCompleteNotification = 1
                $backup.add_Complete($complete)

                if ($MaxTransferSize) {
                    $backup.MaxTransferSize = $MaxTransferSize
                }
                if ($BufferCount) {
                    $backup.BufferCount = $BufferCount
                }
                if ($BlockSize) {
                    $backup.Blocksize = $BlockSize
                }

                Write-Progress -Id $ProgressId -Activity "Backing up database $dbName to $humanBackupFile" -PercentComplete 0 -Status ([System.String]::Format("Progress: {0} %", 0))

                try {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Backing up $dbName to $humanBackupFile")) {
                        if ($OutputScriptOnly -ne $True) {
                            $backup.SqlBackup($server)
                            $script = $backup.Script($server)
                            Write-Progress -Id $ProgressId -Activity "Backing up database $dbName to $backupfile" -Status "Complete" -Completed
                            $BackupComplete = $true
                            if ($server.VersionMajor -eq '8') {
                                $HeaderInfo = Get-BackupAncientHistory -SqlInstance $server -Database $dbName
                            } else {
                                $HeaderInfo = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbName @gbhSwitch -IncludeCopyOnly -RecoveryFork $db.RecoveryForkGuid | Sort-Object -Property End -Descending | Select-Object -First 1
                            }
                            $Filelist = @()
                            $FileList += $Headerinfo.FileList | Where-Object { $_.FileType -eq "D" } | Select-Object FileType, LogicalName , PhysicalName, @{ Name = "Type"; Expression = { "D" } }
                            $FileList += $Headerinfo.FileList | Where-Object { $_.FileType -eq "L" } | Select-Object FileType, LogicalName , PhysicalName, @{ Name = "Type"; Expression = { "L" } }

                            $Verified = $false
                            if ($Verify) {
                                $verifiedresult = [PSCustomObject]@{
                                    ComputerName         = $server.ComputerName
                                    InstanceName         = $server.ServiceName
                                    SqlInstance          = $server.DomainInstanceName
                                    DatabaseName         = $dbName
                                    BackupComplete       = $BackupComplete
                                    BackupFilesCount     = $FinalBackupPath.Count
                                    BackupFile           = (Split-Path $FinalBackupPath -Leaf)
                                    BackupFolder         = (Convert-BackupPath -object (Split-Path $FinalBackupPath | Sort-Object -Unique))
                                    BackupPath           = ($FinalBackupPath | Sort-Object -Unique)
                                    Script               = $script
                                    Notes                = $failures -join (',')
                                    FullName             = ($FinalBackupPath | Sort-Object -Unique)
                                    FileList             = $FileList
                                    SoftwareVersionMajor = $server.VersionMajor
                                    Type                 = $outputType
                                    FirstLsn             = $HeaderInfo.FirstLsn
                                    DatabaseBackupLsn    = $HeaderInfo.DatabaseBackupLsn
                                    CheckPointLsn        = $HeaderInfo.CheckPointLsn
                                    LastLsn              = $HeaderInfo.LastLsn
                                    BackupSetId          = $HeaderInfo.BackupSetId
                                    LastRecoveryForkGUID = $HeaderInfo.LastRecoveryForkGUID
                                    EncryptorName        = $encryptionOptions.EncryptorName
                                    KeyAlgorithm         = $encryptionOptions.Algorithm
                                    EncruptorType        = $encryptionOptions.encryptorType
                                } | Restore-DbaDatabase -SqlInstance $server -DatabaseName DbaVerifyOnly -VerifyOnly -TrustDbBackupHistory -DestinationFilePrefix DbaVerifyOnly
                                if ($verifiedResult[0] -eq "Verify successful") {
                                    $failures += $verifiedResult[0]
                                    $Verified = $true
                                } else {
                                    $failures += $verifiedResult[0]
                                    $Verified = $false
                                }
                            }
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupComplete -Value $BackupComplete
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupFile -Value (Split-Path $FinalBackupPath -Leaf)
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupFilesCount -Value $FinalBackupPath.Count
                            if ($FinalBackupPath[0] -eq 'NUL:') {
                                $pathresult = "NUL:"
                            } else {
                                $pathresult = (Split-Path $FinalBackupPath | Sort-Object -Unique)
                                if ($isdestlinux -and $pathresult) {
                                    $pathresult = $pathresult.Replace("\", "/")
                                } elseif ($pathresult) {
                                    $pathresult = $pathresult.Replace("/", "\")
                                }
                            }
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupFolder -Value $pathresult
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupPath -Value ($FinalBackupPath | Sort-Object -Unique)
                            $HeaderInfo | Add-Member -Type NoteProperty -Name DatabaseName -Value $dbName
                            $HeaderInfo | Add-Member -Type NoteProperty -Name DatabaseId -Value $db.ID
                            $HeaderInfo | Add-Member -Type NoteProperty -Name Notes -Value ($failures -join (','))
                            $HeaderInfo | Add-Member -Type NoteProperty -Name Script -Value $script
                            $HeaderInfo | Add-Member -Type NoteProperty -Name Verified -Value $Verified
                        } else {
                            $backup.Script($server)
                        }
                    }
                } catch {
                    if ($NoRecovery -and ($_.Exception.InnerException.InnerException.InnerException -like '*cannot be opened. It is in the middle of a restore.')) {
                        Write-Message -Message "Exception thrown by db going into restoring mode due to recovery" -Leve Verbose
                    } else {
                        Write-Progress -Id $ProgressId -Activity "Backup" -Status "Failed" -Completed
                        Stop-Function -message "Backup Failed" -ErrorRecord $_ -Continue
                        $BackupComplete = $false
                    }
                }
            }
            Write-Progress -Id $topProgressId -Activity 'Backup' -Completed

            $OutputExclude = 'FullName', 'FileList', 'SoftwareVersionMajor'

            if ($failures.Count -eq 0) {
                $OutputExclude += ('Notes', 'FirstLsn', 'DatabaseBackupLsn', 'CheckpointLsn', 'LastLsn', 'BackupSetId', 'LastRecoveryForkGuid')
            }

            $headerinfo | Select-DefaultView -ExcludeProperty $OutputExclude

            if (-not $ReplaceInName) {
                $FilePath = $null
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCLya+JfzBYcXCl
# acSxlz08dDwQZW5oTiOgC+Lwsm7RMKCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBwBxGmOTJGmVKwPLOx3OoItziHKsKaBwF1
# WQ7K6Ys3oDANBgkqhkiG9w0BAQEFAASCAQAkmQbbaTdrtGHrioMsj8e5JHk0u8fj
# daFrVnSrpY++nAv0boo3YTK6or6xVZs32iTlTLxBBnmh2zSgvFzHvKFltbZwMoDq
# MXhNbkRIYF27UHytbVSfrFBMJQ81XvRN+VENu5OzqdC1tyD9B3Mwu69MB4UlVpbC
# gKd9hd5BczIx9N2mUyt6InHvKso5sYUGzst8DR5Pk/mQ5KWgIWcCPCS1sK9LnOSt
# eZL+epIk4yHAQoSNP9Sv5b0QE811o7pGGQHNCiC+3BZ4PmkppzQmoiDi3H1/sO7e
# Y4FFWe8SY3jCsmdP6Bwd9ub0GJcuOPv5t+xZsff/LrngC+37P37gL+kcoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDIzM1owLwYJKoZIhvcNAQkEMSIEIH2jSFeD
# oNHRsx5xw6x9ptbvp9Vsr+sjARMSPmjFknJ+MA0GCSqGSIb3DQEBAQUABIICAKVi
# bh+UCyHN0Spcdi93bQm4tJG/ZBUojgNoseaVV8aqNpxn2iLdTwo3Ax7EoQ+jb3SA
# Byuy64Ru7ocV9rcvAFbli03y9LgQ5nTcfyQc1wu3SNPLGjRD8QmAYJ+azc81mb4O
# nnLl5+k+hWNRfIIBPACCrdThl/VZsF8av96q7uUCAt3/bgHWbIdwou92YPEdSapt
# 3uJgSZlbrXpqrbu7jTtInY3fAZIj/QvS4PzOmwDVVyr4KcMzKZwrxrmVm7s+cuy4
# BrE2HHLqDFd3nmOJeZCpFQNTkbRS8Y7Hn+7Cy6slzKf8q5jzhU3J87ILxirCTqhk
# zZr4MaJu7u+trz+yV/ZW406boD+pPIWPzM4LZFasxLGxhfnbDlCsFBxdWPoJ5g3F
# hznV2EmfrzWrzmaKyyZoNxy+7lQ1FACo4iaXRYMeNQniCwlnxIjlvYbMgOkebmY2
# lI/KZPSIRC56piT9Z9Oxe6UvPW0KoB2GEqxuImduXv4J9prd3JtdbekV5n5nz9ch
# Ix3Tm5xlSlzUwTCKejbn9mNDl8gpLtlqVhnvX+aX/vbv4k931nGTyY/G6z12pDq5
# 5gHq3DmKBRORae6Es88vSw6ABHeKvX04Qn5gYxfwXBIGT30v9wJ4yIX1RW8CkCXF
# G2NTT/TPK9H7WwYIfQSkJoLhi2i/JrbspFLfZPXi
# SIG # End signature block
