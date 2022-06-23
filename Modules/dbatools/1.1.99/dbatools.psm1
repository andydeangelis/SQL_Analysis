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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU1G/tZgtlQxpUSHSluQksEWoY
# 3QmgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFOsKRNR1ElUKzTkLK13bSrXImRpZMA0G
# CSqGSIb3DQEBAQUABIIBALBCKULj39tWwK5ZxwH2BfFnqo/k+izOSyey+MHn0fow
# o+kfQVv9W9KZQFa+SOtk23yG/BzAOngFEDICYaSOA8Iy1nuT8XZoFgtWRicd6na+
# XAY5FQiBQDIxAkN/M94ZcgvQidf9eVMhwjtReCd8Fv1Rx+kSTHiELPgjEcAN/Kyk
# HSXy/fb7xHZEwoYJXraqaGlARQEocBQvhu9pcg2zYV98WuKbbSHfMS3X2FytZDX+
# t2Xq3j7ZHYLbjxK/ua8CxJKdjfFkfAG5y58A/e1Yq0aJFXSxaiPADfW2NAe9Hsuw
# arwLh+wmHpVVdcR9l1gIcOhiZ/SL9M+2LJh8hiJ2bEahggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNTAyWjAvBgkqhkiG9w0BCQQxIgQg6KNHDT6iu+DIX7/tIwun
# 4qpDBTrh05ZhxR7bkV9UvwUwDQYJKoZIhvcNAQEBBQAEggIAFfL2U7bs+jDP7OmL
# J0Ov09xDrgKSXQ9mPn0F4u0MYfDbW57+ELOo3YacgFlruCpd4c6MtK6LIgw429Tz
# 14cy/Zl0j3BNJfjPAVDNUsWpiVOuJq/7YJfxxJxqU4clYYDLNYFBORXaPsYvxnlT
# qOkTYZs1abCpAILGpZiLJCXBOYPL7VXYtyqpps76uLbW6kMmH1dS0g/hCqsrUEBB
# IPObB9q/PosoQa6qnkTKLie2Xt0WNd9bsH+qEDhUtM4GD471l4BjqsesmmwP2r2s
# xAAsXFjBGSRD/kOT3tpmA0u+LYXcZF9M8p1qGTzaDbw6n290AaE4wk2pXhCn0PTk
# igTatuKx4bQDXDBvkDTwWy9hy5BM0N7Vc2FC6l0iM0RBREOaqPvOoaZNMNqjrzI6
# 5yiD4Z4g52MWCI9bg7Hzf2ITpMkoPjjOVQqYvQpJTjFqBIyWvSrizzfnWUXKa8FX
# rD7TqiIn49g26tRK4NIQ97VnmWmLl3YbKUk9Y8Lnvg049hTmzGurzdJEc5hDFyAb
# X/Nf8QuQqgDn3u2Szz4qv9LKl6Hna48FVBh5eykBaK3orGLiwrYy8/fPE/IbJMCD
# +vthTiyPcuOhfdYyS7Qcx31/gDCK1uo7NTWU9aBrxUpIP97xZ44Fqi8c6uHZD5zM
# fD/Cvl/6Szp7DvwC2UnmRqZee3o=
# SIG # End signature block
