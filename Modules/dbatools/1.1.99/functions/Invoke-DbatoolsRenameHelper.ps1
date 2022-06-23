function Invoke-DbatoolsRenameHelper {
    <#
    .SYNOPSIS
        Older dbatools command names have been changed. This script helps keep up.

    .DESCRIPTION
        Older dbatools command names have been changed. This script helps keep up.

    .PARAMETER InputObject
        A piped in object from Get-ChildItem

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .NOTES
        Tags: Module
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbatoolsRenameHelper

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\ps\*.ps1 -Recurse | Invoke-DbatoolsRenameHelper

        Checks to see if any ps1 file in C:\temp\ps matches an old command name.
        If so, then the command name within the text is updated and the resulting changes are written to disk in UTF-8.

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\ps\*.ps1 -Recurse | Invoke-DbatoolsRenameHelper -Encoding Ascii -WhatIf

        Shows what would happen if the command would run. If the command would run and there were matches,
        the resulting changes would be written to disk as Ascii encoded.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileInfo[]]$InputObject,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$EnableException
    )
    begin {
        $paramrenames = @{
            ExcludeAllSystemDb = 'ExcludeSystem'
            ExcludeAllUserDb   = 'ExcludeUser'
            'Invoke-Sqlcmd2'   = 'Invoke-DbaQuery'
            NetworkShare       = 'SharedPath'
            NoDatabases        = 'ExcludeDatabases'
            NoDisabledJobs     = 'ExcludeDisabledJobs'
            NoJobs             = 'ExcludeJobs'
            NoJobSteps         = 'ExcludeJobSteps'
            NoQueryTextColumn  = 'ExcludeQueryTextColumn'
            NoSystem           = 'ExcludeSystemLogins'
            NoSystemDb         = 'ExcludeSystem'
            NoSystemLogins     = 'ExcludeSystemLogins'
            NoSystemObjects    = 'ExcludeSystemObjects'
            NoSystemSpid       = 'ExcludeSystemSpids'
            UseLastBackups     = 'UseLastBackup'
            PasswordExpiration = 'PasswordExpirationEnabled'
            PasswordPolicy     = 'PasswordPolicyEnforced'
            ServerInstance     = 'SqlInstance'
        }

        $commandrenames = @{
            'Find-DbaDuplicateIndex'            = 'Find-DbaDbDuplicateIndex'
            'Find-DbaDisabledIndex'             = 'Find-DbaDbDisabledIndex'
            'Add-DbaRegisteredServer'           = 'Add-DbaRegServer'
            'Add-DbaRegisteredServerGroup'      = 'Add-DbaRegServerGroup'
            'Backup-DbaDatabaseCertificate'     = 'Backup-DbaDbCertificate'
            'Backup-DbaDatabaseMasterKey'       = 'Backup-DbaDbMasterKey'
            'Clear-DbaSqlConnectionPool'        = 'Clear-DbaConnectionPool'
            'Connect-DbaServer'                 = 'Connect-DbaInstance'
            'Copy-DbaAgentCategory'             = 'Copy-DbaAgentJobCategory'
            'Copy-DbaAgentProxyAccount'         = 'Copy-DbaAgentProxy'
            'Copy-DbaAgentSharedSchedule'       = 'Copy-DbaAgentSchedule'
            'Copy-DbaCentralManagementServer'   = 'Copy-DbaRegServer'
            'Copy-DbaDatabaseAssembly'          = 'Copy-DbaDbAssembly'
            'Copy-DbaDatabaseMail'              = 'Copy-DbaDbMail'
            'Copy-DbaExtendedEvent'             = 'Copy-DbaXESession'
            'Copy-DbaQueryStoreConfig'          = 'Copy-DbaDbQueryStoreOption'
            'Copy-DbaSqlDataCollector'          = 'Copy-DbaDataCollector'
            'Copy-DbaSqlPolicyManagement'       = 'Copy-DbaPolicyManagement'
            'Copy-DbaSqlServerAgent'            = 'Copy-DbaAgentServer'
            'Copy-DbaTableData'                 = 'Copy-DbaDbTableData'
            'Copy-SqlAgentCategory'             = 'Copy-DbaAgentJobCategory'
            'Copy-SqlAlert'                     = 'Copy-DbaAgentAlert'
            'Copy-SqlAudit'                     = 'Copy-DbaInstanceAudit'
            'Copy-SqlAuditSpecification'        = 'Copy-DbaInstanceAuditSpecification'
            'Copy-SqlBackupDevice'              = 'Copy-DbaBackupDevice'
            'Copy-SqlCentralManagementServer'   = 'Copy-DbaRegServer'
            'Copy-SqlCredential'                = 'Copy-DbaCredential'
            'Copy-SqlCustomError'               = 'Copy-DbaCustomError'
            'Copy-SqlDatabase'                  = 'Copy-DbaDatabase'
            'Copy-SqlDatabaseAssembly'          = 'Copy-DbaDbAssembly'
            'Copy-SqlDatabaseMail'              = 'Copy-DbaDbMail'
            'Copy-SqlDataCollector'             = 'Copy-DbaDataCollector'
            'Copy-SqlEndpoint'                  = 'Copy-DbaEndpoint'
            'Copy-SqlExtendedEvent'             = 'Copy-DbaXESession'
            'Copy-SqlJob'                       = 'Copy-DbaAgentJob'
            'Copy-SqlJobServer'                 = 'Copy-SqlInstanceAgent'
            'Copy-SqlLinkedServer'              = 'Copy-DbaLinkedServer'
            'Copy-SqlLogin'                     = 'Copy-DbaLogin'
            'Copy-SqlOperator'                  = 'Copy-DbaAgentOperator'
            'Copy-SqlPolicyManagement'          = 'Copy-DbaPolicyManagement'
            'Copy-SqlProxyAccount'              = 'Copy-DbaAgentProxy'
            'Copy-SqlResourceGovernor'          = 'Copy-DbaResourceGovernor'
            'Copy-SqlInstanceAgent'             = 'Copy-DbaAgentServer'
            'Copy-SqlInstanceTrigger'           = 'Copy-DbaInstanceTrigger'
            'Copy-SqlSharedSchedule'            = 'Copy-DbaAgentSchedule'
            'Copy-SqlSpConfigure'               = 'Copy-DbaSpConfigure'
            'Copy-SqlSsisCatalog'               = 'Copy-DbaSsisCatalog'
            'Copy-SqlSysDbUserObjects'          = 'Copy-DbaSysDbUserObject'
            'Copy-SqlUserDefinedMessage'        = 'Copy-SqlCustomError'
            'Expand-DbaTLogResponsibly'         = 'Expand-DbaDbLogFile'
            'Expand-SqlTLogResponsibly'         = 'Expand-DbaDbLogFile'
            'Export-DbaDacpac'                  = 'Export-DbaDacPackage'
            'Export-DbaRegisteredServer'        = 'Export-DbaRegServer'
            'Export-SqlLogin'                   = 'Export-DbaLogin'
            'Export-SqlSpConfigure'             = 'Export-DbaSpConfigure'
            'Export-SqlUser'                    = 'Export-DbaUser'
            'Find-DbaDatabaseGrowthEvent'       = 'Find-DbaDbGrowthEvent'
            'Find-SqlDuplicateIndex'            = 'Find-DbaDbDuplicateIndex'
            'Find-SqlUnusedIndex'               = 'Find-DbaDbUnusedIndex'
            'Get-DbaRegServerName'              = 'Get-DbaRegServer'
            'Get-DbaConfig'                     = 'Get-DbatoolsConfig'
            'Get-DbaConfigValue'                = 'Get-DbatoolsConfigValue'
            'Get-DbaDatabaseAssembly'           = 'Get-DbaDbAssembly'
            'Get-DbaDatabaseCertificate'        = 'Get-DbaDbCertificate'
            'Get-DbaDatabaseEncryption'         = 'Get-DbaDbEncryption'
            'Get-DbaDatabaseFile'               = 'Get-DbaDbFile'
            'Get-DbaDatabaseFreeSpace'          = 'Get-DbaDbSpace'
            'Get-DbaDatabaseMasterKey'          = 'Get-DbaDbMasterKey'
            'Get-DbaDatabasePartitionFunction'  = 'Get-DbaDbPartitionFunction'
            'Get-DbaDatabasePartitionScheme'    = 'Get-DbaDbPartitionScheme'
            'Get-DbaDatabaseSnapshot'           = 'Get-DbaDbSnapshot'
            'Get-DbaDatabaseSpace'              = 'Get-DbaDbSpace'
            'Get-DbaDatabaseState'              = 'Get-DbaDbState'
            'Get-DbaDatabaseUdf'                = 'Get-DbaDbUdf'
            'Get-DbaDatabaseUser'               = 'Get-DbaDbUser'
            'Get-DbaDatabaseView'               = 'Get-DbaDbView'
            'Get-DbaDbQueryStoreOptions'        = 'Get-DbaDbQueryStoreOption'
            'Get-DbaDistributor'                = 'Get-DbaRepDistributor'
            'Get-DbaInstance'                   = 'Connect-DbaInstance'
            'Get-DbaJobCategory'                = 'Get-DbaAgentJobCategory'
            'Get-DbaLog'                        = 'Get-DbaErrorLog'
            'Get-DbaLogShippingError'           = 'Get-DbaDbLogShipError'
            'Get-DbaOrphanUser'                 = 'Get-DbaDbOrphanUser'
            'Get-DbaPolicy'                     = 'Get-DbaPbmPolicy'
            'Get-DbaQueryStoreConfig'           = 'Get-DbaDbQueryStoreOption'
            'Get-DbaRegisteredServerGroup'      = 'Get-DbaRegServerGroup'
            'Get-DbaRegisteredServerStore'      = 'Get-DbaRegServerStore'
            'Get-DbaRestoreHistory'             = 'Get-DbaDbRestoreHistory'
            'Get-DbaRoleMember'                 = 'Get-DbaDbRoleMember'
            'Get-DbaSqlBuildReference'          = 'Get-DbaBuild'
            'Get-DbaSqlFeature'                 = 'Get-DbaFeature'
            'Get-DbaSqlInstanceProperty'        = 'Get-DbaInstanceProperty'
            'Get-DbaSqlInstanceUserOption'      = 'Get-DbaInstanceUserOption'
            'Get-DbaSqlManagementObject'        = 'Get-DbaManagementObject'
            'Get-DbaSqlModule'                  = 'Get-DbaModule'
            'Get-DbaSqlProductKey'              = 'Get-DbaProductKey'
            'Get-DbaSqlRegistryRoot'            = 'Get-DbaRegistryRoot'
            'Get-DbaSqlService'                 = 'Get-DbaService'
            'Get-DbaTable'                      = 'Get-DbaDbTable'
            'Get-DbaTraceFile'                  = 'Get-DbaTrace'
            'Get-DbaUserLevelPermission'        = 'Get-DbaUserPermission'
            'Get-DbaXEventSession'              = 'Get-DbaXESession'
            'Get-DbaXEventSessionTarget'        = 'Get-DbaXESessionTarget'
            'Get-DiskSpace'                     = 'Get-DbaDiskSpace'
            'Get-SqlMaxMemory'                  = 'Get-DbaMaxMemory'
            'Get-SqlRegisteredServerName'       = 'Get-DbaRegServer'
            'Get-SqlInstanceKey'                = 'Get-DbaProductKey'
            'Import-DbaCsvToSql'                = 'Import-DbaCsv'
            'Import-DbaRegisteredServer'        = 'Import-DbaRegServer'
            'Import-SqlSpConfigure'             = 'Import-DbaSpConfigure'
            'Install-SqlWhoIsActive'            = 'Install-DbaWhoIsActive'
            'Invoke-DbaCmd'                     = 'Invoke-DbaQuery'
            'Invoke-DbaDatabaseClone'           = 'Invoke-DbaDbClone'
            'Invoke-DbaDatabaseShrink'          = 'Invoke-DbaDbShrink'
            'Invoke-DbaDatabaseUpgrade'         = 'Invoke-DbaDbUpgrade'
            'Invoke-DbaLogShipping'             = 'Invoke-DbaDbLogShipping'
            'Invoke-DbaLogShippingRecovery'     = 'Invoke-DbaDbLogShipRecovery'
            'Invoke-DbaSqlQuery'                = 'Invoke-DbaQuery'
            'Move-DbaRegisteredServer'          = 'Move-DbaRegServer'
            'Move-DbaRegisteredServerGroup'     = 'Move-DbaRegServerGroup'
            'New-DbaDatabaseCertificate'        = 'New-DbaDbCertificate'
            'New-DbaDatabaseMasterKey'          = 'New-DbaDbMasterKey'
            'New-DbaDatabaseSnapshot'           = 'New-DbaDbSnapshot'
            'New-DbaPublishProfile'             = 'New-DbaDacProfile'
            'New-DbaSqlConnectionString'        = 'New-DbaConnectionString'
            'New-DbaSqlConnectionStringBuilder' = 'New-DbaConnectionStringBuilder'
            'New-DbaSqlDirectory'               = 'New-DbaDirectory'
            'Out-DbaDataTable'                  = 'ConvertTo-DbaDataTable'
            'Publish-DbaDacpac'                 = 'Publish-DbaDacPackage'
            'Read-DbaXEventFile'                = 'Read-DbaXEFile'
            'Register-DbaConfig'                = 'Register-DbatoolsConfig'
            'Remove-DbaDatabaseCertificate'     = 'Remove-DbaDbCertificate'
            'Remove-DbaDatabaseMasterKey'       = 'Remove-DbaDbMasterKey'
            'Remove-DbaDatabaseSnapshot'        = 'Remove-DbaDbSnapshot'
            'Remove-DbaOrphanUser'              = 'Remove-DbaDbOrphanUser'
            'Remove-DbaRegisteredServer'        = 'Remove-DbaRegServer'
            'Remove-DbaRegisteredServerGroup'   = 'Remove-DbaRegServerGroup'
            'Remove-SqlDatabaseSafely'          = 'Remove-DbaDatabaseSafely'
            'Remove-SqlOrphanUser'              = 'Remove-DbaDbOrphanUser'
            'Repair-DbaOrphanUser'              = 'Repair-DbaDbOrphanUser'
            'Repair-SqlOrphanUser'              = 'Repair-DbaDbOrphanUser'
            'Reset-SqlAdmin'                    = 'Reset-DbaAdmin'
            'Reset-SqlSaPassword'               = 'Reset-SqlAdmin'
            'Restart-DbaSqlService'             = 'Restart-DbaService'
            'Restore-DbaDatabaseCertificate'    = 'Restore-DbaDbCertificate'
            'Restore-DbaDatabaseSnapshot'       = 'Restore-DbaDbSnapshot'
            'Restore-HallengrenBackup'          = 'Restore-SqlBackupFromDirectory'
            'Set-DbaConfig'                     = 'Set-DbatoolsConfig'
            'Get-DbaBackupHistory'              = 'Get-DbaDbBackupHistory'
            'Set-DbaDatabaseOwner'              = 'Set-DbaDbOwner'
            'Set-DbaDatabaseState'              = 'Set-DbaDbState'
            'Set-DbaDbQueryStoreOptions'        = 'Set-DbaDbQueryStoreOption'
            'Set-DbaJobOwner'                   = 'Set-DbaAgentJobOwner'
            'Set-DbaQueryStoreConfig'           = 'Set-DbaDbQueryStoreOption'
            'Set-DbaTempDbConfiguration'        = 'Set-DbaTempdbConfig'
            'Set-SqlMaxMemory'                  = 'Set-DbaMaxMemory'
            'Set-SqlTempDbConfiguration'        = 'Set-DbaTempdbConfig'
            'Show-DbaDatabaseList'              = 'Show-DbaDbList'
            'Show-SqlDatabaseList'              = 'Show-DbaDbList'
            'Show-SqlMigrationConstraint'       = 'Test-SqlMigrationConstraint'
            'Show-SqlInstanceFileSystem'        = 'Show-DbaInstanceFileSystem'
            'Show-SqlWhoIsActive'               = 'Invoke-DbaWhoIsActive'
            'Start-DbaSqlService'               = 'Start-DbaService'
            'Start-SqlMigration'                = 'Start-DbaMigration'
            'Stop-DbaSqlService'                = 'Stop-DbaService'
            'Sync-DbaSqlLoginPermission'        = 'Sync-DbaLoginPermission'
            'Sync-SqlLoginPermissions'          = 'Sync-DbaLoginPermission'
            'Test-DbaDatabaseCollation'         = 'Test-DbaDbCollation'
            'Test-DbaDatabaseCompatibility'     = 'Test-DbaDbCompatibility'
            'Test-DbaDatabaseOwner'             = 'Test-DbaDbOwner'
            'Test-DbaDbVirtualLogFile'          = 'Measure-DbaDbVirtualLogFile'
            'Test-DbaFullRecoveryModel'         = 'Test-DbaDbRecoveryModel'
            'Test-DbaJobOwner'                  = 'Test-DbaAgentJobOwner'
            'Test-DbaLogShippingStatus'         = 'Test-DbaDbLogShipStatus'
            'Test-DbaRecoveryModel'             = 'Test-DbaDbRecoveryModel'
            'Test-DbaSqlBuild'                  = 'Test-DbaBuild'
            'Test-DbaSqlManagementObject'       = 'Test-DbaManagementObject'
            'Test-DbaSqlPath'                   = 'Test-DbaPath'
            'Test-DbaTempDbConfiguration'       = 'Test-DbaTempdbConfig'
            'Test-DbaValidLogin'                = 'Test-DbaWindowsLogin'
            'Test-DbaVirtualLogFile'            = 'Measure-DbaDbVirtualLogFile'
            'Test-SqlConnection'                = 'Test-DbaConnection'
            'Test-SqlDiskAllocation'            = 'Test-DbaDiskAllocation'
            'Test-SqlMigrationConstraint'       = 'Test-DbaMigrationConstraint'
            'Test-SqlNetworkLatency'            = 'Test-DbaNetworkLatency'
            'Test-SqlPath'                      = 'Test-DbaPath'
            'Test-SqlTempDbConfiguration'       = 'Test-DbaTempdbConfig'
            'Update-DbaSqlServiceAccount'       = 'Update-DbaServiceAccount'
            'Watch-DbaXEventSession'            = 'Watch-DbaXESession'
            'Watch-SqlDbLogin'                  = 'Watch-DbaDbLogin'
            'Add-DbaCmsRegServer'               = 'Add-DbaRegServer'
            'Add-DbaCmsRegServerGroup'          = 'Add-DbaRegServerGroup'
            'Copy-DbaCmsRegServer'              = 'Copy-DbaRegServer'
            'Export-DbaCmsRegServer'            = 'Export-DbaRegServer'
            'Get-DbaCmsRegistryRoot'            = 'Get-DbaRegistryRoot'
            'Get-DbaCmsRegServer'               = 'Get-DbaRegServer'
            'Get-DbaCmsRegServerGroup'          = 'Get-DbaRegServerGroup'
            'Get-DbaCmsRegServerStore'          = 'Get-DbaRegServerStore'
            'Import-DbaCmsRegServer'            = 'Import-DbaRegServer'
            'Move-DbaCmsRegServer'              = 'Move-DbaRegServer'
            'Move-DbaCmsRegServerGroup'         = 'Move-DbaRegServerGroup'
            'Remove-DbaCmsRegServer'            = 'Remove-DbaRegServer'
            'Remove-DbaCmsRegServerGroup'       = 'Remove-DbaRegServerGroup'
            'Copy-DbaServerAuditSpecification'  = 'Copy-DbaInstanceAuditSpecification'
            'Copy-DbaServerAudit'               = 'Copy-DbaInstanceAudit'
            'Copy-DbaServerTrigger'             = 'Copy-DbaInstanceTrigger'
            'Test-DbaServerName'                = 'Test-DbaInstanceName'
            'Test-DbaInstanceName'              = 'Repair-DbaInstanceName'
            'Get-DbaServerTrigger'              = 'Get-DbaInstanceTrigger'
            'Get-DbaServerAudit'                = 'Get-DbaInstanceAudit'
            'Get-DbaServerAuditSpecification'   = 'Get-DbaInstanceAuditSpecification'
            'Get-DbaServerInstallDate'          = 'Get-DbaInstanceInstallDate'
            'Show-DbaServerFileSystem'          = 'Show-DbaInstanceFileSystem'
            'Install-DbaWatchUpdate'            = 'Install-DbatoolsWatchUpdate'
            'Uninstall-DbaWatchUpdate'          = 'Uninstall-DbatoolsWatchUpdate'
        }
    }
    process {
        foreach ($fileobject in $InputObject) {
            $file = $fileobject.FullName

            foreach ($name in $paramrenames.GetEnumerator()) {
                if ((Select-String -Pattern $name.Key -Path $file)) {
                    if ($Pscmdlet.ShouldProcess($file, "Replacing $($name.Key) with $($name.Value)")) {
                        $content = (Get-Content -Path $file -Raw).Replace($name.Key, $name.Value).Trim()
                        Set-Content -Path $file -Encoding $Encoding -Value $content
                        [pscustomobject]@{
                            Path         = $file
                            Pattern      = $name.Key
                            ReplacedWith = $name.Value
                        }
                    }
                }
            }

            foreach ($name in $commandrenames.GetEnumerator()) {
                if ((Select-String -Pattern "\b$($name.Key)\b" -Path $file)) {
                    if ($Pscmdlet.ShouldProcess($file, "Replacing $($name.Key) with $($name.Value)")) {
                        $content = ((Get-Content -Path $file -Raw) -Replace "\b$($name.Key)\b", $name.Value).Trim()
                        Set-Content -Path $file -Encoding $Encoding -Value $content
                        [pscustomobject]@{
                            Path         = $file
                            Pattern      = $name.Key
                            ReplacedWith = $name.Value
                        }
                    }
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUEprDiKO1uoODmlUKcsb5dsm4
# w/2gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFK64qYvBgPXSW3QyStOTZ/aGFVVKMA0G
# CSqGSIb3DQEBAQUABIIBACeapAuV0wAAJEMEpF2zQ5yIzSCUnCAH/GnwZLPzgrhe
# Um0UlN1rn8Fm4OssJcVIIQgjIrS4B9kcNSuzwtziHFnarGbFlUbVOevPq7ouulRG
# kqX1ZELCm2W0bv83hK4z8IWKbmaYkELHwIy90VxlAObcXfPMdsG8tLzKyYJkz11g
# StRenR2B7JRqnvRSigSmKHTq+xgJwtG9hta0PsxaEdj8brmrcNQKVASlpbqbe3fs
# ai6OY/fdUdCTmPMEiRxJRF2AQ4QkavZlLhkJ8uP4n35CR4kulEFDur42oltaGE67
# 2HrqshzGuDS4caU290Wx6izojir+2dofc3BxzOPc+VWhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU3WjAvBgkqhkiG9w0BCQQxIgQg2/QyJaJtjD/2kJmwC8Bw
# rZnIU0hrClfcDpgOiXazKbswDQYJKoZIhvcNAQEBBQAEggIAXExilh/0t5DHxyaX
# bDsnpYt8OKcWR4Ve//3VbIKVK1l6yUqt3v/u7BnXL7RF2J63ByKHXNo7F4KuNUp7
# sOdUAaY7nleCEz2VwwDTDlxDhz4wJT+lkdP5Bge7wNk/mw5kDzGZtqfzcTrmutmu
# 9XKht1f+O1NeK2CSeNg7BOGrEV6vIqrUr9tm7IOqyafbemSvHa9PXliQCYPphcG5
# DIYxOjUuQB7D266qeTA+R9mHRKbylQx6z0YgD+jHlxlJItk7SiuThMPJ4pEI6rI5
# 4nlg6V44c1Kxj0lPm7Kp3m1LP9fuVX92LFN0OIwYixPQOY4jdE5JzOEXF5XMq3Vp
# jtpt3ZhVlF12YS1NzkAzRHjmUz0WTlyrmli/femsL+h2f3tvEkCDx04w+QcQqddU
# n0Jzay+3nHk2HmeIpOPvXUpGiP/cCEPrmD0wGhh1X3QLGS1Zd8Wu4M9mE1x3cq+m
# 0FbUvWFOC4v/skySk8gW1FkkBzHLbNprzw2AbFIvlrcGi+lILZn5wmHC+a1em37b
# 2YDxI73YkNoQoMCVh/MC/NqOEPpnI4RRcrI9N5HcroaK/V0x/T8CWvBDOZ4CKqDl
# aAjgc4C95/L9MmfiT3BO5Y/62I0xB6Em5D3uB+uVX168D/drF/xTS6+mFNZrqnwv
# uehq4U4vXIvvs5a0a7tmzMmTqv8=
# SIG # End signature block
