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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUZhgAD0YZ+sCceL4+rPfGXzpf
# s76gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFOKDevdqxqTkvnbDrJXCGcYH4pDnMA0G
# CSqGSIb3DQEBAQUABIIBAHpav1y9gumH3oZR2TQ3bxdKur5tDATt89XjFO9iHNOy
# B6UDXpVycITfdAnpSrON/uuRNCxM9POkmWqnK6LZGWgGMcm2IJOkGzj6z5IGkSkT
# o3aZXXVqzSV7Quo6GFqpICftlV1RYJwCxokEv2YEeo7hFk5UMeFV9X8aJprbNtVM
# Uzo5GFBQplBaN6mBoiSaPaoL/NHfk8JXDupFAzArhyf2FFrcxPfn0vzRFdHpPmHC
# T0T6Kv1Zw6C6IOMHwpw0SSdAGzSk5XCIgjTbpcPYhaQkt6rM+/qJC5X+wFtUsNCz
# hUYukSRrXwQnJvSg3eSELVfhCrU97oF4wJS5LA79jIGhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzA5WjAvBgkqhkiG9w0BCQQxIgQgsXD0INHfCxz+dsngCGVO
# MpafgiHvTm9dMVv4YUPIcY4wDQYJKoZIhvcNAQEBBQAEggIAQQCb13sGJ6a2xD7J
# DX41hjpAEmUZ+2av1TGiH9emPofSFc3Q2R/rKy8BSACtuoxFBFPKLc9u49GHhPrM
# kCybY9zUgiMxtJoYHmgw4oVPP09nYTRxu1HQt0HMXdEOJleAA98eUJS59DIenMDf
# qXS1s4eHhLIoUty8J+UgKL+gurbJWFsvtDrrT5k48jhoTeAKK+9dT8vC2f2ArDh+
# f75s1fNK82ryXAmbgveYM8weFt3Z6Z+P0ZL66g22or3YE6xyNXYyARUqnm47xtf7
# QTEzVoiJW/8EL6+oHPyjB4TmA571VHXcW1ZEmhe7d37ylbP4Ktd+dOo4SHIKzauz
# 3HDDzuGP7WMN6YhE0ri3Ol4dAPpv9TRblbDNv0eCfi33RqO30KRrxGRk2J3AV1dZ
# NYSe86Cm9uP9wwDsapabM5T6qfzFFhnlyeEN1zl+X1WJKsJBpqe1KZOLXH3onQdf
# u9TGKFKTiwnjFEbhHTM43hMmMogzOqf9HfV9J7c7YF7emVRko3Z3NlhtGv2vR0qJ
# ooPnS3jz+EA+uLY3Pu6ypZhEmokRKQXf2wR5lpJ86uROsrmNTqcKOiCr67rC7zii
# dGBu+wLHB8Y4pbuNlS9Y4uqM+77maho4sgGqWuGawicifLtoWtRBDVbEf7vTaw/k
# Kg8GKiFidQr8OPO8ywG+H/fTHA0=
# SIG # End signature block
