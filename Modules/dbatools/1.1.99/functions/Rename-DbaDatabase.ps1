function Rename-DbaDatabase {
    <#
    .SYNOPSIS
        Changes database name, logical file names, file group names and physical file names (optionally handling the move). BETA VERSION.

    .DESCRIPTION
        Can change every database metadata that can be renamed.
        The ultimate goal is choosing to have a default template to enforce in your environment
        so your naming convention for every bit can be put in place in no time.
        The process is as follows (it follows the hierarchy of the entities):
        - database name is changed (optionally, forcing users out)
        - filegroup name(s) are changed accordingly
        - logical name(s) are changed accordingly
        - physical file(s) are changed accordingly
        - if Move is specified, the database will be taken offline and the move will initiate, then it will be taken online
        - if Move is not specified, the database remains online (unless SetOffline), and you are in charge of moving files
        If any of the above fails, the process stops.
        Please take a backup of your databases BEFORE using this, and remember to backup AFTER (also a FULL backup of master)

        It returns an object for each database with all the renames done, plus hidden properties showing a "human" representation of them.

        It's better you store the resulting object in a variable so you can inspect it in case of issues, e.g. "$result = Rename-DbaDatabase ....."

        To get a grasp without worrying of what would happen under the hood, use "Rename-DbaDatabase .... -Preview | Select-Object *"

    .PARAMETER SqlInstance
        Target any number of instances, in order to return their build state.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Targets only specified databases

    .PARAMETER ExcludeDatabase
        Excludes only specified databases

    .PARAMETER AllDatabases
        If you want to apply the naming convention system wide, you need to pass this parameter

    .PARAMETER DatabaseName
        Pass a template to rename the database name. Valid placeholders are:
        - <DBN> current database name
        - <DATE> date (yyyyMMdd)

    .PARAMETER FileGroupName
        Pass a template to rename file group name. Valid placeholders are:
        - <FGN> current filegroup name
        - <DBN> current database name
        - <DATE> date (yyyyMMdd)
        If distinct names cannot be generated, a counter will be appended (0001, 0002, 0003, etc)

    .PARAMETER LogicalName
        Pass a template to rename logical name. Valid placeholders are:
        - <FT> file type (ROWS, LOG)
        - <LGN> current logical name
        - <FGN> current filegroup name
        - <DBN> current database name
        - <DATE> date (yyyyMMdd)
        If distinct names cannot be generated, a counter will be appended (0001, 0002, 0003, etc)

    .PARAMETER FileName
        Pass a template to rename file name. Valid placeholders are:
        - <FNN> current file name (the basename, without directory nor extension)
        - <FT> file type (ROWS, LOG, MMO, FS)
        - <LGN> current logical name
        - <FGN> current filegroup name
        - <DBN> current database name
        - <DATE> date (yyyyMMdd)
        If distinct names cannot be generated, a counter will be appended (0001, 0002, 0003, etc)

    .PARAMETER ReplaceBefore
        If you pass this switch, all upper level "current names" will be inspected and replaced BEFORE doing the
        rename according to the template in the current level (remember the hierarchy):
        Let's say you have a database named "dbatools_HR", composed by 3 files
        - dbatools_HR_Data.mdf
        - dbatools_HR_Index.ndf
        - dbatools_HR_log.ldf
        Rename-DbaDatabase .... -Database "dbatools_HR" -DatabaseName "dbatools_HRARCHIVE" -FileName '<DBN><FNN>'
        would end up with this logic:
        - database --> no placeholders specified
        - dbatools_HR to dbatools_HRARCHIVE
        - filenames placeholders specified
        <DBN><FNN> --> current database name + current filename"
        - dbatools_HR_Data.mdf to dbatools_HRARCHIVEdbatools_HR_Data.mdf
        - dbatools_HR_Index.mdf to dbatools_HRARCHIVEdbatools_HR_Data.mdf
        - dbatools_HR_log.ldf to dbatools_HRARCHIVEdbatools_HR_log.ldf
        Passing this switch, instead, e.g.
        Rename-DbaDatabase .... -Database "dbatools_HR" -DatabaseName "dbatools_HRARCHIVE" -FileName '<DBN><FNN>' -ReplaceBefore
        end up with this logic instead:
        - database --> no placeholders specified
        - dbatools_HR to dbatools_HRARCHIVE
        - filenames placeholders specified,
        <DBN><FNN>, plus -ReplaceBefore --> current database name + replace OLD "upper level" names inside the current filename
        - dbatools_HR_Data.mdf to dbatools_HRARCHIVE_Data.mdf
        - dbatools_HR_Index.mdf to dbatools_HRARCHIVE_Data.mdf
        - dbatools_HR_log.ldf to dbatools_HRARCHIVE_log.ldf

    .PARAMETER Force
        Kills any open session to be able to do renames.

    .PARAMETER SetOffline
        Kills any open session and sets the database offline to be able to move files

    .PARAMETER Move
        If you want this function to move files, else you're the one in charge of it.
        This enables the same functionality as SetOffline, killing open transactions and putting the database
        offline, then do the actual rename and setting it online again afterwards

    .PARAMETER Preview
        Shows the renames without performing any operation (recommended to find your way around this function parameters ;-) )

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER InputObject
        Accepts piped database objects

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Rename
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Rename-DbaDatabase

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName HR2 -Preview | Select-Object *

        Shows the detailed result set you'll get renaming the HR database to HR2 without doing anything

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName HR2

        Renames the HR database to HR2

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2014a -Database HR | Rename-DbaDatabase -DatabaseName HR2

        Same as before, but with a piped database (renames the HR database to HR2)

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>"

        Renames the HR database to dbatools_HR

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>_<DATE>"

        Renames the HR database to dbatools_HR_20170807 (if today is 07th Aug 2017)

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -FileGroupName "dbatools_<FGN>"

        Renames every FileGroup within HR to "dbatools_[the original FileGroup name]"

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>" -FileGroupName "<DBN>_<FGN>"

        Renames the HR database to "dbatools_HR", then renames every FileGroup within to "dbatools_HR_[the original FileGroup name]"

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -FileGroupName "dbatools_<DBN>_<FGN>"
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>"

        Renames the HR database to "dbatools_HR", then renames every FileGroup within to "dbatools_HR_[the original FileGroup name]"

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>" -FileName "<DBN>_<FGN>_<FNN>"

        Renames the HR database to "dbatools_HR" and then all filenames as "dbatools_HR_[Name of the FileGroup]_[original_filename]"
        The db stays online (watch out!). You can then proceed manually to move/copy files by hand, set the db offline and then online again to finish the rename process

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>" -FileName "<DBN>_<FGN>_<FNN>" -SetOffline

        Renames the HR database to "dbatools_HR" and then all filenames as "dbatools_HR_[Name of the FileGroup]_[original_filename]"
        The db is then set offline (watch out!). You can then proceed manually to move/copy files by hand and then set it online again to finish the rename process

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>" -FileName "<DBN>_<FGN>_<FNN>" -Move

        Renames the HR database to "dbatools_HR" and then all filenames as "dbatools_HR_[Name of the FileGroup]_[original_filename]"
        The db is then set offline (watch out!). The function tries to do a simple rename and then sets the db online again to finish the rename process

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ParameterSetName = "Server")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [parameter(ParameterSetName = "Server")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [string]$DatabaseName,
        [string]$FileGroupName,
        [string]$LogicalName,
        [string]$FileName,
        [switch]$ReplaceBefore,
        [switch]$Force,
        [switch]$Move,
        [switch]$SetOffline,
        [switch]$Preview,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Pipe")]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $CurrentDate = Get-Date -Format 'yyyyMMdd'

        function Get-DbaNameStructure($database) {
            $obj = @()
            # db name
            $obj += "- Database : $database"
            # FileGroups
            foreach ($fg in $database.FileGroups) {
                $obj += "  - FileGroup: $($fg.Name)"
                # LogicalNames
                foreach ($ln in $fg.Files) {
                    $obj += "    - Logical: $($ln.Name)"
                    $obj += "      - FileName: $($ln.FileName)"
                }
            }
            $obj += "  - Logfiles"
            foreach ($log in $database.LogFiles) {
                $obj += "    - Logical: $($log.Name)"
                $obj += "      - FileName: $($log.FileName)"
            }
            return $obj -Join "`n"
        }


        function Get-DbaKeyByValue($hashtable, $Value) {
            ($hashtable.GetEnumerator() | Where-Object Value -eq $Value).Name
        }

        if ((Test-Bound -ParameterName SetOffline) -and (-not(Test-Bound -ParameterName FileName))) {
            Stop-Function -Category InvalidArgument -Message "-SetOffline is only useful when -FileName is passed. Quitting."
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if (!$Database -and !$AllDatabases -and !$InputObject -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database/ExcludeDatabase to continue"
            return
        }
        if (!$DatabaseName -and !$FileGroupName -and !$LogicalName -and !$FileName) {
            Stop-Function -Message "You must specify at least one of -DatabaseName,-FileGroupName,-LogicalName or -Filename to continue"
            return
        }
        $dbs = @()
        if ($InputObject) {
            if ($InputObject.Name) {
                # comes from Get-DbaDatabase
                $dbs += $InputObject
            }
        } else {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $sqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                $all_dbs = $server.Databases | Where-Object IsAccessible
                $dbs += $all_dbs | Where-Object { @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name }
                if ($Database) {
                    $dbs = $dbs | Where-Object { $Database -contains $_.Name }
                }
                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
                }
            }
        }

        # holds all dbs per instance to avoid naming clashes
        $InstanceDbs = @{ }

        # holds all db file enumerations (used for -Move only)
        $InstanceFiles = @{ }

        #region db loop
        foreach ($db in $dbs) {
            # used to stop futher operations on database
            $failed = $false

            # pending renames initialized at db level
            $Pending_Renames = @()

            $Entities_Before = @{ }

            $server = $db.Parent
            if ($db.Name -in @('master', 'model', 'msdb', 'tempdb', 'distribution')) {
                Write-Message -Level Warning -Message "Database $($db.Name) is a system one, skipping..."
                continue
            }
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $($db.Name) is not accessible, skipping..."
                continue
            }
            if ($db.IsMirroringEnabled -eq $true -or $db.AvailabilityGroupName.Length -gt 0) {
                Write-Message -Level Warning -Message "Database $($db.Name) is either mirrored or in an AG, skipping..."
                continue
            }
            $Server_Id = $server.DomainInstanceName
            if ( !$InstanceDbs.ContainsKey($Server_Id) ) {
                $InstanceDbs[$Server_Id] = @{ }
                foreach ($dn in $server.Databases.Name) {
                    $InstanceDbs[$Server_Id][$dn] = 1
                }
            }

            $Entities_Before['DBN'] = @{ }
            $Entities_Before['FGN'] = @{ }
            $Entities_Before['LGN'] = @{ }
            $Entities_Before['FNN'] = @{ }
            $Entities_Before['DBN'][$db.Name] = $db.Name
            #region databasename
            if ($DatabaseName) {
                $Orig_DBName = $db.Name
                # fixed replacements
                $NewDBName = $DatabaseName.Replace('<DBN>', $Orig_DBName).Replace('<DATE>', $CurrentDate)
                if ($Orig_DBName -eq $NewDBName) {
                    Write-Message -Level VeryVerbose -Message "Database name unchanged, skipping"
                } else {
                    if ($InstanceDbs[$Server_Id].ContainsKey($NewDBName)) {
                        Write-Message -Level Warning -Message "Database $NewDBName exists already, skipping this rename"
                        $failed = $true
                    } else {
                        if ($PSCmdlet.ShouldProcess($db, "Renaming Database $db to $NewDBName")) {
                            if ($Force) {
                                $server.KillAllProcesses($Orig_DBName)
                            }
                            try {
                                if (!$Preview) {
                                    $db.Rename($NewDBName)
                                }
                                $InstanceDbs[$Server_Id].Remove($Orig_DBName)
                                $InstanceDbs[$Server_Id][$NewDBName] = 1
                                $Entities_Before['DBN'][$Orig_DBName] = $NewDBName
                                #$db.Refresh()
                            } catch {
                                Stop-Function -Message "Failed to rename Database : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                # stop any further renames
                                $failed = $true
                            }
                        }
                    }
                }
            }
            #endregion databasename
            #region filegroupname
            if ($ReplaceBefore) {
                #backfill PRIMARY
                $Entities_Before['FGN']['PRIMARY'] = 'PRIMARY'
                foreach ($fg in $db.FileGroups.Name) {
                    $Entities_Before['FGN'][$fg] = $fg
                }
            }

            if (!$failed -and $FileGroupName) {
                $Editable_FGs = $db.FileGroups | Where-Object Name -ne 'PRIMARY'
                $New_FGNames = @{ }
                foreach ($fg in $db.FileGroups.Name) {
                    $New_FGNames[$fg] = 1
                }
                $FGCounter = 0
                foreach ($fg in $Editable_FGs) {
                    $Orig_FGName = $fg.Name
                    $Orig_Placeholder = $Orig_FGName
                    if ($ReplaceBefore) {
                        # at Filegroup level, we need to worry about database name
                        $Orig_Placeholder = $Orig_Placeholder.Replace($Entities_Before['DBN'][$Orig_DBName], '')
                    }
                    $NewFGName = $FileGroupName.Replace('<DBN>', $Entities_Before['DBN'][$db.Name]).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $Orig_Placeholder)
                    $FinalFGName = $NewFGName
                    while ($fg.Name -ne $FinalFGName) {
                        if ($FinalFGName -in $New_FGNames.Keys) {
                            $FGCounter += 1
                            $FinalFGName = "$NewFGName$($FGCounter.ToString('000'))"
                        } else {
                            break
                        }
                    }
                    if ($fg.Name -eq $FinalFGName) {
                        Write-Message -Level VeryVerbose -Message "No rename necessary for FileGroup $($fg.Name) (on $db)"
                        continue
                    }
                    if ($PSCmdlet.ShouldProcess($db, "Renaming FileGroup $($fg.Name) to $FinalFGName")) {
                        try {
                            if (!$Preview) {
                                $fg.Rename($FinalFGName)
                            }
                            $New_FGNames.Remove($Orig_FGName)
                            $New_FGNames[$FinalFGName] = 1
                            $Entities_Before['FGN'][$Orig_FGName] = $FinalFGName
                        } catch {
                            Stop-Function -Message "Failed to rename FileGroup : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                            # stop any further renames
                            $failed = $true
                            break
                        }
                    }
                }
                #$db.FileGroups.Refresh()
            }

            #endregion filegroupname
            #region logicalname
            if ($ReplaceBefore) {
                foreach ($fn in $db.FileGroups.Files.Name) {
                    $Entities_Before['LGN'][$fn] = $fn
                }
                foreach ($fn in $db.Logfiles.Name) {
                    $Entities_Before['LGN'][$fn] = $fn
                }
            }
            if (!$failed -and $LogicalName) {
                $New_LogicalNames = @{ }
                foreach ($fn in $db.FileGroups.Files.Name) {
                    $New_LogicalNames[$fn] = 1
                }
                foreach ($fn in $db.Logfiles.Name) {
                    $New_LogicalNames[$fn] = 1
                }
                $LNCounter = 0
                foreach ($fg in $db.FileGroups) {
                    $logicalfiles = @($fg.Files)
                    for ($i = 0; $i -lt $logicalfiles.Count; $i++) {
                        $logical = $logicalfiles[$i]
                        $FileType = switch ($fg.FileGroupType) {
                            'RowsFileGroup' { 'ROWS' }
                            'MemoryOptimizedDataFileGroup' { 'MMO' }
                            'FileStreamDataFileGroup' { 'FS' }
                            default { 'STD' }
                        }
                        $Orig_LGName = $logical.Name
                        $Orig_Placeholder = $Orig_LGName
                        if ($ReplaceBefore) {
                            # at Logical Name level, we need to worry about database name and filegroup name
                            $Orig_Placeholder = $Orig_Placeholder.Replace((Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name), '').Replace(
                                (Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name), '')
                        }
                        $NewLGName = $LogicalName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $fg.Name).Replace(
                            '<FT>', $FileType).Replace('<LGN>', $Orig_Placeholder)
                        $FinalLGName = $NewLGName
                        while ($logical.Name -ne $FinalLGName) {
                            if ($FinalLGName -in $New_LogicalNames.Keys) {
                                $LNCounter += 1
                                $FinalLGName = "$NewLGName$($LNCounter.ToString('000'))"
                            } else {
                                break
                            }
                        }
                        if ($logical.Name -eq $FinalLGName) {
                            Write-Message -Level VeryVerbose -Message "No rename necessary for LogicalFile $($logical.Name) (on FileGroup $($fg.Name) (on $db))"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming LogicalFile $($logical.Name) to $FinalLGName (on FileGroup $($fg.Name))")) {
                            try {
                                if (!$Preview) {
                                    $logical.Rename($FinalLGName)
                                }
                                $New_LogicalNames.Remove($Orig_LGName)
                                $New_LogicalNames[$FinalLGName] = 1
                                $Entities_Before['LGN'][$Orig_LGName] = $FinalLGName
                            } catch {
                                Stop-Function -Message "Failed to Rename Logical File : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                }
                #$fg.Files.Refresh()
                if (!$failed) {
                    $logfiles = @($db.LogFiles)
                    for ($i = 0; $i -lt $logfiles.Count; $i++) {
                        $logicallog = $logfiles[$i]
                        $Orig_LGName = $logicallog.Name
                        $Orig_Placeholder = $Orig_LGName
                        if ($ReplaceBefore) {
                            # at Logical Name level, we need to worry about database name and filegroup name, but for logfiles filegroup is not there
                            $Orig_Placeholder = $Orig_Placeholder.Replace((Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name), '').Replace(
                                (Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name), '')
                        }
                        $NewLGName = $LogicalName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', '').Replace(
                            '<FT>', 'LOG').Replace('<LGN>', $Orig_Placeholder)
                        $FinalLGName = $NewLGName
                        if ($FinalLGName.Length -eq 0) {
                            #someone passed in -LogicalName '<FGN>'.... but we don't have FGN here
                            $FinalLGName = $Orig_LGName
                        }
                        while ($logicallog.Name -ne $FinalLGName) {
                            if ($FinalLGName -in $New_LogicalNames.Keys) {
                                $LNCounter += 1
                                $FinalLGName = "$NewLGName$($LNCounter.ToString('000'))"
                            } else {
                                break
                            }
                        }
                        if ($logicallog.Name -eq $FinalLGName) {
                            Write-Message -Level VeryVerbose -Message "No Rename necessary for LogicalFile log $($logicallog.Name) (LOG on (on $db))"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming LogicalFile log $($logicallog.Name) to $FinalLGName (LOG)")) {
                            try {
                                if (!$Preview) {
                                    $logicallog.Rename($FinalLGName)
                                }
                                $New_LogicalNames.Remove($Orig_LGName)
                                $New_LogicalNames[$FinalLGName] = 1
                                $Entities_Before['LGN'][$Orig_LGName] = $FinalLGName
                            } catch {
                                Stop-Function -Message "Failed to Rename Logical File : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                    #$db.Logfiles.Refresh()
                }
            }
            #endregion logicalname
            #region filename
            if ($ReplaceBefore) {
                foreach ($fn in $db.FileGroups.Files.FileName) {
                    $Entities_Before['FNN'][$fn] = $fn
                }
                foreach ($fn in $db.Logfiles.FileName) {
                    $Entities_Before['FNN'][$fn] = $fn
                }
            }
            if (!$failed -and $FileName) {

                $New_FileNames = @{ }
                foreach ($fn in $db.FileGroups.Files.FileName) {
                    $New_FileNames[$fn] = 1
                }
                foreach ($fn in $db.Logfiles.FileName) {
                    $New_FileNames[$fn] = 1
                }
                # we need to inspect what files are in the same directory
                # to avoid failing the process because the move won't work
                # here we have a dict keyed by instance and then keyed by path
                if ( !$InstanceFiles.ContainsKey($Server_Id) ) {
                    $InstanceFiles[$Server_Id] = @{ }
                }
                foreach ($fn in $New_FileNames.Keys) {
                    $dirname = [IO.Path]::GetDirectoryName($fn)
                    if ( !$InstanceFiles[$Server_Id].ContainsKey($dirname) ) {
                        $InstanceFiles[$Server_Id][$dirname] = @{ }
                        try {
                            $dirfiles = Get-DbaFile -SqlInstance $server -Path $dirname -EnableException
                        } catch {
                            Write-Message -Level Warning -Message "Failed to enumerate existing files at $dirname, move could go wrong"
                        }
                        foreach ($f in $dirfiles) {
                            $InstanceFiles[$Server_Id][$dirname][$f.Filename] = 1
                        }
                    }
                }
                $FNCounter = 0
                foreach ($fg in $db.FileGroups) {
                    $FG_Files = @($fg.Files)
                    foreach ($logical in $FG_Files) {
                        $FileType = switch ($fg.FileGroupType) {
                            'RowsFileGroup' { 'ROWS' }
                            'MemoryOptimizedDataFileGroup' { 'MMO' }
                            'FileStreamDataFileGroup' { 'FS' }
                            default { 'STD' }
                        }
                        $FNName = $logical.FileName
                        $FNNameDir = [IO.Path]::GetDirectoryName($FNName)
                        $Orig_FNNameLeaf = [IO.Path]::GetFileNameWithoutExtension($logical.FileName)
                        $Orig_Placeholder = $Orig_FNNameLeaf
                        if ($ReplaceBefore) {
                            # at Filename level, we need to worry about database name, filegroup name and logical file name
                            $Orig_Placeholder = $Orig_Placeholder.Replace((Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name), '').Replace(
                                (Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name), '').Replace(
                                (Get-DbaKeyByValue -HashTable $Entities_Before['LGN'] -Value $logical.Name), '')
                        }
                        $NewFNName = $FileName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $fg.Name).Replace(
                            '<FT>', $FileType).Replace('<LGN>', $logical.Name).Replace('<FNN>', $Orig_Placeholder)
                        $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$([IO.Path]::GetExtension($FNName))")

                        while ($logical.FileName -ne $FinalFNName) {
                            if ($InstanceFiles[$Server_Id][$FNNameDir].ContainsKey($FinalFNName)) {
                                $FNCounter += 1
                                $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$($FNCounter.ToString('000'))$([IO.Path]::GetExtension($FNName))"
                                )
                            } else {
                                break
                            }
                        }
                        if ($logical.FileName -eq $FinalFNName) {
                            Write-Message -Level VeryVerbose -Message "No rename necessary (on FileGroup $($fg.Name) (on $db))"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming FileName $($logical.FileName) to $FinalFNName (on FileGroup $($fg.Name))")) {
                            try {
                                if (!$Preview) {
                                    $logical.FileName = $FinalFNName
                                    $db.Alter()
                                }
                                $InstanceFiles[$Server_Id][$FNNameDir].Remove($FNName)
                                $InstanceFiles[$Server_Id][$FNNameDir][$FinalFNName] = 1
                                $Entities_Before['FNN'][$FNName] = $FinalFNName
                                $Pending_Renames += [pscustomobject]@{
                                    Source      = $FNName
                                    Destination = $FinalFNName
                                }
                            } catch {
                                Stop-Function -Message "Failed to Rename FileName : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                    if (!$failed) {
                        $FG_Files = @($db.Logfiles)
                        foreach ($logical in $FG_Files) {
                            $FNName = $logical.FileName
                            $FNNameDir = [IO.Path]::GetDirectoryName($FNName)
                            $Orig_FNNameLeaf = [IO.Path]::GetFileNameWithoutExtension($logical.FileName)
                            $Orig_Placeholder = $Orig_FNNameLeaf
                            if ($ReplaceBefore) {
                                # at Filename level, we need to worry about database name, filegroup name and logical file name
                                $Orig_Placeholder = $Orig_Placeholder.Replace((Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name), '').Replace(
                                    (Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name), '').Replace(
                                    (Get-DbaKeyByValue -HashTable $Entities_Before['LGN'] -Value $logical.Name), '')
                            }
                            $NewFNName = $FileName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', '').Replace(
                                '<FT>', 'LOG').Replace('<LGN>', $logical.Name).Replace('<FNN>', $Orig_Placeholder)
                            $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$([IO.Path]::GetExtension($FNName))")
                            while ($logical.FileName -ne $FinalFNName) {
                                if ($InstanceFiles[$Server_Id][$FNNameDir].ContainsKey($FinalFNName)) {
                                    $FNCounter += 1
                                    $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$($FNCounter.ToString('000'))$([IO.Path]::GetExtension($FNName))")
                                } else {
                                    break
                                }
                            }
                            if ($logical.FileName -eq $FinalFNName) {
                                Write-Message -Level VeryVerbose -Message "No rename necessary for $($logical.FileName) (LOG on (on $db))"
                                continue
                            }

                            if ($PSCmdlet.ShouldProcess($db, "Renaming FileName $($logical.FileName) to $FinalFNName (LOG)")) {
                                try {
                                    if (!$Preview) {
                                        $logical.FileName = $FinalFNName
                                        $db.Alter()
                                    }
                                    $InstanceFiles[$Server_Id][$FNNameDir].Remove($FNName)
                                    $InstanceFiles[$Server_Id][$FNNameDir][$FinalFNName] = 1
                                    $Entities_Before['FNN'][$FNName] = $FinalFNName
                                    $Pending_Renames += [pscustomobject]@{
                                        Source      = $FNName
                                        Destination = $FinalFNName
                                    }
                                } catch {
                                    Stop-Function -Message "Failed to Rename FileName : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                    # stop any further renames
                                    $failed = $true
                                    break
                                }
                            }
                        }
                    }

                }
                #endregion filename
                #region move
                $ComputerName = $null
                $Final_Renames = New-Object System.Collections.ArrayList
                if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                    # locally ran so we can just use rename-item
                    $ComputerName = $server.ComputerName
                } else {
                    # let's start checking if we can access .ComputerName
                    $testPS = $false
                    if ($SqlCredential) {
                        # why does Test-PSRemoting require a Credential param ? this is ugly...
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -Credential $SqlCredential -ErrorAction Stop
                    } else {
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -ErrorAction Stop
                    }
                    if (!($testPS)) {
                        # let's try to resolve it to a more qualified name, without "cutting" knowledge about the domain (only $server.Name possibly holds the complete info)
                        $Resolved = (Resolve-DbaNetworkName -ComputerName $server.Name).FullComputerName
                        if ($SqlCredential) {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -Credential $SqlCredential -ErrorAction Stop
                        } else {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -ErrorAction Stop
                        }
                        if ($testPS) {
                            $ComputerName = $Resolved
                        }
                    } else {
                        $ComputerName = $server.ComputerName
                    }
                }
                foreach ($op in $pending_renames) {
                    if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                        $null = $Final_Renames.Add([pscustomobject]@{
                                Source       = $op.Source
                                Destination  = $op.Destination
                                ComputerName = $ComputerName
                            })
                    } else {
                        if ($null -eq $ComputerName) {
                            # if we don't have remote access ($ComputerName is null) we can fallback to admin shares if they're available
                            if (Test-Path (Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Source)) {
                                $null = $Final_Renames.Add([pscustomobject]@{
                                        Source       = Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Source
                                        Destination  = Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Destination
                                        ComputerName = $server.ComputerName
                                    })
                            } else {
                                # flag the impossible rename ($ComputerName is $null)
                                $null = $Final_Renames.Add([pscustomobject]@{
                                        Source       = $op.Source
                                        Destination  = $op.Destination
                                        ComputerName = $ComputerName
                                    })
                            }
                        } else {
                            # we can do renames in a remote pssession
                            $null = $Final_Renames.Add([pscustomobject]@{
                                    Source       = $op.Source
                                    Destination  = $op.Destination
                                    ComputerName = $ComputerName
                                })
                        }
                    }
                }
                $Status = 'FULL'
                if (!$failed -and ($SetOffline -or $Move) -and $Final_Renames) {
                    if (!$Move) {
                        Write-Message -Level VeryVerbose -Message "Setting the database offline. You are in charge of moving the files to the new location"
                        # because renames still need to be dealt with
                        $Status = 'PARTIAL'
                    } else {
                        if ($PSCmdlet.ShouldProcess($db, "File Rename required, setting db offline")) {
                            $SetState = Set-DbaDbState -SqlInstance $server -Database $db.Name -Offline -Force
                            if ($SetState.Status -ne 'OFFLINE') {
                                Write-Message -Level Warning -Message "Setting db offline failed, You are in charge of moving the files to the new location"
                                # because it was impossible to set the database offline
                                $Status = 'PARTIAL'
                            } else {
                                try {
                                    while ($Final_Renames.Count -gt 0) {
                                        $op = $Final_Renames.Item(0)
                                        if ($null -eq $op.ComputerName) {
                                            Stop-Function -Message "No access to physical files for renames"
                                        } else {
                                            Write-Message -Level VeryVerbose -Message "Moving file $($op.Source) to $($op.Destination)"
                                            if (!$Preview) {
                                                $scriptBlock = {
                                                    $op = $args[0]
                                                    Rename-Item -Path $op.Source -NewName $op.Destination
                                                }
                                                Invoke-Command2 -ComputerName $op.ComputerName -Credential $sqlCredential -ScriptBlock $scriptBlock -ArgumentList $op
                                            }
                                        }
                                        $null = $Final_Renames.RemoveAt(0)
                                    }
                                } catch {
                                    $failed = $true
                                    # because a rename operation failed
                                    $Status = 'PARTIAL'
                                    Stop-Function -Message "Failed to rename $($op.Source) to $($op.Destination), you are in charge of moving the files to the new location" -ErrorRecord $_ -Target $instance -Exception $_.Exception -Continue
                                }
                                if (!$failed) {
                                    if ($PSCmdlet.ShouldProcess($db, "Setting database online")) {
                                        $SetState = Set-DbaDbState -SqlInstance $server -Database $db.Name -Online -Force
                                        if ($SetState.Status -ne 'ONLINE') {
                                            Write-Message -Level Warning -Message "Setting db online failed"
                                            # because renames were done, but the database didn't wake up
                                            $Status = 'PARTIAL'
                                        } else {
                                            $Status = 'FULL'
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    # because of a previous error with renames to do
                    $Status = 'PARTIAL'
                }
            } else {
                if (!$failed) {
                    # because no previous error and not filename
                    $Status = 'FULL'
                } else {
                    # because previous errors and not filename
                    $Status = 'PARTIAL'
                }
            }
            #endregion move
            # remove entities that match for the output
            foreach ($k in $Entities_Before.Keys) {
                $ToRemove = $Entities_Before[$k].GetEnumerator() | Where-Object { $_.Name -eq $_.Value } | Select-Object -ExpandProperty Name
                foreach ($el in $ToRemove) {
                    $Entities_Before[$k].Remove($el)
                }
            }
            [pscustomobject]@{
                ComputerName       = $server.ComputerName
                InstanceName       = $server.ServiceName
                SqlInstance        = $server.DomainInstanceName
                Database           = $db
                DBN                = $Entities_Before['DBN']
                DatabaseRenames    = ($Entities_Before['DBN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                FGN                = $Entities_Before['FGN']
                FileGroupsRenames  = ($Entities_Before['FGN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                LGN                = $Entities_Before['LGN']
                LogicalNameRenames = ($Entities_Before['LGN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                FNN                = $Entities_Before['FNN']
                FileNameRenames    = ($Entities_Before['FNN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                PendingRenames     = $Final_Renames
                Status             = $Status
            } | Select-DefaultView -ExcludeProperty DatabaseRenames, FileGroupsRenames, LogicalNameRenames, FileNameRenames
        }
        #endregion db loop
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUGSStq7V8cHjPq1utvWyfrEaC
# YgKgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFCrLM5SOpZTDqTv99FP+yX9L6yh6MA0G
# CSqGSIb3DQEBAQUABIIBAE0VyViV0n62AGOimLdUwiCJncglCnujz3Qy0bTxHMNE
# KSW79rZkDkFOXD+k/qsubHBoX+JA4AsLw3T0s1GRdDAmK2nE+qECUSuKlo9pQiIW
# b+HIQw3Lo8Oy1RC/KfCH5eZ43KmMOHtbCIuQg+keeMHeEvhspMXHx5nAEoA4Eart
# 33EPbgHUpGI1qDvXRI5Mmse4941E+x0VIYVvZfHmleN5BZOtnbGvd03+QFQQjRlN
# EMvhA3jlNvkeVE6noIi3aPM0RYRqhlHQD2Y3fmeUG8yvumHuxMPzkSTkvnb0g61X
# o/PKnsY3fGQpPs0xY9QZiViwsGnfluAovhlqbKyU3xuhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDE1WjAvBgkqhkiG9w0BCQQxIgQgs3YBtj17FZq8sJPp3CBm
# Z+Dglh5YO2MLOCRHPR7ZEhAwDQYJKoZIhvcNAQEBBQAEggIAK8PzqMTvTZTsZ6Y9
# LAJgnMPUfqOVdnIFuVB39mI8kWsLNvZ/brcOqbsCWKcH4BneqIR/5hualC+Vwkva
# XoPMIgi9ENCTWP6KzBtz2tDmIS1PA/tG3VybQvIZWNR0335kkzX2Ai3Vh/BXcKg8
# 0aJio0fGbUXeQ1IHxrqPbDtVcGy3EKREL2SoxaAwA58jN5fXJJzZ4BOpuGzcDV8b
# 4DWONHGobkXWy8JYVK30w5AqHyBdoaXswklWevuCamBYsxa5k+FG/oGBfDwfc/2m
# 0ajlTEel2HKO7qXuIQRNGH2jqtcifnmv2190StzronO/M7Trdw82MMQBgl4FEwDZ
# 7aFW3MUK35uw1zv/65jghdPSmuQpOyHnH4vaNwU3w6rt0PR4oXrcq2G7F/QHMMfG
# lYuKdRGgTeFWl7tTKeJcYaW1tfiMfUafdneO2CRoHFghFLFzSzoHsW53AgdEbMgk
# V7Kr97gYhl9QjsSOLsMb4WgpGIVN9yEiZs3MtywNQejsNofzd3OSfWdoAvLXiOJV
# VRCwNmhRRrX7/YMr4l74gu9nBgzfomCVh1uZ+BYglLZ1+FsZLwkcIL1HvG2xY0DG
# zCzQ47aMLm+pQ8vPO1NU/wFqPqLcJSnii4Wc/iyUp7GK+gpGjiryyzDwA8Np+rtb
# zVihGSXSAyUeUB9l87AiBv4wyJY=
# SIG # End signature block
