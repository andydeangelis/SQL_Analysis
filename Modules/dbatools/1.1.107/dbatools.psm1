#requires -Version 3.0
param(
    [Collections.IDictionary]
    [Alias('Options')]
    $Option = @{ }
)

$start = [DateTime]::Now

if (($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -and $PSVersionTable.Platform -eq 'Win32NT')) {
    $script:isWindows = $true
} else {
    $script:isWindows = $false
}

if ($IsLinux -or $IsMacOS) {
    # this doesn't exist by default
    # https://github.com/PowerShell/PowerShell/issues/1262
    $env:COMPUTERNAME = hostname
}

if ('Sqlcollaborative.Dbatools.dbaSystem.DebugHost' -as [Type]) {
    # If we've already got for module import,
    [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Clear() # clear it (since we're clearly re-importing)
}

#region Import helper functions
function Import-ModuleFile {
    <#
    .SYNOPSIS
        Helps import dbatools files according to configuration

    .DESCRIPTION
        Helps import dbatools files according to configuration
        Always dotsource this function!

    .PARAMETER Path
        The full path to the file to import

    .EXAMPLE
        PS C:\> Import-ModuleFile -Path $function.FullName

        Imports the file stored at '$function.FullName'
    #>
    [CmdletBinding()]
    param (
        $Path
    )

    if (-not $path) {
        return
    }

    if ($script:doDotSource) {
        . (Resolve-Path -Path $Path)
    } else {
        $txt = [IO.File]::ReadAllText((Resolve-Path -Path $Path).ProviderPath)
        $ExecutionContext.InvokeCommand.InvokeScript($TXT, $false, [Management.Automation.Runspaces.PipelineResultTypes]::None, $null, $null)
    }
}

function Write-ImportTime {
    <#
    .SYNOPSIS
        Writes an entry to the import module time debug list

    .DESCRIPTION
        Writes an entry to the import module time debug list

    .PARAMETER Text
        The message to write

    .EXAMPLE
        PS C:\> Write-ImportTime -Text "Starting SMO Import"

        Adds the message "Starting SMO Import" to the debug list
#>
    param (
        [string]$Text,
        $Timestamp = ([DateTime]::now)
    )


    if (-not $script:dbatools_ImportPerformance) {
        $script:dbatools_ImportPerformance = New-Object Collections.ArrayList
    }

    if (-not ('Sqlcollaborative.Dbatools.Configuration.Config' -as [type])) {
        $script:dbatools_ImportPerformance.AddRange(@(New-Object PSObject -Property @{ Time = $timestamp; Action = $Text }))
    } else {
        if ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Count -eq 0) {
            foreach ($entry in $script:dbatools_ImportPerformance) {
                $te = New-Object Sqlcollaborative.Dbatools.dbaSystem.StartTimeEntry($entry.Action, $entry.Time, [Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId)
                [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Add($te)
            }
            $script:dbatools_ImportPerformance.Clear()
        }
        $te = New-Object Sqlcollaborative.Dbatools.dbaSystem.StartTimeEntry($Text, $timestamp, ([Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
        [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Add($te)
    }
}

Write-ImportTime -Text "Start" -Timestamp $start
Write-ImportTime -Text "Loading System.Security"
Add-Type -AssemblyName System.Security
Write-ImportTime -Text "Loading import helper functions"
#endregion Import helper functions

# Not supporting the provider path at this time 2/28/2017
if ($ExecutionContext.SessionState.Path.CurrentLocation.Drive.Name -eq 'SqlServer') {
    Write-Warning "SQLSERVER:\ provider not supported. Please change to another directory and reload the module."
    Write-Warning "Going to continue loading anyway, but expect issues."
}

Write-ImportTime -Text "Resolved path to not SQLSERVER PSDrive"

$script:PSModuleRoot = $PSScriptRoot

if ($PSVersionTable.PSEdition -and $PSVersionTable.PSEdition -ne 'Desktop') {
    $script:core = $true
} else {
    $script:core = $false
}

#region Import Defines
if ($psVersionTable.Platform -ne 'Unix' -and 'Microsoft.Win32.Registry' -as [Type]) {
    $regType = 'Microsoft.Win32.Registry' -as [Type]
    $hkcuNode = $regType::CurrentUser.OpenSubKey("SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")
    if ($dbaToolsSystemNode) {
        $userValues = @{ }
        foreach ($v in $hkcuNode.GetValueNames()) {
            $userValues[$v] = $hkcuNode.GetValue($v)
        }
        $dbatoolsSystemUserNode = $systemValues
    }
    $hklmNode = $regType::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")
    if ($dbaToolsSystemNode) {
        $systemValues = @{ }
        foreach ($v in $hklmNode.GetValueNames()) {
            $systemValues[$v] = $hklmNode.GetValue($v)
        }
        $dbatoolsSystemSystemNode = $systemValues
    }
} else {
    $dbatoolsSystemUserNode = @{ }
    $dbatoolsSystemSystemNode = @{ }
}

#region Dot Sourcing
# Detect whether at some level dotsourcing was enforced
$script:doDotSource = $dbatools_dotsourcemodule -or
$dbatoolsSystemSystemNode.DoDotSource -or
$dbatoolsSystemUserNode.DoDotSource -or
$option.DoDotSource
#endregion Dot Sourcing

#region Copy DLL Mode
# copy dll mode adds mess but is useful for installations using install.ps1
$script:copyDllMode = $dbatools_copydllmode -or
$dbatoolsSystemSystemNode.CopyDllMode -or
$dbatoolsSystemUserNode.CopyDllMode -or
$option.CopyDllMode
#endregion Copy DLL Mode

#region Always Compile
$script:alwaysBuildLibrary = $dbatools_alwaysbuildlibrary -or
$dbatoolsSystemSystemNode.AlwaysBuildLibrary -or
$dbatoolsSystemUserNode.AlwaysBuildLibrary -or
$option.AlwaysBuildLibrary
#endregion Always Compile

#region Serial Import
$script:serialImport = $dbatools_serialimport -or
$dbatoolsSystemSystemNode.SerialImport -or
$dbatoolsSystemUserNode.SerialImport -or
$Option.SerialImport
#endregion Serial Import

#region Multi File Import
$script:multiFileImport = $dbatools_multiFileImport -or
$dbatoolsSystemSystemNode.MultiFileImport -or
$dbatoolsSystemUserNode.MultiFileImport -or
$option.MultiFileImport


$gitDir = $script:PSModuleRoot, '.git' -join [IO.Path]::DirectorySeparatorChar
if ($dbatools_enabledebug -or
    $option.Debug -or
    $DebugPreference -ne 'silentlycontinue' -or
    [IO.Directory]::Exists($gitDir)) {
    $script:multiFileImport, $script:SerialImport, $script:doDotSource = $true, $true, $true
}
#endregion Multi File Import

Write-ImportTime -Text "Validated defines"
#endregion Import Defines

if (($PSVersionTable.PSVersion.Major -le 5) -or $script:isWindows) {
    Get-ChildItem -Path (Resolve-Path "$script:PSModuleRoot\bin\") -Filter "*.dll" -Recurse | Unblock-File -ErrorAction Ignore
    Write-ImportTime -Text "Unblocking Files"
}

$script:DllRoot = (Resolve-Path -Path "$script:PSModuleRoot\bin\").ProviderPath

<#
If dbatools has not been imported yet, it also hasn't done libraries yet. Fix that.
Previously checked for SMO being available, but that would break import with SqlServer loaded
Some people also use the dbatools library for other things without the module, so also check,
whether the modulebase has been set (first thing it does after loading library through dbatools import)
Theoretically, there's a minor cuncurrency collision risk with that, but since the cost is only
a little import time loss if that happens ...
#>
if ((-not ('Sqlcollaborative.Dbatools.dbaSystem.DebugHost' -as [type])) -or (-not [Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase)) {
    . $script:psScriptRoot\internal\scripts\libraryimport.ps1
    Write-ImportTime -Text "Starting import SMO libraries"
}

<#

    Do the rest of the loading

#>

# This technique helps a little bit
# https://becomelotr.wordpress.com/2017/02/13/expensive-dot-sourcing/

# Load our own custom library
# Should always come before function imports
. $psScriptRoot\bin\library.ps1
. $psScriptRoot\bin\typealiases.ps1
Write-ImportTime -Text "Loading dbatools library"

# Tell the library where the module is based, just in case
[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase = $script:PSModuleRoot

if ($script:multiFileImport -or -not (Test-Path -Path "$psScriptRoot\allcommands.ps1")) {
    # All internal functions privately available within the toolset
    foreach ($file in (Get-ChildItem -Path "$psScriptRoot\internal\functions\" -Recurse -Filter *.ps1)) {
        . $file.FullName
    }
    Write-ImportTime -Text "Loading Internal Commands"

    #    . $psScriptRoot\internal\scripts\cmdlets.ps1

    Write-ImportTime -Text "Registering cmdlets"

    # All exported functions
    foreach ($file in (Get-ChildItem -Path "$script:PSModuleRoot\functions\" -Recurse -Filter *.ps1)) {
        . $file.FullName
    }
    Write-ImportTime -Text "Loading Public Commands"

} else {
    #    . $psScriptRoot\internal\scripts\cmdlets.ps1
    Write-Verbose -Message "Loading allcommands.ps1 to speed up import times"
    . $psScriptRoot\allcommands.ps1
    #. (Resolve-Path -Path "$script:PSModuleRoot\allcommands.ps1")
    Write-ImportTime -Text "Loading Public and Private Commands"

    Write-ImportTime -Text "Registering cmdlets"
}

# Load configuration system
# Should always go after library and path setting
. $psScriptRoot\internal\configurations\configuration.ps1
Write-ImportTime -Text "Configuration System"

# Resolving the path was causing trouble when it didn't exist yet
# Not converting the path separators based on OS was also an issue.
if (-not ([Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath)) {
    [Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath = Join-DbaPath $script:AppData "PowerShell" "dbatools"
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($file in (Get-ChildItem -Path "$script:PSScriptRoot\optional" -Filter *.ps1)) {
    . $file.FullName
}
Write-ImportTime -Text "Loading Optional Commands"

# Process TEPP parameters
. $psScriptRoot\internal\scripts\insertTepp.ps1
Write-ImportTime -Text "Loading TEPP"


# Process transforms
. $psScriptRoot\internal\scripts\message-transforms.ps1
Write-ImportTime -Text "Loading Message Transforms"

# Load scripts that must be individually run at the end #
#-------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
. $psScriptRoot\internal\scripts\logfilescript.ps1
Write-ImportTime -Text "Script: Logging"

# Start the tepp asynchronous update system (requires the configuration system up and running)
. $psScriptRoot\internal\scripts\updateTeppAsync.ps1
Write-ImportTime -Text "Script: Asynchronous TEPP Cache"

# Start the maintenance system (requires pretty much everything else already up and running)
. $psScriptRoot\internal\scripts\dbatools-maintenance.ps1
Write-ImportTime -Text "Script: Maintenance"

#region Aliases

# New 3-char aliases
$shortcuts = @{
    'ivq' = 'Invoke-DbaQuery'
    'cdi' = 'Connect-DbaInstance'
}
foreach ($_ in $shortcuts.GetEnumerator()) {
    New-Alias -Name $_.Key -Value $_.Value
}

# Leave forever
$forever = @{
    'Get-DbaRegisteredServer' = 'Get-DbaRegServer'
    'Attach-DbaDatabase'      = 'Mount-DbaDatabase'
    'Detach-DbaDatabase'      = 'Dismount-DbaDatabase'
    'Start-SqlMigration'      = 'Start-DbaMigration'
    'Write-DbaDataTable'      = 'Write-DbaDbTableData'
    'Get-DbaDbModule'         = 'Get-DbaModule'
    'Get-DbaBuildReference'   = 'Get-DbaBuild'
}
foreach ($_ in $forever.GetEnumerator()) {
    Set-Alias -Name $_.Key -Value $_.Value
}
#endregion Aliases

#region Post-Import Cleanup
Write-ImportTime -Text "Loading Aliases"

# region Commands
$script:xplat = @(
    'Start-DbaMigration',
    'Copy-DbaDatabase',
    'Copy-DbaLogin',
    'Copy-DbaAgentServer',
    'Copy-DbaSpConfigure',
    'Copy-DbaDbMail',
    'Copy-DbaDbAssembly',
    'Copy-DbaAgentSchedule',
    'Copy-DbaAgentOperator',
    'Copy-DbaAgentJob',
    'Copy-DbaCustomError',
    'Copy-DbaInstanceAuditSpecification',
    'Copy-DbaEndpoint',
    'Copy-DbaInstanceAudit',
    'Copy-DbaServerRole',
    'Copy-DbaResourceGovernor',
    'Copy-DbaXESession',
    'Copy-DbaInstanceTrigger',
    'Copy-DbaRegServer',
    'Copy-DbaSysDbUserObject',
    'Copy-DbaAgentProxy',
    'Copy-DbaAgentAlert',
    'Copy-DbaStartupProcedure',
    'Get-DbaDbDetachedFileInfo',
    'Copy-DbaAgentJobCategory',
    'Get-DbaLinkedServerLogin',
    'Test-DbaPath',
    'Export-DbaLogin',
    'Watch-DbaDbLogin',
    'Expand-DbaDbLogFile',
    'Test-DbaMigrationConstraint',
    'Test-DbaNetworkLatency',
    'Find-DbaDbDuplicateIndex',
    'Remove-DbaDatabaseSafely',
    'Set-DbaTempdbConfig',
    'Test-DbaTempdbConfig',
    'Repair-DbaDbOrphanUser',
    'Remove-DbaDbOrphanUser',
    'Find-DbaDbUnusedIndex',
    'Get-DbaDbSpace',
    'Test-DbaDbOwner',
    'Set-DbaDbOwner',
    'Test-DbaAgentJobOwner',
    'Set-DbaAgentJobOwner',
    'Measure-DbaDbVirtualLogFile',
    'Get-DbaDbRestoreHistory',
    'Get-DbaTcpPort',
    'Test-DbaDbCompatibility',
    'Test-DbaDbCollation',
    'Test-DbaConnectionAuthScheme',
    'Test-DbaInstanceName',
    'Repair-DbaInstanceName',
    'Stop-DbaProcess',
    'Find-DbaOrphanedFile',
    'Get-DbaAvailabilityGroup',
    'Get-DbaLastGoodCheckDb',
    'Get-DbaProcess',
    'Get-DbaRunningJob',
    'Set-DbaMaxDop',
    'Test-DbaDbRecoveryModel',
    'Test-DbaMaxDop',
    'Remove-DbaBackup',
    'Get-DbaPermission',
    'Get-DbaLastBackup',
    'Connect-DbaInstance',
    'Get-DbaDbBackupHistory',
    'Get-DbaAgBackupHistory',
    'Read-DbaBackupHeader',
    'Test-DbaLastBackup',
    'Get-DbaMaxMemory',
    'Set-DbaMaxMemory',
    'Get-DbaDbSnapshot',
    'Remove-DbaDbSnapshot',
    'Get-DbaDbRoleMember',
    'Get-DbaServerRoleMember',
    'Get-DbaDbAsymmetricKey',
    'New-DbaDbAsymmetricKey',
    'Remove-DbaDbAsymmetricKey',
    'Invoke-DbaDbTransfer',
    'New-DbaDbTransfer',
    'Remove-DbaDbData',
    'Resolve-DbaNetworkName',
    'Export-DbaAvailabilityGroup',
    'Write-DbaDbTableData',
    'New-DbaDbSnapshot',
    'Restore-DbaDbSnapshot',
    'Get-DbaInstanceTrigger',
    'Get-DbaDbTrigger',
    'Get-DbaDbState',
    'Set-DbaDbState',
    'Get-DbaHelpIndex',
    'Get-DbaAgentAlert',
    'Get-DbaAgentOperator',
    'Get-DbaSpConfigure',
    'Rename-DbaLogin',
    'Find-DbaAgentJob',
    'Find-DbaDatabase',
    'Get-DbaXESession',
    'Export-DbaXESession',
    'Test-DbaOptimizeForAdHoc',
    'Find-DbaStoredProcedure',
    'Measure-DbaBackupThroughput',
    'Get-DbaDatabase',
    'Find-DbaUserObject',
    'Get-DbaDependency',
    'Find-DbaCommand',
    'Backup-DbaDatabase',
    'Test-DbaBackupEncrypted',
    'New-DbaDirectory',
    'Get-DbaDbQueryStoreOption',
    'Set-DbaDbQueryStoreOption',
    'Restore-DbaDatabase',
    'Get-DbaDbFileMapping',
    'Copy-DbaDbQueryStoreOption',
    'Get-DbaExecutionPlan',
    'Export-DbaExecutionPlan',
    'Set-DbaSpConfigure',
    'Test-DbaIdentityUsage',
    'Get-DbaDbAssembly',
    'Get-DbaAgentJob',
    'Get-DbaCustomError',
    'Get-DbaCredential',
    'Get-DbaBackupDevice',
    'Get-DbaAgentProxy',
    'Get-DbaDbEncryption',
    'Disable-DbaDbEncryption',
    'Enable-DbaDbEncryption',
    'Get-DbaDbEncryptionKey',
    'New-DbaDbEncryptionKey',
    'Remove-DbaDbEncryptionKey',
    'Start-DbaDbEncryption',
    'Stop-DbaDbEncryption',
    'Remove-DbaDatabase',
    'Get-DbaQueryExecutionTime',
    'Get-DbaTempdbUsage',
    'Find-DbaDbGrowthEvent',
    'Test-DbaLinkedServerConnection',
    'Get-DbaDbFile',
    'Get-DbaDbFileGrowth',
    'Set-DbaDbFileGrowth',
    'Read-DbaTransactionLog',
    'Get-DbaDbTable',
    'Remove-DbaDbTable',
    'Invoke-DbaDbShrink',
    'Get-DbaEstimatedCompletionTime',
    'Get-DbaLinkedServer',
    'New-DbaAgentJob',
    'Get-DbaLogin',
    'New-DbaScriptingOption',
    'Save-DbaDiagnosticQueryScript',
    'Invoke-DbaDiagnosticQuery',
    'Export-DbaDiagnosticQuery',
    'Invoke-DbaWhoIsActive',
    'Set-DbaAgentJob',
    'Remove-DbaAgentJob',
    'New-DbaAgentJobStep',
    'Set-DbaAgentJobStep',
    'Remove-DbaAgentJobStep',
    'New-DbaAgentSchedule',
    'Set-DbaAgentSchedule',
    'Remove-DbaAgentSchedule',
    'Backup-DbaDbCertificate',
    'Get-DbaDbCertificate',
    'Copy-DbaDbCertificate',
    'Get-DbaEndpoint',
    'Get-DbaDbMasterKey',
    'Get-DbaSchemaChangeHistory',
    'Get-DbaInstanceAudit',
    'Get-DbaInstanceAuditSpecification',
    'Get-DbaProductKey',
    'Get-DbatoolsError',
    'Get-DbatoolsLog',
    'Restore-DbaDbCertificate',
    'New-DbaDbCertificate',
    'New-DbaDbMasterKey',
    'New-DbaServiceMasterKey',
    'Remove-DbaDbCertificate',
    'Remove-DbaDbMasterKey',
    'Get-DbaInstanceProperty',
    'Get-DbaInstanceUserOption',
    'New-DbaConnectionString',
    'Get-DbaAgentSchedule',
    'Read-DbaTraceFile',
    'Get-DbaInstanceInstallDate',
    'Backup-DbaDbMasterKey',
    'Get-DbaAgentJobHistory',
    'Get-DbaMaintenanceSolutionLog',
    'Invoke-DbaDbLogShipRecovery',
    'Find-DbaTrigger',
    'Find-DbaView',
    'Invoke-DbaDbUpgrade',
    'Get-DbaDbUser',
    'Get-DbaAgentLog',
    'Get-DbaDbMailLog',
    'Get-DbaDbMailHistory',
    'Get-DbaDbView',
    'Remove-DbaDbView',
    'New-DbaSqlParameter',
    'Get-DbaDbUdf',
    'Get-DbaDbPartitionFunction',
    'Get-DbaDbPartitionScheme',
    'Remove-DbaDbPartitionScheme',
    'Remove-DbaDbPartitionFunction',
    'Get-DbaDefaultPath',
    'Get-DbaDbStoredProcedure',
    'Test-DbaDbCompression',
    'Mount-DbaDatabase',
    'Dismount-DbaDatabase',
    'Get-DbaAgReplica',
    'Get-DbaAgDatabase',
    'Get-DbaModule',
    'Sync-DbaLoginPermission',
    'New-DbaCredential',
    'Get-DbaFile',
    'Set-DbaDbCompression',
    'Get-DbaTraceFlag',
    'Invoke-DbaCycleErrorLog',
    'Get-DbaAvailableCollation',
    'Get-DbaUserPermission',
    'Get-DbaAgHadr',
    'Find-DbaSimilarTable',
    'Get-DbaTrace',
    'Get-DbaSuspectPage',
    'Get-DbaWaitStatistic',
    'Clear-DbaWaitStatistics',
    'Get-DbaTopResourceUsage',
    'New-DbaLogin',
    'Get-DbaAgListener',
    'Invoke-DbaDbClone',
    'Disable-DbaTraceFlag',
    'Enable-DbaTraceFlag',
    'Start-DbaAgentJob',
    'Stop-DbaAgentJob',
    'New-DbaAgentProxy',
    'Test-DbaDbLogShipStatus',
    'Get-DbaXESessionTarget',
    'New-DbaXESmartTargetResponse',
    'New-DbaXESmartTarget',
    'Get-DbaDbVirtualLogFile',
    'Get-DbaBackupInformation',
    'Start-DbaXESession',
    'Stop-DbaXESession',
    'Set-DbaDbRecoveryModel',
    'Get-DbaDbRecoveryModel',
    'Get-DbaWaitingTask',
    'Remove-DbaDbUser',
    'Get-DbaDump',
    'Invoke-DbaAdvancedRestore',
    'Format-DbaBackupInformation',
    'Get-DbaAgentJobStep',
    'Test-DbaBackupInformation',
    'Invoke-DbaBalanceDataFiles',
    'Select-DbaBackupInformation',
    'Publish-DbaDacPackage',
    'Copy-DbaDbTableData',
    'Copy-DbaDbViewData',
    'Invoke-DbaQuery',
    'Remove-DbaLogin',
    'Get-DbaAgentJobCategory',
    'New-DbaAgentJobCategory',
    'Remove-DbaAgentJobCategory',
    'Set-DbaAgentJobCategory',
    'Get-DbaServerRole',
    'Find-DbaBackup',
    'Remove-DbaXESession',
    'New-DbaXESession',
    'Get-DbaXEStore',
    'New-DbaXESmartTableWriter',
    'New-DbaXESmartReplay',
    'New-DbaXESmartEmail',
    'New-DbaXESmartQueryExec',
    'Start-DbaXESmartTarget',
    'Get-DbaDbOrphanUser',
    'Get-DbaOpenTransaction',
    'Get-DbaDbLogShipError',
    'Test-DbaBuild',
    'Get-DbaXESessionTemplate',
    'ConvertTo-DbaXESession',
    'Start-DbaTrace',
    'Stop-DbaTrace',
    'Remove-DbaTrace',
    'Set-DbaLogin',
    'Copy-DbaXESessionTemplate',
    'Get-DbaXEObject',
    'ConvertTo-DbaDataTable',
    'Find-DbaDbDisabledIndex',
    'Get-DbaXESmartTarget',
    'Remove-DbaXESmartTarget',
    'Stop-DbaXESmartTarget',
    'Get-DbaRegServerGroup',
    'New-DbaDbUser',
    'Measure-DbaDiskSpaceRequirement',
    'New-DbaXESmartCsvWriter',
    'Invoke-DbaXeReplay',
    'Find-DbaInstance',
    'Test-DbaDiskSpeed',
    'Get-DbaDbExtentDiff',
    'Read-DbaAuditFile',
    'Get-DbaDbCompression',
    'Invoke-DbaDbDecryptObject',
    'Get-DbaDbForeignKey',
    'Get-DbaDbCheckConstraint',
    'Remove-DbaDbCheckConstraint',
    'Set-DbaAgentAlert',
    'Get-DbaWaitResource',
    'Get-DbaDbPageInfo',
    'Get-DbaConnection',
    'Test-DbaLoginPassword',
    'Get-DbaErrorLogConfig',
    'Set-DbaErrorLogConfig',
    'Get-DbaPlanCache',
    'Clear-DbaPlanCache',
    'ConvertTo-DbaTimeline',
    'Get-DbaDbMail',
    'Get-DbaDbMailAccount',
    'Get-DbaDbMailProfile',
    'Get-DbaDbMailConfig',
    'Get-DbaDbMailServer',
    'New-DbaDbMailServer',
    'New-DbaDbMailAccount',
    'New-DbaDbMailProfile',
    'Get-DbaResourceGovernor',
    'Get-DbaRgResourcePool',
    'Get-DbaRgWorkloadGroup',
    'Get-DbaRgClassifierFunction',
    'Export-DbaInstance',
    'Invoke-DbatoolsRenameHelper',
    'Measure-DbatoolsImport',
    'Get-DbaDeprecatedFeature',
    'Test-DbaDeprecatedFeature'
    'Get-DbaDbFeatureUsage',
    'Stop-DbaEndpoint',
    'Start-DbaEndpoint',
    'Set-DbaDbMirror',
    'Repair-DbaDbMirror',
    'Remove-DbaEndpoint',
    'Remove-DbaDbMirrorMonitor',
    'Remove-DbaDbMirror',
    'New-DbaEndpoint',
    'Invoke-DbaDbMirroring',
    'Invoke-DbaDbMirrorFailover',
    'Get-DbaDbMirrorMonitor',
    'Get-DbaDbMirror',
    'Add-DbaDbMirrorMonitor',
    'Test-DbaEndpoint',
    'Get-DbaDbSharePoint',
    'Get-DbaDbMemoryUsage',
    'Clear-DbaLatchStatistics',
    'Get-DbaCpuRingBuffer',
    'Get-DbaIoLatency',
    'Get-DbaLatchStatistic',
    'Get-DbaSpinLockStatistic',
    'Add-DbaAgDatabase',
    'Add-DbaAgListener',
    'Add-DbaAgReplica',
    'Grant-DbaAgPermission',
    'Invoke-DbaAgFailover',
    'Join-DbaAvailabilityGroup',
    'New-DbaAvailabilityGroup',
    'Remove-DbaAgDatabase',
    'Remove-DbaAgListener',
    'Remove-DbaAvailabilityGroup',
    'Revoke-DbaAgPermission',
    'Get-DbaDbCompatibility',
    'Set-DbaDbCompatibility',
    'Invoke-DbatoolsFormatter',
    'Remove-DbaAgReplica',
    'Resume-DbaAgDbDataMovement',
    'Set-DbaAgListener',
    'Set-DbaAgReplica',
    'Set-DbaAvailabilityGroup',
    'Set-DbaEndpoint',
    'Suspend-DbaAgDbDataMovement',
    'Sync-DbaAvailabilityGroup',
    'Get-DbaMemoryCondition',
    'Remove-DbaDbBackupRestoreHistory',
    'New-DbaDatabase'
    'New-DbaDacOption',
    'Get-DbaDbccHelp',
    'Get-DbaDbccMemoryStatus',
    'Get-DbaDbccProcCache',
    'Get-DbaDbccUserOption',
    'Get-DbaAgentServer',
    'Set-DbaAgentServer',
    'Invoke-DbaDbccFreeCache'
    'Export-DbatoolsConfig',
    'Import-DbatoolsConfig',
    'Reset-DbatoolsConfig',
    'Unregister-DbatoolsConfig',
    'Join-DbaPath',
    'Resolve-DbaPath',
    'Import-DbaCsv',
    'Invoke-DbaDbDataMasking',
    'New-DbaDbMaskingConfig',
    'Get-DbaDbccSessionBuffer',
    'Get-DbaDbccStatistic',
    'Get-DbaDbDbccOpenTran',
    'Invoke-DbaDbccDropCleanBuffer',
    'Invoke-DbaDbDbccCheckConstraint',
    'Invoke-DbaDbDbccCleanTable',
    'Invoke-DbaDbDbccUpdateUsage',
    'Get-DbaDbIdentity',
    'Set-DbaDbIdentity',
    'Get-DbaRegServer',
    'Get-DbaRegServerStore',
    'Add-DbaRegServer',
    'Add-DbaRegServerGroup',
    'Export-DbaRegServer',
    'Import-DbaRegServer',
    'Move-DbaRegServer',
    'Move-DbaRegServerGroup',
    'Remove-DbaRegServer',
    'Remove-DbaRegServerGroup',
    'New-DbaCustomError',
    'Remove-DbaCustomError',
    'Get-DbaDbSequence',
    'New-DbaDbSequence',
    'Remove-DbaDbSequence',
    'Select-DbaDbSequenceNextValue',
    'Set-DbaDbSequence',
    'Get-DbaDbUserDefinedTableType',
    'Get-DbaDbServiceBrokerService',
    'Get-DbaDbServiceBrokerQueue ',
    'Set-DbaResourceGovernor',
    'New-DbaRgResourcePool',
    'Set-DbaRgResourcePool',
    'Remove-DbaRgResourcePool',
    # Config system
    'Get-DbatoolsConfig',
    'Get-DbatoolsConfigValue',
    'Set-DbatoolsConfig',
    'Register-DbatoolsConfig',
    # Data generator
    'New-DbaDbDataGeneratorConfig',
    'Invoke-DbaDbDataGenerator',
    'Get-DbaRandomizedValue',
    'Get-DbaRandomizedDatasetTemplate',
    'Get-DbaRandomizedDataset',
    'Get-DbaRandomizedType',
    'Export-DbaDbTableData',
    'Backup-DbaServiceMasterKey',
    'Invoke-DbaDbPiiScan',
    'New-DbaAzAccessToken',
    'Add-DbaDbRoleMember',
    'Disable-DbaStartupProcedure',
    'Enable-DbaStartupProcedure',
    'Get-DbaDbFilegroup',
    'Get-DbaDbObjectTrigger',
    'Get-DbaStartupProcedure',
    'Get-DbatoolsChangeLog',
    'Get-DbaXESessionTargetFile',
    'Get-DbaDbRole',
    'New-DbaDbRole',
    'New-DbaDbTable',
    'New-DbaDiagnosticAdsNotebook',
    'New-DbaServerRole',
    'Remove-DbaDbRole',
    'Remove-DbaDbRoleMember',
    'Remove-DbaServerRole',
    'Test-DbaDbDataGeneratorConfig',
    'Test-DbaDbDataMaskingConfig',
    'Get-DbaAgentAlertCategory',
    'New-DbaAgentAlertCategory',
    'Remove-DbaAgentAlert',
    'Remove-DbaAgentAlertCategory',
    'Save-DbaKbUpdate',
    'Get-DbaKbUpdate',
    'Get-DbaDbLogSpace',
    'Export-DbaDbRole',
    'Export-DbaServerRole',
    'Get-DbaBuild',
    'Update-DbaBuildReference',
    'Install-DbaFirstResponderKit',
    'Install-DbaWhoIsActive',
    'Update-Dbatools',
    'Add-DbaServerRoleMember',
    'Get-DbatoolsPath',
    'Set-DbatoolsPath',
    'Export-DbaSysDbUserObject',
    'Test-DbaDbQueryStore',
    'Install-DbaMultiTool',
    'New-DbaAgentOperator',
    'Remove-DbaAgentOperator',
    'Remove-DbaDbTableData',
    'Get-DbaDbSchema',
    'New-DbaDbSchema',
    'Set-DbaDbSchema',
    'Remove-DbaDbSchema',
    'Get-DbaDbSynonym',
    'New-DbaDbSynonym',
    'Remove-DbaDbSynonym',
    'Install-DbaDarlingData',
    'New-DbaDbFileGroup',
    'Remove-DbaDbFileGroup',
    'Set-DbaDbFileGroup',
    'Remove-DbaLinkedServer',
    'Test-DbaAvailabilityGroup',
    'Export-DbaUser',
    'Get-DbaSsisExecutionHistory',
    'New-DbaConnectionStringBuilder',
    'New-DbatoolsSupportPackage',
    'Export-DbaScript',
    'Get-DbaAgentJobOutputFile',
    'Set-DbaAgentJobOutputFile',
    'Import-DbaXESessionTemplate',
    'Export-DbaXESessionTemplate',
    'Import-DbaSpConfigure',
    'Export-DbaSpConfigure',
    'Test-DbaMaxMemory',
    'Install-DbaMaintenanceSolution',
    'Get-DbaManagementObject',
    'Set-DbaAgentOperator',
    'Remove-DbaExtendedProperty',
    'Get-DbaExtendedProperty',
    'Set-DbaExtendedProperty',
    'Add-DbaExtendedProperty',
    'Get-DbaOleDbProvider',
    'Get-DbaConnectedInstance',
    'Disconnect-DbaInstance',
    'Set-DbaDefaultPath',
    'New-DbaDacProfile',
    'Export-DbaDacPackage',
    'Remove-DbaDbUdf',
    'Save-DbaCommunitySoftware',
    'Update-DbaMaintenanceSolution',
    'Remove-DbaServerRoleMember',
    'Remove-DbaDbMailProfile',
    'Remove-DbaDbMailAccount',
    'Set-DbaRgWorkloadGroup',
    'New-DbaRgWorkloadGroup',
    'Remove-DbaRgWorkloadGroup',
    'New-DbaLinkedServerLogin',
    'Remove-DbaLinkedServerLogin',
    'Remove-DbaCredential',
    'Remove-DbaAgentProxy'
)

$script:noncoresmo = @(
    # SMO issues
    'Get-DbaRepDistributor',
    'Copy-DbaPolicyManagement',
    'Copy-DbaDataCollector',
    'Get-DbaPbmCategory',
    'Get-DbaPbmCategorySubscription',
    'Get-DbaPbmCondition',
    'Get-DbaPbmObjectSet',
    'Get-DbaPbmPolicy',
    'Get-DbaPbmStore',
    'Get-DbaRepPublication',
    'Test-DbaRepLatency',
    'Export-DbaRepServerSetting',
    'Get-DbaRepServer'
)
$script:windowsonly = @(
    # filesystem (\\ related),
    'Move-DbaDbFile'
    'Copy-DbaBackupDevice',
    'Read-DbaXEFile',
    'Watch-DbaXESession',
    # Registry
    'Get-DbaRegistryRoot',
    # GAC
    'Test-DbaManagementObject',
    # CM and Windows functions
    'Get-DbaInstalledPatch',
    'Get-DbaFirewallRule',
    'New-DbaFirewallRule',
    'Remove-DbaFirewallRule',
    'Rename-DbaDatabase',
    'Get-DbaNetworkConfiguration',
    'Set-DbaNetworkConfiguration',
    'Get-DbaExtendedProtection',
    'Set-DbaExtendedProtection',
    'Install-DbaInstance',
    'Invoke-DbaAdvancedInstall',
    'Update-DbaInstance',
    'Invoke-DbaAdvancedUpdate',
    'Invoke-DbaPfRelog',
    'Get-DbaPfDataCollectorCounter',
    'Get-DbaPfDataCollectorCounterSample',
    'Get-DbaPfDataCollector',
    'Get-DbaPfDataCollectorSet',
    'Start-DbaPfDataCollectorSet',
    'Stop-DbaPfDataCollectorSet',
    'Export-DbaPfDataCollectorSetTemplate',
    'Get-DbaPfDataCollectorSetTemplate',
    'Import-DbaPfDataCollectorSetTemplate',
    'Remove-DbaPfDataCollectorSet',
    'Add-DbaPfDataCollectorCounter',
    'Remove-DbaPfDataCollectorCounter',
    'Get-DbaPfAvailableCounter',
    'Export-DbaXECsv',
    'Get-DbaOperatingSystem',
    'Get-DbaComputerSystem',
    'Set-DbaPrivilege',
    'Set-DbaTcpPort',
    'Set-DbaCmConnection',
    'Get-DbaUptime',
    'Get-DbaMemoryUsage',
    'Clear-DbaConnectionPool',
    'Get-DbaLocaleSetting',
    'Get-DbaFilestream',
    'Enable-DbaFilestream',
    'Disable-DbaFilestream',
    'Get-DbaCpuUsage',
    'Get-DbaPowerPlan',
    'Get-DbaWsfcAvailableDisk',
    'Get-DbaWsfcCluster',
    'Get-DbaWsfcDisk',
    'Get-DbaWsfcNetwork',
    'Get-DbaWsfcNetworkInterface',
    'Get-DbaWsfcNode',
    'Get-DbaWsfcResource',
    'Get-DbaWsfcResourceType',
    'Get-DbaWsfcRole',
    'Get-DbaWsfcSharedVolume',
    'Export-DbaCredential',
    'Export-DbaLinkedServer',
    'Get-DbaFeature',
    'Update-DbaServiceAccount',
    'Remove-DbaClientAlias',
    'Disable-DbaAgHadr',
    'Enable-DbaAgHadr',
    'Stop-DbaService',
    'Start-DbaService',
    'Restart-DbaService',
    'New-DbaClientAlias',
    'Get-DbaClientAlias',
    'Stop-DbaExternalProcess',
    'Get-DbaExternalProcess',
    'Remove-DbaNetworkCertificate',
    'Enable-DbaForceNetworkEncryption',
    'Disable-DbaForceNetworkEncryption',
    'Get-DbaForceNetworkEncryption',
    'Get-DbaHideInstance',
    'Enable-DbaHideInstance',
    'Disable-DbaHideInstance',
    'New-DbaComputerCertificateSigningRequest',
    'Remove-DbaComputerCertificate',
    'New-DbaComputerCertificate',
    'Get-DbaComputerCertificate',
    'Add-DbaComputerCertificate',
    'Backup-DbaComputerCertificate',
    'Test-DbaComputerCertificateExpiration',
    'Get-DbaNetworkCertificate',
    'Set-DbaNetworkCertificate',
    'Remove-DbaDbLogshipping',
    'Invoke-DbaDbLogShipping',
    'New-DbaCmConnection',
    'Get-DbaCmConnection',
    'Remove-DbaCmConnection',
    'Test-DbaCmConnection',
    'Get-DbaCmObject',
    'Set-DbaStartupParameter',
    'Get-DbaNetworkActivity',
    'Get-DbaInstanceProtocol',
    'Install-DbatoolsWatchUpdate',
    'Uninstall-DbatoolsWatchUpdate',
    'Watch-DbatoolsUpdate',
    'Get-DbaPrivilege',
    'Get-DbaMsdtc',
    'Get-DbaPageFileSetting',
    'Copy-DbaCredential',
    'Test-DbaConnection',
    'Reset-DbaAdmin',
    'Copy-DbaLinkedServer',
    'Get-DbaDiskSpace',
    'Test-DbaDiskAllocation',
    'Test-DbaPowerPlan',
    'Set-DbaPowerPlan',
    'Test-DbaDiskAlignment',
    'Get-DbaStartupParameter',
    'Get-DbaSpn',
    'Test-DbaSpn',
    'Set-DbaSpn',
    'Remove-DbaSpn',
    'Get-DbaService',
    'Get-DbaClientProtocol',
    'Get-DbaWindowsLog',
    # WPF
    'Show-DbaInstanceFileSystem',
    'Show-DbaDbList',
    # AD
    'Test-DbaWindowsLogin',
    'Find-DbaLoginInGroup',
    # 3rd party non-core DLL or sqlpackage.exe
    'Install-DbaSqlWatch',
    'Uninstall-DbaSqlWatch',
    # Unknown
    'Get-DbaErrorLog'
)

# If a developer or appveyor calls the psm1 directly, they want all functions
# So do not explicitly export because everything else is then implicitly excluded
if (-not $script:multiFileImport) {
    $exports =
    @(if (($PSVersionTable.Platform)) {
            if ($PSVersionTable.Platform -ne "Win32NT") {
                $script:xplat
            } else {
                $script:xplat
                $script:windowsonly
            }
        } else {
            $script:xplat
            $script:windowsonly
            $script:noncoresmo
        })

    $aliasExport = @(
        foreach ($k in $script:Renames.Keys) {
            $k
        }
        foreach ($k in $script:Forever.Keys) {
            $k
        }
        foreach ($c in $script:shortcuts.Keys) {
            $c
        }
    )

    Export-ModuleMember -Alias $aliasExport -Function $exports -Cmdlet Select-DbaObject, Set-DbatoolsConfig

    Write-ImportTime -Text "Exported module member"
} else {
    Export-ModuleMember -Alias * -Function * -Cmdlet *
}

$timeout = 20000
$timeSpent = 0
while ($script:smoRunspace.Runspace.RunspaceAvailability -eq 'Busy') {
    [Threading.Thread]::Sleep(10)
    $timeSpent = $timeSpent + 50

    if ($timeSpent -ge $timeout) {
        Write-Warning @"
The module import has hit a timeout while waiting for some background tasks to finish.
This may result in some commands not working as intended.
This should not happen under reasonable circumstances, please file an issue at:
https://github.com/dataplat/dbatools/issues
Or contact us directly in the #dbatools channel of the SQL Server Community Slack Channel:
https://dbatools.io/slack/
Timeout waiting for temporary runspaces reached! The Module import will complete, but some things may not work as intended
"@
        $global:smoRunspace = $script:smoRunspace
        break
    }
}

if ($script:smoRunspace) {
    $script:smoRunspace.Runspace.Close()
    $script:smoRunspace.Runspace.Dispose()
    $script:smoRunspace.Dispose()
    $script:smoRunspace = $null
}
Write-ImportTime -Text "Waiting for runspaces to finish"
$myInv = $MyInvocation
if ($option.LoadTypes -or
    ($myInv.Line -like '*.psm1*' -and
        (-not (Get-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server)
        ))) {
    Update-TypeData -AppendPath (Resolve-Path -Path "$script:PSModuleRoot\xml\dbatools.Types.ps1xml")
    Write-ImportTime -Text "Loaded type extensions"
}
#. Import-ModuleFile "$script:PSModuleRoot\bin\type-extensions.ps1"
# Write-ImportTime -Text "Loaded type extensions"

Write-ImportTime -Text "Checking for conflicting SMO types"
$loadedversion = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }
if ($loadedversion -notmatch "dbatools") {
    if (Get-DbatoolsConfigValue -FullName Import.SmoCheck) {
        Write-Warning -Message 'An alternative SMO library has already been loaded in this session. This may cause unexpected behavior. See https://github.com/dataplat/dbatools/issues/8168 for more information.'
        Write-Warning -Message 'To disable this message, type: Set-DbatoolsConfig -Name Import.SmoCheck -Value $false -PassThru | Register-DbatoolsConfig'
    }
}

Write-ImportTime -Text "Checking to see if SqlServer or SQLPS has been loaded"
$loadedModuleNames = Get-Module | Select-Object -ExpandProperty Name
if ($loadedModuleNames -contains 'sqlserver' -or $loadedModuleNames -contains 'sqlps') {
    if (Get-DbatoolsConfigValue -FullName Import.SqlpsCheck) {
        Write-Warning -Message 'SQLPS or SqlServer was previously imported during this session. If you encounter weird issues with dbatools, please restart PowerShell, then import dbatools without loading SQLPS or SqlServer first.'
        Write-Warning -Message 'To disable this message, type: Set-DbatoolsConfig -Name Import.SqlpsCheck -Value $false -PassThru | Register-DbatoolsConfig'
    }
}

[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported = $true
#endregion Post-Import Cleanup

# Removal of runspaces is needed to successfully close PowerShell ISE
if (Test-Path -Path Variable:global:psISE) {
    $onRemoveScript = {
        Get-Runspace | Where-Object Name -like dbatools* | ForEach-Object -Process { $_.Dispose() }
    }
    $ExecutionContext.SessionState.Module.OnRemove += $onRemoveScript
    Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action $onRemoveScript
}

# Create collection for servers
$script:connectionhash = @{ }
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBBQC2ui+YM1XYV
# 9pOa1lauHXtiu7fp6rNIqvwY/iDraqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCcICIcZBqfUvJDfeN5yzoZ2I7gS1dCOetq
# R7zRAXhZbTANBgkqhkiG9w0BAQEFAASCAQA+PrF1ZssMyyvVszNaV/csVab0k9Qq
# CNITJTa7wO30vJMRgdUA/J0gXrN4MLiY3COBnuGUoVId7UeD5x79O2C5SaBFy+CT
# VfsUv/VhTVBe7UqmZJ7Y4t4b/lkhOAucQW95uhfl0JvuFmi8D1abnDsPM+HWFZyQ
# Cj+8yvMxO9uunVZ6UMqL3qZx5QOK1hluFTKoDVDXxsl7r3xmT13QSmUkJUouvjfR
# WHrmrFG/+ZnR8NjBknOIbjyeZDOCHvWz4GiduRULzy3qBXt2YkhQhJJlxnx1VSDX
# C9t7SiNlO9CES6ndSncXA1sm5+nE/RXf1qLjPpHZt+09jvjTQ6qTVSusoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQ1OVowLwYJKoZIhvcNAQkEMSIEIEdzUln5
# liNfECafqm7pVRw3ChbhMwvghZzl/BYHFskOMA0GCSqGSIb3DQEBAQUABIICAIRA
# 8prj2muWXs5hRFqdm/b6GPM88VZU745KHs93nrlM6fZ3fNZ7ZMKSnJ7k6zl13i9N
# n4s8O36/PooIAW4DkxR4b3fDUp9xI2VPNECOh2tPHU+0484yj4w0Mc6DD0XRh3++
# uATyjqP1LBQe9kFRYRGicDmr6RP8pGCfVt4OVOgiUenl40F0JVUpb8GiTs5pShvf
# Z2vSOUC0P/GHole58yQTzWlxRUvx2jYNmVTOTpc3MkpIdg17/2iuR+tVmYmQn1DY
# q4AbuDtP2fmIi0Agy/dMPxK1peiPB9/JHu1HRIbNjyhNc8ZpY3vz36BYyvbx44/M
# 8ZlGvWSIFPriUzEXcEkicCWJuz4meG6sQj8IP2I11RUdBnf9upuN7lg1FMB99E34
# x4e8LylUh83FLj43pGVqEUVK0RznX6Mgp/Ovo9HNonFBfKEuaJNW3Gi5l35dtgTh
# tcds3dG3jsduGrdtP7Y9OUnPZVmyqSHRy4snCcvM2cICOnepFY8sNeBVutmD/KRm
# ZhvlbAyDBPj1oZgVDzdBbzOqGcwgDKsrQLlLFPFhQy5TgJltT9gl6YbVCKx4vRk+
# xZbWtimva7fVfd95qKk40J8tins+oEyP0kyqBWiHkjimkvDDC2teBThyVKq0Pz/7
# AUM5Z2daF7WzRdDr5+y5WzH7u/ESOgAwzyI5pAUZ
# SIG # End signature block
