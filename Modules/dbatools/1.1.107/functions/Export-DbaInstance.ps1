function Export-DbaInstance {
    <#
    .SYNOPSIS
        Exports SQL Server *ALL* database restore scripts, logins, database mail profiles/accounts, credentials, SQL Agent objects, linked servers,
        Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
        system triggers and backup devices from one SQL Server to another.

        For more granular control, please use one of the -Exclude parameters and use the other functions available within the dbatools module.

    .DESCRIPTION
        Export-DbaInstance consolidates most of the export scripts in dbatools into one command.

        This is useful when you're looking to Export entire instances. It less flexible than using the underlying functions.
        Think of it as an easy button. Unless an -Exclude is specified, it exports:

        All database 'restore from backup' scripts.  Note: if a database does not have a backup the 'restore from backup' script won't be generated.
        All logins.
        All database mail objects.
        All credentials.
        All objects within the Job Server (SQL Agent).
        All linked servers.
        All groups and servers within Central Management Server.
        All SQL Server configuration objects (everything in sp_configure).
        All user objects in system databases.
        All system triggers.
        All system backup devices.
        All Audits.
        All Endpoints.
        All Extended Events.
        All Policy Management objects.
        All Resource Governor objects.
        All Server Audit Specifications.
        All Custom Errors (User Defined Messages).
        All Server Roles.
        All Availability Groups.
        All OLEDB Providers.

        The exported files are written to a folder with a naming convention of "machinename$instance-yyyyMMddHHmmss".

        This command supports the following use cases related to the output files:

        1. Export files to a new timestamped folder. This is the default behavior and results in a simple historical archive within the local filesystem.
        2. Export files to an existing folder and overwrite pre-existing files. This can be accomplished using the -Force parameter.
        This results in a single folder location with the latest exported files. These files can then be checked into a source control system if needed.

    .PARAMETER SqlInstance
        The target SQL Server instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Alternative Windows credentials for exporting Linked Servers and Credentials. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER WithReplace
        If this switch is used, databases are restored from backup using WITH REPLACE. This is useful if you want to stage some complex file paths.

    .PARAMETER NoRecovery
        If this switch is used, databases will be left in the No Recovery state to enable further backups to be added.

    .PARAMETER AzureCredential
        Optional AzureCredential to connect to blob storage holding the backups

    .PARAMETER IncludeDbMasterKey
        Exports the db master key then logs into the server to copy it to the $Path

    .PARAMETER Exclude
        Exclude one or more objects to export

        Databases
        Logins
        AgentServer
        Credentials
        LinkedServers
        SpConfigure
        CentralManagementServer
        DatabaseMail
        SysDbUserObjects
        SystemTriggers
        BackupDevices
        Audits
        Endpoints
        ExtendedEvents
        PolicyManagement
        ResourceGovernor
        ServerAuditSpecifications
        CustomErrors
        ServerRoles
        AvailabilityGroups
        ReplicationSettings
        OleDbProvider

    .PARAMETER BatchSeparator
        Batch separator for scripting output. "GO" by default based on (Get-DbatoolsConfigValue -FullName 'formatting.batchseparator').

    .PARAMETER NoPrefix
        If this switch is used, the scripts will not include prefix information containing creator and datetime.

    .PARAMETER ExcludePassword
        If this switch is used, the scripts will not include passwords for Credentials, LinkedServers or Logins.

    .PARAMETER ScriptingOption
        Add scripting options to scripting output for all objects except Registered Servers and Extended Events.

    .PARAMETER Force
        Overwrite files in the location specified by -Path. Note: The Server Name is used when creating the folder structure.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Export
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaInstance

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlserver\instance

        All databases, logins, job objects and sp_configure options will be exported from sqlserver\instance to an automatically generated folder name in Documents. For example, %userprofile%\Documents\DbatoolsExport\sqldev1$sqlcluster-20201108140000

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Exclude Databases, Logins -Path C:\dr\sqlcluster

        Exports everything but logins and database restore scripts to a folder such as C:\dr\sqlcluster\sqldev1$sqlcluster-20201108140000

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Path C:\servers\ -NoPrefix

        Exports everything to a folder such as C:\servers\sqldev1$sqlcluster-20201108140000 but scripts will not include prefix information.

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Path C:\servers\ -Force

        Exports everything to a folder such as C:\servers\sqldev1$sqlcluster and will overwrite/refresh existing files in that folder. Note: when the -Force param is used the generated folder name will not include a timestamp. This supports the use case of running Export-DbaInstance on a schedule and writing to the same dir each time.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [Alias("FilePath")]
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [switch]$NoRecovery,
        [string]$AzureCredential,
        [switch]$IncludeDbMasterKey,
        [ValidateSet('AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider')]
        [string[]]$Exclude,
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'formatting.batchseparator'),
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOption,
        [switch]$NoPrefix = $false,
        [switch]$ExcludePassword,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path

        if (-not $ScriptingOption) {
            $ScriptingOption = New-DbaScriptingOption
        }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date

        $eol = [System.Environment]::NewLine
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            $stepCounter = 0
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Force) {
                # when the caller requests to overwrite existing scripts we won't add the dynamic timestamp to the folder name, so that a pre-existing location can be overwritten.
                $exportPath = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))"
            } else {
                $timeNow = (Get-Date -UFormat (Get-DbatoolsConfigValue -FullName 'formatting.uformat'))
                $exportPath = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))-$timeNow"
            }

            # Ensure the export dir exists.
            if (-not (Test-Path $exportPath)) {
                try {
                    $null = New-Item -ItemType Directory -Path $exportPath -Force -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                    return
                }
            }

            if ($Exclude -notcontains 'SpConfigure') {
                Write-Message -Level Verbose -Message "Exporting SQL Server Configuration"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL Server Configuration"
                Export-DbaSpConfigure -SqlInstance $server -FilePath "$exportPath\sp_configure.sql"
                # no call to Get-ChildItem because Export-DbaSpConfigure does it
            }

            if ($Exclude -notcontains 'CustomErrors') {
                Write-Message -Level Verbose -Message "Exporting custom errors (user defined messages)"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting custom errors (user defined messages)"
                $null = Get-DbaCustomError -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\customererrors.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\customererrors.sql"
            }

            if ($Exclude -notcontains 'ServerRoles') {
                Write-Message -Level Verbose -Message "Exporting server roles"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting server roles"
                $null = Get-DbaServerRole -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\serverroles.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\serverroles.sql"
            }

            if ($Exclude -notcontains 'Credentials') {
                Write-Message -Level Verbose -Message "Exporting SQL credentials"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL credentials"
                $null = Export-DbaCredential -SqlInstance $server -Credential $Credential -FilePath "$exportPath\credentials.sql" -ExcludePassword:$ExcludePassword
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\credentials.sql"
            }

            if ($Exclude -notcontains 'Logins') {
                Write-Message -Level Verbose -Message "Exporting logins"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting logins"
                Export-DbaLogin -SqlInstance $server -FilePath "$exportPath\logins.sql" -ExcludePassword:$ExcludePassword -NoPrefix:$NoPrefix -WarningAction SilentlyContinue
                # no call to Get-ChildItem because Export-DbaLogin does it
            }

            if ($Exclude -notcontains 'DatabaseMail') {
                Write-Message -Level Verbose -Message "Exporting database mail"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database mail"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaDbMailConfig -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailAccount -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailProfile -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailServer -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix

                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\dbmail.sql"
            }

            if ($Exclude -notcontains 'CentralManagementServer') {
                Write-Message -Level Verbose -Message "Exporting Central Management Server"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Central Management Server"
                $outputFilePath = "$exportPath\regserver.xml"
                $null = Export-DbaRegServer -SqlInstance $server -FilePath $outputFilePath -Overwrite:$Force
                Get-ChildItem -ErrorAction Ignore -Path $outputFilePath
            }

            if ($Exclude -notcontains 'BackupDevices') {
                Write-Message -Level Verbose -Message "Exporting Backup Devices"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Backup Devices"
                $null = Get-DbaBackupDevice -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\backupdevices.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\backupdevices.sql"
            }

            if ($Exclude -notcontains 'LinkedServers') {
                Write-Message -Level Verbose -Message "Exporting linked servers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting linked servers"
                Export-DbaLinkedServer -SqlInstance $server -FilePath "$exportPath\linkedservers.sql" -Credential $Credential -ExcludePassword:$ExcludePassword
                # no call to Get-ChildItem because Export-DbaLinkedServer does it
            }

            if ($Exclude -notcontains 'SystemTriggers') {
                Write-Message -Level Verbose -Message "Exporting System Triggers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting System Triggers"
                $null = Get-DbaInstanceTrigger -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\servertriggers.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $triggers = Get-Content -Path "$exportPath\servertriggers.sql" -Raw -ErrorAction Ignore
                if ($triggers) {
                    $triggers = $triggers.ToString() -replace 'CREATE TRIGGER', "$BatchSeparator$($eol)CREATE TRIGGER"
                    $triggers = $triggers.ToString() -replace 'ENABLE TRIGGER', "$BatchSeparator$($eol)ENABLE TRIGGER"
                    $null = $triggers | Set-Content -Path "$exportPath\servertriggers.sql" -Force
                    Get-ChildItem -ErrorAction Ignore -Path "$exportPath\servertriggers.sql"
                }
            }

            if ($Exclude -notcontains 'Databases') {
                Write-Message -Level Verbose -Message "Exporting database restores"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database restores"
                Get-DbaDbBackupHistory -SqlInstance $server -Last -WarningAction SilentlyContinue | Restore-DbaDatabase -SqlInstance $server -NoRecovery:$NoRecovery -WithReplace -OutputScriptOnly -WarningAction SilentlyContinue -AzureCredential $AzureCredential | Out-File -FilePath "$exportPath\databases.sql"
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\databases.sql"
            }

            if ($Exclude -notcontains 'Audits') {
                Write-Message -Level Verbose -Message "Exporting Audits"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Audits"
                $null = Get-DbaInstanceAudit -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\audits.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\audits.sql"
            }

            if ($Exclude -notcontains 'ServerAuditSpecifications') {
                Write-Message -Level Verbose -Message "Exporting Server Audit Specifications"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Server Audit Specifications"
                $null = Get-DbaInstanceAuditSpecification -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\auditspecs.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\auditspecs.sql"
            }

            if ($Exclude -notcontains 'Endpoints') {
                Write-Message -Level Verbose -Message "Exporting Endpoints"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Endpoints"
                $null = Get-DbaEndpoint -SqlInstance $server | Where-Object IsSystemObject -EQ $false | Export-DbaScript -FilePath "$exportPath\endpoints.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\endpoints.sql"
            }

            if ($Exclude -notcontains 'PolicyManagement' -and $PSVersionTable.PSEdition -eq "Core") {
                Write-Message -Level Verbose -Message "Skipping Policy Management -- not supported by PowerShell Core"
            }
            if ($Exclude -notcontains 'PolicyManagement' -and $PSVersionTable.PSEdition -ne "Core") {
                Write-Message -Level Verbose -Message "Exporting Policy Management"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Policy Management"

                $outputFilePath = "$exportPath\policymanagement.sql"
                $scriptText = ""
                $policyObjects = @()

                # the policy objects are a different set of classes and are not compatible with the SMO object usage in Export-DbaScript

                $policyObjects += Get-DbaPbmCondition -SqlInstance $server
                $policyObjects += Get-DbaPbmObjectSet -SqlInstance $server
                $policyObjects += Get-DbaPbmPolicy -SqlInstance $server

                foreach ($policyObject in $policyObjects) {
                    $tsqlScript = $policyObject.ScriptCreate()
                    $scriptText += $tsqlScript.GetScript() + "$eol$BatchSeparator$eol$eol"
                }

                Set-Content -Path $outputFilePath -Value $scriptText

                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\policymanagement.sql"
            }

            if ($Exclude -notcontains 'ResourceGovernor') {
                Write-Message -Level Verbose -Message "Exporting Resource Governor"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Resource Governor"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaRgClassifierFunction -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgResourcePool -SqlInstance $server | Where-Object Name -NotIn 'default', 'internal' | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgWorkloadGroup -SqlInstance $server | Where-Object Name -NotIn 'default', 'internal' | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaResourceGovernor -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\resourcegov.sql"
            }

            if ($Exclude -notcontains 'ExtendedEvents') {
                Write-Message -Level Verbose -Message "Exporting Extended Events"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Extended Events"
                $null = Get-DbaXESession -SqlInstance $server | Export-DbaXESession -FilePath "$exportPath\extendedevents.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\extendedevents.sql"
            }

            if ($Exclude -notcontains 'AgentServer') {
                Write-Message -Level Verbose -Message "Exporting job server"

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting job server"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaAgentJobCategory -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentOperator -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentAlert -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentProxy -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentSchedule -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentJob -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\sqlagent.sql"
            }

            if ($Exclude -notcontains 'ReplicationSettings') {
                Write-Message -Level Verbose -Message "Exporting replication settings"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting replication settings"

                try {
                    $null = Export-DbaRepServerSetting -SqlInstance $instance -SqlCredential $SqlCredential -FilePath "$exportPath\replication.sql" -EnableException
                    Get-ChildItem -ErrorAction Ignore -Path "$exportPath\replication.sql"
                } catch {
                    Write-Message -Level Verbose -Message "Replication failed, skipping"
                }
            }

            if ($Exclude -notcontains 'SysDbUserObjects') {
                Write-Message -Level Verbose -Message "Exporting user objects in system databases (this can take a minute)."
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting user objects in system databases (this can take a minute)."
                $outputFile = "$exportPath\userobjectsinsysdbs.sql"
                $sysDbUserObjects = Export-DbaSysDbUserObject -SqlInstance $server -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption -PassThru
                Set-Content -Path $outputFile -Value $sysDbUserObjects # this approach is needed because -Append is used in Export-DbaSysDbUserObject.ps1
                Get-ChildItem -ErrorAction Ignore -Path $outputFile
            }

            if ($Exclude -notcontains 'AvailabilityGroups') {
                Write-Message -Level Verbose -Message "Exporting availability group"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting availability groups"
                $null = Get-DbaAvailabilityGroup -SqlInstance $server -WarningAction SilentlyContinue | Export-DbaScript -FilePath "$exportPath\AvailabilityGroups.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\AvailabilityGroups.sql"
            }

            if ($Exclude -notcontains 'OleDbProvider') {
                Write-Message -Level Verbose -Message "Exporting OLEDB Providers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting OLEDB Providers"
                $null = Get-DbaOleDbProvider -SqlInstance $server -WarningAction SilentlyContinue | Export-DbaScript -FilePath "$exportPath\OleDbProvider.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\oledbprovider.sql"
            }


            Write-Progress -Activity "Performing Instance Export for $instance" -Completed
        }
    }
    end {
        $totalTime = ($elapsed.Elapsed.toString().Split(".")[0])
        Write-Message -Level Verbose -Message "SQL Server export complete."
        Write-Message -Level Verbose -Message "Export started: $started"
        Write-Message -Level Verbose -Message "Export completed: $(Get-Date)"
        Write-Message -Level Verbose -Message "Total Elapsed time: $totalTime"
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD85ic2SxDcvKUr
# avTP5ldYj2EKzQBraDBQKA76Wq18i6CCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBBXl+f3//4XgV4b6iFCp4GaNFJAFntNqMw
# Sc4g8OYqKjANBgkqhkiG9w0BAQEFAASCAQAj1u0WgVslfGrCLU5vFiJ6jjvMcGQu
# Sgb8xlMNAKU9bmIlpmpiMQOaol1PMYtGzWwjVKgflOb3sgiNpAnZbNBTyY6qIWU+
# EP2XR/RtYtsE5fHuNLSOH8jIoVPMOXKhc69XKtYPo88JZczu47YZgxeicuBgv6bC
# JKqtfmmvVa6uOi/UIz13XV+t+kMNJtEBFJiegdudCxRANd015JrFD8x6Sbi6f95v
# x8KI6nWSQSSgUccAfI3wbfiOxPf5/Q6ZUoejRzO4OFovULatJtH5B1Gqs4uQZmG2
# H0Dnqy1mGXmqbpEzE7BkJwc+6hYP/bNFMpxTKocOxeAJnU6QbnjpuZQ1oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI0M1owLwYJKoZIhvcNAQkEMSIEIKqL1P05
# THhRg79Tcamn8qJsCyeUegsz46QK3ANWFKzuMA0GCSqGSIb3DQEBAQUABIICAKq0
# 3oxj8oS/YCr7pAfx1zMQqNH3LFK8OUywin1cxL3J2t9Y5XqNMLsujDsxNgtWiyLU
# QvCZk25OSAlhgSwcukS+RQNp9KcJX9CJZs6yvHMyRb0i43HAmn/cz7xw52xRLHdW
# MR+LP4S0iaumSwtmx7E8enNC4Xh0XtK2gpk/UNGojY2ZLlzPxboBICJPybhROLhD
# teGLBrhX9M+rA8s5IPE4+pcjEJtSB+EJesAxje3iBvshU1/5LI/EaCYunyJgMIVN
# wooLmaF4j8w45fiNHYuA2rlAUWEsBeCTgDQjmujTW5ueuYlWEB4A/m9E7J6C6CMx
# iavye9BqxbafeLuIfUP7zjiCjZMOsYB1lYUnCDftZsKtrqqfzI+Dg+6OvV/B5KRF
# E3O8CwKKMGTNu303Y/ivcd9AE9+D2iCn/N+RXqGyLFJ62XvHHextSPrjMpQf7H7X
# +LEn72OiLVYJvfD3An8BxihaSuq/W46g/iSCT6Cw0+Vavn5IyQaVoxrG3XGkKNgo
# buIg2TDmVbjedDI6wJ5KaeWRSFPg2A+1zr+eh/dXCBG/hQqExSyexX3CMac5Fn/8
# 6vATvvVRdwcLBc428j8LCsD9tQGcUgfWq6EVneVcTeis6+P+JrIqdoEXW0Xm3sWk
# KH9wffCEn6DJCakZ/ZL71ZMFAJHD3yAWbE1EKu4m
# SIG # End signature block
