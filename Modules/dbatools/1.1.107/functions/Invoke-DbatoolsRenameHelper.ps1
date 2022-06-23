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
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCE27fHiVqysgzH
# v4wpbNJu9Yt3XSNn/GbiMHCeX4RnlaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBe8O2XEIi5KOmWT41mRskVyxLFb5PgWDIP
# Coelzm73EzANBgkqhkiG9w0BAQEFAASCAQChctkvs3tclvfei8rDNPMjjNGkxPmU
# Cckl1ITjRodQ1b16mSidtXnXXoNAdjSdX0aRuToXjahTFGcPrLSLpVWeRHAQSiFs
# nUCIS1COMmhUUpehKvWQIEeOiUjuITsNiC2qBVppyni0izwLvQVIA3qEuctSfUFo
# MKhjr86bNDjd0NT3WiTzsB5+lZgDiPVgvLBSxnwPwf5FxmuJmQLX29g2r9XyjvRd
# AQIfvdnC+mXtKwL5mVLZiXhEXiGdXcqxxwpdXEq4clSTreYi5OjbFxjV2uHZIBRP
# d4UtFeAlKmzeEsOw2O0JxjoFDtcm7LW5BYq3Jw2VOs0RoAhcBJsU82G7oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMyOVowLwYJKoZIhvcNAQkEMSIEIGKOnaS4
# UVGiShQhdothzYfAvaRGyllH1qntXa/I6ToZMA0GCSqGSIb3DQEBAQUABIICAJsm
# eoHJIqgvXFw67rWtlhdNyIz9kmGII5ZH9Hlwiu/nOYzKzRV9kqK5+IkF6NUAS0F/
# pqpbHUcnfiOkLSZLCIMHtPCV/T8THATbcwG76mvUyXiPJZIHxtW6G5a3AMkr0ykd
# JYYGA22WqGFBE1n0hp2tDI69wSzUTMXOtRsYUoRxZz26olipr0dcaNxAIFUhwBfn
# R0itg1YwQmBKgADNHwWNk2BnXX8jviLPePhLsbjV3+MHwWTFP6pPo1BKmLqOwDQ4
# foKcgM+h9hbmb2PRWQD7WjBE9YXeIH6YayTMTikatXZktMKBf7LaABX/U5rgEm4C
# MaUfttfSG3WXU4y9e6XzkaJXzPrGA/EK/QsDrDPnu+WFbMmcfa1W+Vq02YtmczDt
# aPMEnYPNDoPj0MFBo1lNKcVw4r+fSZoVQOL8X1jZS4aatQQpAz0Ifs31LCvTV9W6
# owKG2n9BnYCPHqrhzP4ijFje5JGyPqQQYpSDQtXZYafBMz85HAiYxfarwLPT0oJl
# MvRhlwPmA62YDUODpm6u12xGHR4y9bI4arLiU7JdV0mpnEir9E8+KMTpUn3NUiCz
# QZb3njVww0oX5Ot7bPdxKXuwCm9CYDLA1PDJ3ZroC73ZCROtK2XhMHRkSb9mnbD4
# iebRvnFIoOnn4VycwEju0Pi6ojV4t9mQnixEnvl9
# SIG # End signature block
