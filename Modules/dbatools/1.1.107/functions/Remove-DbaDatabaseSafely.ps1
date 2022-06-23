function Remove-DbaDatabaseSafely {
    <#
    .SYNOPSIS
        Safely removes a SQL Database and creates an Agent Job to restore it.

    .DESCRIPTION
        Performs a DBCC CHECKDB on the database, backs up the database with Checksum and verify only to a final (golden) backup location, creates an Agent Job to restore from that backup, drops the database, runs the agent job to restore the database, performs a DBCC CHECKDB and drops the database.

        With huge thanks to Grant Fritchey and his verify your backups video. Take a look, it's only 3 minutes long. http://sqlps.io/backuprant

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        If specified, Agent jobs will be created on this server. By default, the jobs will be created on the server specified by SqlInstance. You must have sysadmin access and the server must be SQL Server 2000 or higher. The SQL Agent service will be started if it is not already running.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more databases to remove.

    .PARAMETER NoDbccCheckDb
        If this switch is enabled, the initial DBCC CHECK DB will be skipped. This will make the process quicker but will also allow you to create an Agent job that restores a database backup containing a corrupt database.

        A second DBCC CHECKDB is performed on the restored database so you will still be notified BUT USE THIS WITH CARE.

    .PARAMETER BackupFolder
        Specifies the path to a folder where the final backups of the removed databases will be stored. If you are using separate source and destination servers, you must specify a UNC path such as  \\SERVER1\BACKUPSHARE\

    .PARAMETER JobOwner
        Specifies the name of the account which will own the Agent jobs. By default, sa is used.

    .PARAMETER UseDefaultFilePaths
        If this switch is enabled, the default file paths for the data and log files on the instance where the database is restored will be used. By default, the original file paths will be used.

    .PARAMETER CategoryName
        Specifies the Category Name for the Agent job that is created for restoring the database(s). By default, the name is "Rationalisation".

    .PARAMETER BackupCompression
        If this switch is enabled, compression will be used for the backup regardless of the SQL Server instance setting. By default, the SQL Server instance setting for backup compression is used.

    .PARAMETER AllDatabases
        If this switch is enabled, all user databases on the server will be removed. This is useful when decommissioning a server. You should use a Destination with this switch.

    .PARAMETER ReuseSourceFolderStructure
        If this switch is enabled, the source folder structure will be used when restoring instead of using the destination instance default folder structure.

    .PARAMETER Force
        If this switch is enabled, all actions will be performed even if DBCC errors are detected. An Agent job will be created with 'DBCCERROR' in the name and the backup file will have 'DBCC' in its name.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Delete
        Author: Rob Sewell (@SQLDBAWithBeard), sqldbawithabeard.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDatabaseSafely

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database RideTheLightning -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on database RideTheLightning on server Fade2Black. If there are no errors, the database is backup to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. Then, an Agent job to restore the database from that backup is created. The database is then dropped, the Agent job to restore it run, a DBCC CHECKDB run against the restored database, and then it is dropped again.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> $Database = 'DemoNCIndex','RemoveTestDatabase'
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database $Database -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on two databases, 'DemoNCIndex' and 'RemoveTestDatabase' on server Fade2Black. Then, an Agent job to restore each database from those backups is created. The databases are then dropped, the Agent jobs to restore them run, a DBCC CHECKDB run against the restored databases, and then they are dropped again.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Destination JusticeForAll -Database RideTheLightning -BackupFolder '\\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on database RideTheLightning on server Fade2Black. If there are no errors, the database is backup to the folder \\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE . Then, an Agent job is created on server JusticeForAll to restore the database from that backup is created. The database is then dropped on Fade2Black, the Agent job to restore it on JusticeForAll is run, a DBCC CHECKDB run against the restored database, and then it is dropped from JusticeForAll.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -Destination TheWildHearts -BackupFolder Z:\Backups -NoDbccCheckDb -JobOwner 'THEBEARD\Rob'

        For the databases $Database on the server IronMaiden a DBCC CHECKDB will not be performed before backing up the databases to the folder Z:\Backups. Then, an Agent job is created on server TheWildHearts with a Job Owner of THEBEARD\Rob to restore each database from that backup using the instance's default file paths. The database(s) is(are) then dropped on IronMaiden, the Agent job(s) run, a DBCC CHECKDB run on the restored database(s), and then the database(s) is(are) dropped.

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -Destination TheWildHearts -BackupFolder Z:\Backups

        The databases $Database on the server IronMaiden will be backed up the to the folder Z:\Backups. Then, an Agent job is created on server TheWildHearts with a Job Owner of THEBEARD\Rob to restore each database from that backup using the instance's default file paths. The database(s) is(are) then dropped on IronMaiden, the Agent job(s) run, a DBCC CHECKDB run on the restored database(s), and then the database(s) is(are) dropped.

        If there is a DBCC Error, the function  will continue to perform rest of the actions and will create an Agent job with 'DBCCERROR' in the name and a Backup file with 'DBCCError' in the name.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [DbaInstanceParameter]$Destination = $SqlInstance,
        [PSCredential]$DestinationSqlCredential,
        [Alias("NoCheck")]
        [switch]$NoDbccCheckDb,
        [parameter(Mandatory)]
        [string]$BackupFolder,
        [string]$CategoryName = 'Rationalisation',
        [string]$JobOwner,
        [switch]$AllDatabases,
        [ValidateSet("Default", "On", "Off")]
        [string]$BackupCompression = 'Default',
        [switch]$ReuseSourceFolderStructure,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if (!$AllDatabases -and !$Database) {
            Stop-Function -Message "You must specify at least one database. Use -Database or -AllDatabases." -ErrorRecord $_
            return
        }

        try {
            $sourceserver = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
        }

        if (-not $Destination) {
            $Destination = $SqlInstance
            $DestinationSqlCredential = $SqlCredential
        }

        if ($SqlInstance -ne $Destination) {

            try {
                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -Continue
            }

            $sourcenb = $sourceserver.ComputerName
            $destnb = $destserver.ComputerName

            if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcenb -ne $destnb) {
                Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -ErrorRecord $_ -Target $backupFolder
                return
            }
        } else {
            $destserver = $sourceserver
        }

        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName

        if (!$jobowner) {
            $jobowner = Get-SqlSaLogin -SqlInstance $destserver
        }

        if ($alldatabases -or !$Database) {
            $database = ($sourceserver.databases | Where-Object { $_.IsSystemObject -eq $false -and ($_.Status -match 'Offline') -eq $false }).Name
        }

        if (!(Test-DbaPath -SqlInstance $destserver -Path $backupFolder)) {
            $serviceAccount = $destserver.ServiceAccount
            Stop-Function -Message "Can't access $backupFolder Please check if $serviceAccount has permissions." -ErrorRecord $_ -Target $backupFolder
        }

        #TODO: Test
        $jobname = "Rationalised Final Database Restore for $dbName"
        $jobStepName = "Restore the $dbName database from Final Backup"

        if (!($destserver.Logins | Where-Object { $_.Name -eq $jobowner })) {
            Stop-Function -Message "$destination does not contain the login $jobowner - Please fix and try again - Aborting." -ErrorRecord $_ -Target $jobowner
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        $start = Get-Date

        try {
            $destInstanceName = $destserver.InstanceName

            if ($destserver.EngineEdition -match "Express") {
                Write-Message -Level Warning -Message "$destInstanceName is Express Edition which does not support SQL Server Agent."
                return
            }

            if ($destInstanceName -eq '') {
                $destInstanceName = "MSSQLSERVER"
            }
            $agentService = Get-DbaService -ComputerName $destserver.ComputerName -InstanceName $destInstanceName -Type Agent

            if ($agentService.State -ne 'Running') {
                Stop-Function -Message "SQL Server Agent is not running. Please start the service." -ErrorAction $agentService.Name
            } else {
                Write-Message -Level Verbose -Message "SQL Server Agent $($agentService.Name) is running."
            }
        } catch {
            Stop-Function -Message "Failure getting SQL Agent service" -ErrorRecord $_
            return
        }

        Write-Message -Level Verbose -Message "Starting Rationalisation Script at $start."

        foreach ($dbName in $Database) {

            $db = $sourceserver.databases[$dbName]

            # The db check is needed when the number of databases exceeds 255, then it's no longer auto-populated
            if (!$db) {
                Stop-Function -Message "$dbName does not exist on $source. Aborting routine for this database." -Continue
            }

            $lastFullBckDuration = ( Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -LastFull).Duration

            if (-NOT ([string]::IsNullOrEmpty($lastFullBckDuration))) {
                $lastFullBckDurationSec = $lastFullBckDuration.TotalSeconds
                $lastFullBckDurationMin = [Math]::Round($lastFullBckDuration.TotalMinutes, 2)

                Write-Message -Level Verbose -Message "From the backup history the last full backup took $lastFullBckDurationSec seconds ($lastFullBckDurationMin minutes)"
                if ($lastFullBckDurationSec -gt 600) {
                    Write-Message -Level Verbose -Message "Last full backup took more than 10 minutes. Do you want to continue?"

                    # Set up the parts for the user choice
                    $Title = "Backup duration"
                    $Info = "Last full backup took more than $lastFullBckDurationMin minutes. Do you want to continue?"

                    $Options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No (Skip)")
                    [int]$Defaultchoice = 0
                    $choice = $host.UI.PromptForChoice($Title, $Info, $Options, $Defaultchoice)
                    # Check the given option
                    if ($choice -eq 1) {
                        Stop-Function -Message "You have chosen skipping the database $dbName because of last known backup time ($lastFullBckDurationMin minutes)." -ErrorRecord $_ -Target $dbName -Continue
                        Continue
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Couldn't find last full backup time for database $dbName using Get-DbaDbBackupHistory."
            }

            $jobname = "Rationalised Database Restore Script for $dbName"
            $jobStepName = "Restore the $dbName database from Final Backup"
            $checkJob = Get-DbaAgentJob -SqlInstance $destserver -Job $jobname

            if ($checkJob.count -gt 0) {
                if ($Force -eq $false) {
                    Stop-Function -Message "FAILED: The Job $jobname already exists. Have you done this before? Rename the existing job and try again or use -Force to drop and recreate." -Continue
                } else {
                    if ($Pscmdlet.ShouldProcess($dbName, "Dropping $jobname on $destination")) {
                        Write-Message -Level Verbose -Message "Dropping $jobname on $destination."
                        $checkJob.Drop()
                    }
                }
            }


            Write-Message -Level Verbose -Message "Starting Rationalisation of $dbName."
            ## if we want to Dbcc before to abort if we have a corrupt database to start with
            if ($NoDbccCheckDb -eq $false) {
                if ($Pscmdlet.ShouldProcess($dbName, "Running dbcc check on $dbName on $source")) {
                    Write-Message -Level Verbose -Message "Starting DBCC CHECKDB for $dbName on $source."
                    $dbccgood = Start-DbccCheck -server $sourceserver -dbname $dbName -table

                    if ($dbccgood -ne "Success") {
                        if ($Force -eq $false) {
                            Write-Message -Level Verbose -Message "DBCC failed for $dbName (you should check that). Aborting routine for this database."
                            continue
                        } else {
                            Write-Message -Level Verbose -Message "DBCC failed, but Force specified. Continuing."
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($source, "Backing up $dbName")) {

                Write-Message -Level Verbose -Message "Starting Backup for $dbName on $source."
                ## Take a Backup
                try {
                    $timenow = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')

                    if ($Force -and $dbccgood -ne "Success") {
                        $filename = "$backupFolder\$($dbName)_DBCCERROR_$timenow.bak"
                    } else {
                        $filename = "$backupFolder\$($dbName)_Final_Before_Drop_$timenow.bak"
                    }

                    $DefaultCompression = $sourceserver.Configuration.DefaultBackupCompression.ConfigValue
                    $backupWithCompressionParams = @{
                        SqlInstance    = $SqlInstance
                        SqlCredential  = $SqlCredential
                        Database       = $dbName
                        BackupFileName = $filename
                        CompressBackup = $true
                        Checksum       = $true
                    }

                    $backupWithoutCompressionParams = @{
                        SqlInstance    = $SqlInstance
                        SqlCredential  = $SqlCredential
                        Database       = $dbName
                        BackupFileName = $filename
                        Checksum       = $true
                    }
                    if ($BackupCompression -eq "Default") {
                        if ($DefaultCompression -eq 1) {
                            $null = Backup-DbaDatabase @backupWithCompressionParams
                        } else {
                            $null = Backup-DbaDatabase @backupWithoutCompressionParams
                        }
                    } elseif ($BackupCompression -eq "On") {
                        $null = Backup-DbaDatabase @backupWithCompressionParams
                    } else {
                        $null = Backup-DbaDatabase @backupWithoutCompressionParams
                    }

                } catch {
                    Stop-Function -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database. Exception: $_" -Target $filename -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Creating Automated Restore Job from Golden Backup for $dbName on $destination")) {
                Write-Message -Level Verbose -Message "Creating Automated Restore Job from Golden Backup for $dbName on $destination."
                try {
                    if ($Force -eq $true -and $dbccgood -ne "Success") {
                        $jobName = $jobname -replace "Rationalised", "DBCC ERROR"
                    }

                    ## Create a Job Category
                    if (!(Get-DbaAgentJobCategory -SqlInstance $destination -SqlCredential $DestinationSqlCredential -Category $categoryname)) {
                        New-DbaAgentJobCategory -SqlInstance $destination -SqlCredential $DestinationSqlCredential -Category $categoryname
                    }

                    try {
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Agent Job $jobname on $destination")) {
                            $jobParams = @{
                                SqlInstance   = $destination
                                SqlCredential = $DestinationSqlCredential
                                Job           = $jobname
                                Category      = $categoryname
                                Description   = "This job will restore the $dbName database using the final backup located at $filename."
                                Owner         = $jobowner
                            }
                            $job = New-DbaAgentJob @jobParams

                            Write-Message -Level Verbose -Message "Created Agent Job $jobname on $destination."
                        }
                    } catch {
                        Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for this database." -Target $categoryname -ErrorRecord $_ -Continue
                    }

                    ## Create Job Step
                    ## Aaron's Suggestion: In the restore script, add a comment block that tells the last known size of each file in the database.
                    ## Suggestion check for disk space before restore
                    ## Create Restore Script
                    try {
                        $jobStepCommand = Restore-DbaDatabase -SqlInstance $destserver -Path $filename -OutputScriptOnly -WithReplace

                        $jobStepParams = @{
                            SqlInstance     = $destination
                            SqlCredential   = $DestinationSqlCredential
                            Job             = $job
                            StepName        = $jobStepName
                            SubSystem       = 'TransactSql'
                            Command         = $jobStepCommand
                            Database        = 'master'
                            OnSuccessAction = 'QuitWithSuccess'
                            OnFailAction    = 'QuitWithFailure'
                            StepId          = 1
                        }
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Agent JobStep on $destination")) {
                            $jobStep = New-DbaAgentJobStep @jobStepParams
                        }
                        $jobStartStepid = $jobStep.ID
                        Write-Message -Level Verbose -Message "Created Agent JobStep $jobStepName on $destination."
                    } catch {
                        Stop-Function -Message "FAILED : To Create Agent JobStep $jobStepName on $destination - Aborting." -Target $jobStepName -ErrorRecord $_ -Continue
                    }
                    if ($Pscmdlet.ShouldProcess($destination, "Applying Agent Job $jobname to $destination")) {
                        $job.StartStepID = $jobStartStepid
                        $job.Alter()
                    }
                } catch {
                    Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for $dbName. Exception: $_" -Target $jobname -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Dropping Database $dbName on $sourceserver")) {
                ## Drop the database
                try {
                    $null = Remove-DbaDatabase -SqlInstance $sourceserver -Database $dbName -Confirm:$false
                    Write-Message -Level Verbose -Message "Dropped $dbName Database on $source prior to running the Agent Job"
                } catch {
                    Stop-Function -Message "FAILED : To Drop database $dbName on $server - aborting routine for $dbName. Exception: $_" -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Running Agent Job on $destination to restore $dbName")) {
                ## Run the restore job to restore it
                Write-Message -Level Verbose -Message "Starting $jobname on $destination."
                try {
                    $job.Start()
                    $job.Refresh()
                    $status = $job.CurrentRunStatus

                    while ($status -ne 'Idle') {
                        Write-Message -Level Verbose -Message "Restore Job for $dbName on $destination is $status."
                        Start-Sleep -Seconds 15
                        $job.Refresh()
                        $status = $job.CurrentRunStatus
                    }

                    Write-Message -Level Verbose -Message "Restore Job $jobname has completed on $destination."
                    Write-Message -Level Verbose -Message "Sleeping for a few seconds to ensure the next step (DBCC) succeeds."
                    Start-Sleep -Seconds 10 ## This is required to ensure the next DBCC Check succeeds
                } catch {
                    Stop-Function -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbName. Exception: $_" -Continue
                }

                if ($job.LastRunOutcome -ne 'Succeeded') {
                    # LOL, love the plug.
                    Write-Message -Level Warning -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbName."
                    Write-Message -Level Warning -Message "Check the Agent Job History on $destination - if you have SSMS2016 July release or later."
                    Write-Message -Level Warning -Message "Get-DbaAgentJobHistory -SqlInstance $destination -Job '$jobname'."

                    continue
                }

                $refreshRetries = 1

                $destserver.Databases.Refresh()
                $restoredDatabase = Get-DbaDatabase -SqlInstance $destserver -Database $dbName
                while ($null -eq $restoredDatabase -and $refreshRetries -lt 6) {
                    Write-Message -Level verbose -Message "Database $dbName not found! Refreshing collection."

                    #refresh database list, otherwise the next step (DBCC) can fail
                    $restoredDatabase.Parent.Databases.Refresh()

                    Start-Sleep -Seconds 1

                    $refreshRetries += 1
                }
            }

            ## Run a Dbcc No choice here
            if ($Pscmdlet.ShouldProcess($dbName, "Running Dbcc CHECKDB on $dbName on $destination")) {
                Write-Message -Level Verbose -Message "Starting Dbcc CHECKDB for $dbName on $destination."
                $dbccgood = Start-DbccCheck -server $sourceserver -dbname $dbName -table

                if ($dbccgood -ne "Success") {
                    Write-Message -Level Verbose -Message "DBCC CHECKDB finished successfully for $dbName on $servername."
                } else {
                    Write-Message -Level Verbose -Message "DBCC failed for $dbName (you should check that). Continuing."
                }
            }

            if ($Pscmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
                ## Drop the database
                try {
                    $null = Remove-DbaDatabase -SqlInstance $destserver -Database $dbName -Confirm:$false
                    Write-Message -Level Verbose -Message "Dropped $dbName database on $destination."
                } catch {
                    Stop-Function -Message "FAILED : To Drop database $dbName on $destination - Aborting. Exception: $_" -Target $dbName -ErrorRecord $_ -Continue
                }
            }
            Write-Message -Level Verbose -Message "Rationalisation Finished for $dbName."

            [PSCustomObject]@{
                SqlInstance     = $source
                DatabaseName    = $dbName
                JobName         = $jobname
                TestingInstance = $destination
                BackupFolder    = $backupFolder
            }
        }
    }

    end {
        if (Test-FunctionInterrupt) {
            return
        }
        if ($Pscmdlet.ShouldProcess("console", "Showing final message")) {
            $End = Get-Date
            Write-Message -Level Verbose -Message "Finished at $End."
            $Duration = $End - $start
            Write-Message -Level Verbose -Message "Script Duration: $Duration."
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBf8g7YHC1N4lee
# TJnspu/3mUKnTvZFX1gIj7x0gtGMOqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCC4VbabFzlY03Cn7HEpjB2mvgU/dHd7x0rm
# 6S6vHcYPoDANBgkqhkiG9w0BAQEFAASCAQBg1Br++5589pTaIpPvnWY65EmHYVAQ
# ihp1R4z6IhP1RzLXBa8OQALrCkQvUDVp1gKEjC3J69oTUNLo8pdj4ppjwpyqm3bM
# Q8hI/rfouJ4iTs5gawQUhjpl0vRneVwccBN1qfL3w4Gu3SzCYoXbPEXgderN6Z13
# rvi+cjlA8HUABylZw92xvr63duJJuu+fpDL1qhBoHvudpHX+31o1t5uTzHW1DOZO
# 5VKL5bl5t/7BOhtIHRHIP9NInu8BpgO1noAC5YdCKtvH0Mvf9RJQ1yaFQkoWiYfJ
# RQDpPWhxDCG0GqqKOu1EmTeDW64r5GZlXIcwPeI5Tjc8cRqhiNsvjMHOoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDM0M1owLwYJKoZIhvcNAQkEMSIEIESR6tj4
# g47T5kHUDP6uaoS1HCkagMEPFQMx8ZkwcOT8MA0GCSqGSIb3DQEBAQUABIICAKrX
# /4wO5qlqyk9Fs7QmnZRpqQt+vNqiU3k5DLOVHPU9cBDpI/YHF8zkp8t6B3XKBHUR
# 67D0wWwKOB5HGA/VChI6VuZWMCrUOn/xTUdbPAiXzz08uRx05zp7XVnBzBVfKcR1
# tyhIG2jXJ0GM69ocBU/MiccodDeIA1WCYDjGk2IaQoOoiussyn+WEiwd0dzEOWgJ
# jRyPBsAIh8M069eECs+uh2OPkPIL+H799qlso6s6ReEHi06bmpCGj53roJIa4o0a
# HIGpYtbevg/e/e+gL6b+rhdFMgCa9Qc4N3IGrq4v7sCHgkEL82b+ThO/AEzT4Crm
# hMb5lRkiQaXv6DDro3OIYyRcEBmiORYzxlJjEKgUwrdEwEt7KXw+fqLQkYmd9MdR
# m4NGV6+R4rdCuj7ouZRWpha/m4Ts2kll79cxqaSHJws9ySDGEuqI/ovzs/LBhyEj
# 8RP9TE+QhfMyO7uM38Szxzhfkb9+Ls+vmCiTE+7tfLTWVdel93jqOFiSCzjG1mrt
# AYX+H+Z767Y+lrKFehqg59TY1siqoA1tnDldYcEHLOg3rYkYr4ptwAct3ZlqYgNE
# EN8J3aFzt2zk2Tqf6fS2f7toGKECULb2xdXfQ5C23Ispm/pVvBUPHTxNHv1kMz4T
# fcFzigDNJ762JRz5tTJZFPkDJUiYz3FrX2qR8M0M
# SIG # End signature block
