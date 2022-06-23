function Invoke-DbaAdvancedRestore {
    <#
    .SYNOPSIS
        Allows the restore of modified BackupHistory Objects
        For 90% of users Restore-DbaDatabase should be your point of access to this function. The other 10% use it at their own risk

    .DESCRIPTION
        This is the final piece in the Restore-DbaDatabase Stack. Usually a BackupHistory object will arrive here from `Restore-DbaDatabase` via the following pipeline:
        `Get-DbaBackupInformation  | Select-DbaBackupInformation | Format-DbaBackupInformation | Test-DbaBackupInformation | Invoke-DbaAdvancedRestore`

        We have exposed these functions publicly to allow advanced users to perform operations that we don't support, or won't add as they would make things too complex for the majority of our users

        For example if you wanted to do some very complex redirection during a migration, then doing the rewrite of destinations may be better done with your own custom scripts rather than via `Format-DbaBackupInformation`

        We would recommend ALWAYS pushing your input through `Test-DbaBackupInformation` just to make sure that it makes sense to us.

    .PARAMETER BackupHistory
        The BackupHistory object to be restored.
        Can be passed in on the pipeline

    .PARAMETER SqlInstance
        The SqlInstance to which the backups should be restored

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER OutputScriptOnly
        If set, the restore will not be performed, but the T-SQL scripts to perform it will be returned

    .PARAMETER VerifyOnly
        If set, performs a Verify of the backups rather than a full restore

    .PARAMETER RestoreTime
        Point in Time to which the database should be restored.

        This should be the same value or earlier, as used in the previous pipeline stages

    .PARAMETER StandbyDirectory
        A folder path where a standby file should be created to put the recovered databases in a standby mode

    .PARAMETER NoRecovery
        Leave the database in a restoring state so that further restore may be made

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple by 64kb

    .PARAMETER Blocksize
        Specifies the block size to use. Must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb or 64kb
        Can be specified in bytes
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER Continue
        Indicates that the restore is continuing a restore, so target database must be in Recovering or Standby states
        When specified, WithReplace will be set to true

    .PARAMETER AzureCredential
        AzureCredential required to connect to blob storage holding the backups

    .PARAMETER WithReplace
        Indicated that if the database already exists it should be replaced

    .PARAMETER KeepReplication
        Indicates whether replication configuration should be restored as part of the database restore operation

    .PARAMETER KeepCDC
        Indicates whether CDC information should be restored as part of the database

    .PARAMETER PageRestore
        The output from Get-DbaSuspect page containing the suspect pages to be restored.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER ExecuteAs
        If set, this will cause the database(s) to be restored (and therefore owned) as the SA user

    .PARAMETER StopMark
        Mark in the transaction log to stop the restore at

    .PARAMETER StopBefore
        Switch to indicate the restore should stop before StopMark

    .PARAMETER StopAfterDate
        By default the restore will stop at the first occurence of StopMark found in the chain, passing a datetime where will cause it to stop the first StopMark atfer that datetime

    .PARAMETER EnableException
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.

    .NOTES
        Tags: Restore, Backup
        Author: Stuart Moore (@napalmgram - http://stuart-moore.com)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaAdvancedRestore

    .EXAMPLE
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance

        Will restore all the backups in the BackupHistory object according to the transformations it contains

    .EXAMPLE
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance -OutputScriptOnly
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance

        First generates just the T-SQL restore scripts so they can be sanity checked, and then if they are good perform the full restore.
        By reusing the BackupHistory object there is no need to rescan all the backup files again

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "AzureCredential", Justification = "For Parameter AzureCredential")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Object[]]$BackupHistory,
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$OutputScriptOnly,
        [switch]$VerifyOnly,
        [datetime]$RestoreTime = (Get-Date).AddDays(2),
        [string]$StandbyDirectory,
        [switch]$NoRecovery,
        [int]$MaxTransferSize,
        [int]$BlockSize,
        [int]$BufferCount,
        [switch]$Continue,
        [string]$AzureCredential,
        [switch]$WithReplace,
        [switch]$KeepReplication,
        [switch]$KeepCDC,
        [object[]]$PageRestore,
        [string]$ExecuteAs,
        [switch]$StopBefore,
        [string]$StopMark,
        [datetime]$StopAfterDate,
        [switch]$EnableException
    )
    begin {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }
        if ($KeepCDC -and ($NoRecovery -or ('' -ne $StandbyDirectory))) {
            Stop-Function -Category InvalidArgument -Message "KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
            return
        }

        if ($null -ne $PageRestore) {
            Write-Message -Message "Doing Page Recovery" -Level Verbose
            $tmpPages = @()
            foreach ($Page in $PageRestore) {
                $tmpPages += "$($Page.FileId):$($Page.PageID)"
            }
            $NoRecovery = $True
            $Pages = $tmpPages -join ','
        }
        $internalHistory = @()
    }
    process {
        foreach ($bh in $BackupHistory) {
            $internalHistory += $bh
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        if ($Continue -eq $True) {
            $WithReplace = $True
        }
        $databases = $internalHistory.Database | Select-Object -Unique
        foreach ($database in $databases) {
            $databaseRestoreStartTime = Get-Date
            if ($database -in $server.Databases.Name) {
                if (-not $OutputScriptOnly -and -not $VerifyOnly -and $server.DatabaseEngineEdition -ne "SqlManagedInstance") {
                    if ($Pscmdlet.ShouldProcess("Killing processes in $database on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if processes exist, ", "Database Exists and WithReplace specified, need to kill processes to restore")) {
                        try {
                            Write-Message -Level Verbose -Message "Killing processes on $database"
                            $null = Stop-DbaProcess -SqlInstance $server -Database $database -WarningAction Silentlycontinue
                            $null = $server.Query("Alter database $database set offline with rollback immediate; alter database $database set restricted_user; Alter database $database set online with rollback immediate", 'master')
                            $server.ConnectionContext.Connect()
                        } catch {
                            Write-Message -Level Verbose -Message "No processes to kill in $database"
                        }
                    }
                } elseif (-not $OutputScriptOnly -and -not $VerifyOnly -and $server.DatabaseEngineEdition -eq "SqlManagedInstance") {
                    if ($Pscmdlet.ShouldProcess("Dropping $database on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if database exist, ", "Database Exists and WithReplace specified, need to drop database to restore")) {
                        try {
                            Write-Message -Level Verbose "$SqlInstance is a Managed instance so dropping database was WithReplace not supported"
                            $null = Stop-DbaProcess -SqlInstance $server -Database $database -WarningAction Silentlycontinue
                            $null = Remove-DbaDatabase -SqlInstance $server -Database $database -Confirm:$false
                            $server.ConnectionContext.Connect()
                        } catch {
                            Write-Message -Level Verbose -Message "No processes to kill in $database"
                        }
                    }

                } elseif (-not $WithReplace -and (-not $VerifyOnly)) {
                    Write-Message -Level verbose -Message "$database exists and WithReplace not specified, stopping"
                    continue
                }
            }
            Write-Message -Message "WithReplace  = $WithReplace" -Level Debug
            $backups = @($internalHistory | Where-Object { $_.Database -eq $database } | Sort-Object -Property Type, FirstLsn)
            $BackupCnt = 1

            foreach ($backup in $backups) {
                $fileRestoreStartTime = Get-Date
                $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
                if (($backup -ne $backups[-1]) -or $true -eq $NoRecovery) {
                    $restore.NoRecovery = $True
                } elseif ($backup -eq $backups[-1] -and '' -ne $StandbyDirectory) {
                    $restore.StandbyFile = $StandByDirectory + "\" + $database + (Get-Date -Format yyyyMMddHHmmss) + ".bak"
                    Write-Message -Level Verbose -Message "Setting standby on last file $($restore.StandbyFile)"
                } else {
                    $restore.NoRecovery = $False
                }
                if (-not [string]::IsNullOrEmpty($StopMark)) {
                    if ($StopBefore -eq $True) {
                        $restore.StopBeforeMarkName = $StopMark
                        if ($null -ne $StopAfterDate) {
                            $restore.StopBeforeMarkAfterDate = $StopAfterDate
                        }
                    } else {
                        $restore.StopAtMarkName = $StopMark
                        if ($null -ne $StopAfterDate) {
                            $restore.StopAtMarkAfterDate = $StopAfterDate
                        }
                    }
                } elseif ($RestoreTime -gt (Get-Date) -or $backup.RestoreTime -gt (Get-Date) -or $backup.RecoveryModel -eq 'Simple') {
                    $restore.ToPointInTime = $null
                } else {
                    if ($RestoreTime -ne $backup.RestoreTime) {
                        $restore.ToPointInTime = $backup.RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        $restore.ToPointInTime = $RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }

                $restore.Database = $database
                if ($server.DatabaseEngineEdition -ne "SqlManagedInstance") {
                    $restore.ReplaceDatabase = $WithReplace
                }
                if ($MaxTransferSize) {
                    $restore.MaxTransferSize = $MaxTransferSize
                }
                if ($BufferCount) {
                    $restore.BufferCount = $BufferCount
                }
                if ($BlockSize) {
                    $restore.Blocksize = $BlockSize
                }
                if ($KeepReplication) {
                    $restore.KeepReplication = $KeepReplication
                }
                if ($true -ne $Continue -and ($null -eq $Pages)) {
                    foreach ($file in $backup.FileList) {
                        $moveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
                        $moveFile.LogicalFileName = $file.LogicalName
                        $moveFile.PhysicalFileName = $file.PhysicalName
                        $null = $restore.RelocateFiles.Add($moveFile)
                    }
                }
                $action = switch ($backup.Type) {
                    '1' { 'Database' }
                    '2' { 'Log' }
                    '5' { 'Database' }
                    'Transaction Log' { 'Log' }
                    Default { 'Database' }
                }

                Write-Message -Level Debug -Message "restore action = $action"
                $restore.Action = $action
                foreach ($file in $backup.FullName) {
                    Write-Message -Message "Adding device $file" -Level Debug
                    $device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                    $device.Name = $file
                    if ($file.StartsWith("http")) {
                        $device.devicetype = "URL"
                    } else {
                        $device.devicetype = "File"
                    }

                    if ($AzureCredential) {
                        $restore.CredentialName = $AzureCredential
                    }

                    $restore.FileNumber = $backup.Position
                    $restore.Devices.Add($device)
                }
                Write-Message -Level Verbose -Message "Performing restore action"
                if ($Pscmdlet.ShouldProcess($SqlInstance, "Restoring $database to $SqlInstance based on these files: $($backup.FullName -join ', ')")) {
                    try {
                        $restoreComplete = $true
                        if ($KeepCDC -and $restore.NoRecovery -eq $false) {
                            $script = $restore.Script($server)
                            if ($script -like '*WITH*') {
                                $script = $script.TrimEnd() + ' , KEEP_CDC'
                            } else {
                                $script = $script.TrimEnd() + ' WITH KEEP_CDC'
                            }
                            if ($true -ne $OutputScriptOnly) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            }
                        } elseif ($null -ne $Pages -and $action -eq 'Database') {
                            $script = $restore.Script($server)
                            $script = $script -replace "] FROM", "] PAGE='$pages' FROM"
                            if ($true -ne $OutputScriptOnly) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            }
                        } elseif ($OutputScriptOnly) {
                            $script = $restore.Script($server)
                            if ($ExecuteAs -ne '' -and $BackupCnt -eq 1) {
                                $script = "EXECUTE AS LOGIN='$ExecuteAs'; " + $script
                            }
                        } elseif ($VerifyOnly) {
                            Write-Message -Message "VerifyOnly restore" -Level Verbose
                            Write-Progress -id 1 -activity "Verifying $database backup file on $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $Verify = $restore.SqlVerify($server)
                            Write-Progress -id 1 -activity "Verifying $database backup file on $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            if ($verify -eq $true) {
                                Write-Message -Message "VerifyOnly restore Succeeded" -Level Verbose
                                return "Verify successful"
                            } else {
                                Write-Message -Message "VerifyOnly restore Failed" -Level Verbose
                                return "Verify failed"
                            }
                        } else {
                            $outerProgress = $BackupCnt / $Backups.Count * 100
                            if ($BackupCnt -eq 1) {
                                Write-Progress -id 1 -Activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0
                            }
                            Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -percentcomplete 0
                            $script = $restore.Script($server)
                            if ($ExecuteAs -ne '' -and $BackupCnt -eq 1) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $script = "EXECUTE AS LOGIN='$ExecuteAs'; " + $script
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            } else {
                                $percentcomplete = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                                    Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                                }
                                $restore.add_PercentComplete($percentcomplete)
                                $restore.PercentCompleteNotification = 1
                                $restore.SqlRestore($server)
                                Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -Completed
                                Add-TeppCacheItem -SqlInstance $server -Type database -Name $database
                            }
                            Write-Progress -id 1 -Activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete $outerProgress -status ([System.String]::Format("Progress: {0:N2} %", $outerProgress))
                        }
                    } catch {
                        Write-Message -Level Verbose -Message "Failed, Closing Server connection"
                        $restoreComplete = $False
                        $ExitError = $_.Exception.InnerException
                        Stop-Function -Message "Failed to restore db $database, stopping" -ErrorRecord $_ -Continue
                        break
                    } finally {
                        if ($OutputScriptOnly -eq $false) {
                            $pathSep = Get-DbaPathSep -Server $server
                            $RestoreDirectory = ((Split-Path $backup.FileList.PhysicalName -Parent) | Sort-Object -Unique).Replace('\', $pathSep) -Join ','
                            [PSCustomObject]@{
                                ComputerName           = $server.ComputerName
                                InstanceName           = $server.ServiceName
                                SqlInstance            = $server.DomainInstanceName
                                Database               = $backup.Database
                                DatabaseName           = $backup.Database
                                DatabaseOwner          = $server.ConnectionContext.TrueLogin
                                Owner                  = $server.ConnectionContext.TrueLogin
                                NoRecovery             = $restore.NoRecovery
                                WithReplace            = $WithReplace
                                KeepReplication        = $KeepReplication
                                RestoreComplete        = $restoreComplete
                                BackupFilesCount       = $backup.FullName.Count
                                RestoredFilesCount     = $backup.Filelist.PhysicalName.count
                                BackupSizeMB           = if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) { [Math]::Round(($backup | Measure-Object -Property TotalSize -Sum).Sum / $backup.FullName.Count / 1mb, 2) } else { $null }
                                CompressedBackupSizeMB = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { [Math]::Round(($backup | Measure-Object -Property CompressedBackupSize -Sum).Sum / $backup.FullName.Count / 1mb, 2) } else { $null }
                                BackupFile             = $backup.FullName -Join ','
                                RestoredFile           = $((Split-Path $backup.FileList.PhysicalName -Leaf) | Sort-Object -Unique) -Join ','
                                RestoredFileFull       = ($backup.Filelist.PhysicalName -Join ',')
                                RestoreDirectory       = $RestoreDirectory
                                BackupSize             = if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) { [dbasize](($backup | Measure-Object -Property TotalSize -Sum).Sum / $backup.FullName.Count) } else { $null }
                                CompressedBackupSize   = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { [dbasize](($backup | Measure-Object -Property CompressedBackupSize -Sum).Sum / $backup.FullName.Count) } else { $null }
                                BackupStartTime        = $backup.Start
                                BackupEndTime          = $backup.End
                                RestoreTargetTime      = if ($RestoreTime -lt (Get-Date)) { $RestoreTime } else { 'Latest' }
                                Script                 = $script
                                BackupFileRaw          = ($backups.Fullname)
                                FileRestoreTime        = New-TimeSpan -Seconds ((Get-Date) - $fileRestoreStartTime).TotalSeconds
                                DatabaseRestoreTime    = New-TimeSpan -Seconds ((Get-Date) - $databaseRestoreStartTime).TotalSeconds
                                ExitError              = $ExitError
                            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, BackupFile, BackupFilesCount, BackupSize, CompressedBackupSize, Database, Owner, DatabaseRestoreTime, FileRestoreTime, NoRecovery, RestoreComplete, RestoredFile, RestoredFilesCount, Script, RestoreDirectory, WithReplace
                        } else {
                            $script
                        }
                        if ($restore.Devices.Count -gt 0) {
                            $restore.Devices.Clear()
                        }
                        Write-Message -Level Verbose -Message "Succeeded, Closing Server connection"
                        $server.ConnectionContext.Disconnect()
                    }
                }
                $BackupCnt++
            }
            Write-Progress -id 2 -Activity "Finished" -Completed
            if ($server.ConnectionContext.exists) {
                $server.ConnectionContext.Disconnect()
            }
            Write-Progress -id 1 -Activity "Finished" -Completed
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU+2FoRfwJUUwy5ViRatrfVIm1
# evOgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFLvdsjAtJVw/C6abDS+5bKi3k1zQMA0G
# CSqGSIb3DQEBAQUABIIBAI4yjAYyB3HD5ssPevMYpbsWKrPrVsRARcltw3nP9bep
# Ka/fTecaclJZ9jyLivLEo0HqQwHOD9tjM/xKNO+r05uSttDKUU6HCrEawe8MpTYo
# 79CNOiq7ycZFQ+cxJjrAUJFNRZSR/yJhZSK0GFbEi22rBxNsieP9wrkZ4kipkkD0
# KAbZQ+/5/oiXIIIFaWmKzl/Elmd5tWbaJo4DkMj+eKvDUFAXNdL0vXeSlPBgQn/R
# VrTmt0mem3JJip0y2IEq/Ks20qZa8D+sWD0S+wIJrlDzb97CdxsyxAATuI+45RCW
# bsAf03X8IrryTZrO/i0WSZCBOYcTIgZsk+sBRY7twhuhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU0WjAvBgkqhkiG9w0BCQQxIgQg7ev8mbffPvdNH9J4X6xD
# Td6DLV+uYSN8lxLNdM9aVjgwDQYJKoZIhvcNAQEBBQAEggIAOxc01E5prCy3RsoM
# 1SaZLWwmE5IMhzB+in1AAACTePEgh1v2qjKksWtLuxtWw00lHLKACsKEkm+Bcfdw
# pjt0CSOy2pzYHLl3X0QPp+cK3+1k3TBI/x5pNPtaeTOdHEe6c1EivB1mG85QZC5s
# Ou8t1VcY3WyeSxra2QnwBD6OmX5hEOV4Bw+wjbpMAcYT08Ty2scqbRHRk0ugU2e7
# KCWDyNmpDy7x4S7iWcSv+g4VBHWSMRDYZbWcKgkFyaypveWaPyTtmAK4P7bvVo64
# qfW/wTYp4PznibgDi4ZWJxABTOk6HutF4TP/p7FGimvWM91B5BZoiCzraYjzsrzu
# sfNum7PWIi59TO3lYXhkoNNnNLnia5zxKBGf8d4HhgT5d7zATam4V2I3uNOInFYc
# pg4dirHoGi6acIu/Y0na3d0DOv6ehLMRFq2/PbQSKKrMyBk5WU6nKcwVsL0Zl0NM
# StMRQceXfYimRClnujetV7EUiLdzl9QLOOFTUu80j7cphZzePZnQP/fqhCG6nfsI
# ++5EGvhwMPvc5eYcDpjs2M983TlefREk62gzNgDm6IDcfY8qm7b/TGkMVRwZm7g+
# tb8IzdgxAvmWV6dhEURGFfPqpVzJPyhKDSd8FcIk3gdbuy+si9jKioUFu/qawwUr
# rkosNelvKQXgUSAW8skXnrLDVwc=
# SIG # End signature block
