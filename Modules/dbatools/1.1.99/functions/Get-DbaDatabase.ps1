function Get-DbaDatabase {
    <#
    .SYNOPSIS
        Gets SQL Database information for each database that is present on the target instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaDatabase command gets SQL database information for each database that is present on the target instance(s) of
        SQL Server. If the name of the database is provided, the command will return only the specific database information.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER ExcludeUser
        If this switch is enabled, only databases which are not User databases will be processed.

        This parameter cannot be used with -ExcludeSystem.

    .PARAMETER ExcludeSystem
        If this switch is enabled, only databases which are not System databases will be processed.

        This parameter cannot be used with -ExcludeUser.

    .PARAMETER Status
        Specifies one or more database statuses to filter on. Only databases in the status(es) listed will be returned. Valid options for this parameter are 'Emergency', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', and 'Suspect'.

    .PARAMETER Access
        Filters databases returned by their access type. Valid options for this parameter are 'ReadOnly' and 'ReadWrite'. If omitted, no filtering is performed.

    .PARAMETER Owner
        Specifies one or more database owners. Only databases owned by the listed owner(s) will be returned.

    .PARAMETER Encrypted
        If this switch is enabled, only databases which have Transparent Data Encryption (TDE) enabled will be returned.

    .PARAMETER RecoveryModel
        Filters databases returned by their recovery model. Valid options for this parameter are 'Full', 'Simple', and 'BulkLogged'.

    .PARAMETER NoFullBackup
        If this switch is enabled, only databases without a full backup recorded by SQL Server will be returned. This will also indicate which of these databases only have CopyOnly full backups.

    .PARAMETER NoFullBackupSince
        Only databases which haven't had a full backup since the specified DateTime will be returned.

    .PARAMETER NoLogBackup
        If this switch is enabled, only databases without a log backup recorded by SQL Server will be returned.

    .PARAMETER NoLogBackupSince
        Only databases which haven't had a log backup since the specified DateTime will be returned.

    .PARAMETER IncludeLastUsed
        If this switch is enabled, the last used read & write times for each database will be returned. This data is retrieved from sys.dm_db_index_usage_stats which is reset when SQL Server is restarted.

    .PARAMETER OnlyAccessible
        If this switch is enabled, only accessible databases are returned (huge speedup in SMO enumeration)

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com | Klaas Vandenberghe (@PowerDbaKlaas) | Simone Bizzotto ( @niphlod )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDatabase

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost

        Returns all databases on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -ExcludeUser

        Returns only the system databases on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -ExcludeSystem

        Returns only the user databases on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> 'localhost','sql2016' | Get-DbaDatabase

        Returns databases on multiple instances piped into the function.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress -RecoveryModel full,Simple

        Returns only the user databases in Full or Simple recovery model from SQL Server instance SQL1\SQLExpress.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress -Status Normal

        Returns only the user databases with status 'normal' from SQL Server instance SQL1\SQLExpress.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress -IncludeLastUsed

        Returns the databases from SQL Server instance SQL1\SQLExpress and includes the last used information
        from the sys.dm_db_index_usage_stats DMV.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -ExcludeDatabase model,master

        Returns all databases except master and model from SQL Server instances SQL1\SQLExpress and SQL2.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -Encrypted

        Returns only databases using TDE from SQL Server instances SQL1\SQLExpress and SQL2.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -Access ReadOnly

        Returns only read only databases from SQL Server instances SQL1\SQLExpress and SQL2.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL2,SQL3 -Database OneDB,OtherDB

        Returns databases 'OneDb' and 'OtherDB' from SQL Server instances SQL2 and SQL3 if databases by those names exist on those instances.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [Alias("SystemDbOnly", "NoUserDb", "ExcludeAllUserDb")]
        [switch]$ExcludeUser,
        [Alias("UserDbOnly", "NoSystemDb", "ExcludeAllSystemDb")]
        [switch]$ExcludeSystem,
        [string[]]$Owner,
        [switch]$Encrypted,
        [ValidateSet('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect')]
        [string[]]$Status = @('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect'),
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$Access,
        [ValidateSet('Full', 'Simple', 'BulkLogged')]
        [string[]]$RecoveryModel = @('Full', 'Simple', 'BulkLogged'),
        [switch]$NoFullBackup,
        [datetime]$NoFullBackupSince,
        [switch]$NoLogBackup,
        [datetime]$NoLogBackupSince,
        [switch]$EnableException,
        [switch]$IncludeLastUsed,
        [switch]$OnlyAccessible
    )

    begin {

        if ($ExcludeUser -and $ExcludeSystem) {
            Stop-Function -Message "You cannot specify both ExcludeUser and ExcludeSystem." -Continue -EnableException $EnableException
        }

    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (!$IncludeLastUsed) {
                $dblastused = $null
            } else {
                ## Get last used information from the DMV
                $querylastused = "WITH agg AS
                (
                  SELECT
                       max(last_user_seek) last_user_seek,
                       max(last_user_scan) last_user_scan,
                       max(last_user_lookup) last_user_lookup,
                       max(last_user_update) last_user_update,
                       sd.name dbname
                   FROM
                       sys.dm_db_index_usage_stats, master..sysdatabases sd
                   WHERE
                     database_id = sd.dbid AND database_id > 4
                      group by sd.name
                )
                SELECT
                   dbname,
                   last_read = MAX(last_read),
                   last_write = MAX(last_write)
                FROM
                (
                   SELECT dbname, last_user_seek, NULL FROM agg
                   UNION ALL
                   SELECT dbname, last_user_scan, NULL FROM agg
                   UNION ALL
                   SELECT dbname, last_user_lookup, NULL FROM agg
                   UNION ALL
                   SELECT dbname, NULL, last_user_update FROM agg
                ) AS x (dbname, last_read, last_write)
                GROUP BY
                   dbname
                ORDER BY 1;"
                # put a function around this to enable Pester Testing and also to ease any future changes
                function Invoke-QueryDBlastUsed {
                    $server.Query($querylastused)
                }
                $dblastused = Invoke-QueryDBlastUsed
            }

            if ($ExcludeUser) {
                $DBType = @($true)
            } elseif ($ExcludeSystem) {
                $DBType = @($false)
            } else {
                $DBType = @($false, $true)
            }

            $AccessibleFilter = switch ($OnlyAccessible) {
                $true { @($true) }
                default { @($true, $false) }
            }

            $Readonly = switch ($Access) {
                'Readonly' { @($true) }
                'ReadWrite' { @($false) }
                default { @($true, $false) }
            }
            $Encrypt = switch (Test-Bound -Parameter 'Encrypted') {
                $true { @($true) }
                default { @($true, $false, $null) }
            }
            function Invoke-QueryRawDatabases {
                try {
                    if ($server.isAzure) {
                        $dbquery = "SELECT db.name, db.state, dp.name AS [Owner] FROM sys.databases AS db LEFT JOIN sys.database_principals AS dp ON dp.sid = db.owner_sid"
                        $server.ConnectionContext.ExecuteWithResults($dbquery).Tables
                    } elseif ($server.VersionMajor -eq 8) {
                        $server.Query("
                            SELECT name,
                                CASE DATABASEPROPERTYEX(name,'status')
                                    WHEN 'ONLINE'     THEN 0
                                    WHEN 'RESTORING'  THEN 1
                                    WHEN 'RECOVERING' THEN 2
                                    WHEN 'SUSPECT'    THEN 4
                                    WHEN 'EMERGENCY'  THEN 5
                                    WHEN 'OFFLINE'    THEN 6
                                END AS state,
                                SUSER_SNAME(sid) AS [Owner]
                            FROM master.dbo.sysdatabases
                        ")
                    } else {
                        $server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner] FROM sys.databases")
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }

            $backed_info = Invoke-QueryRawDatabases
            $backed_info = $backed_info | Where-Object {
                ($_.name -in $Database -or !$Database) -and
                ($_.name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                ($_.Owner -in $Owner -or !$Owner) -and
                ($_.state -ne 6 -or !$OnlyAccessible)
            }


            $inputObject = @()
            foreach ($dt in $backed_info) {
                if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                    # Enumeration via $server.Databases[$dt.name] no longer works in azure
                    $inputObject += New-Object Microsoft.SqlServer.Management.Smo.Database $server, $dt.Name
                } else {
                    $inputObject += $server.Databases | Where-Object Name -ceq $dt.name
                }
            }
            if ($server.isAzure) {
                $inputObject = $inputObject |
                    Where-Object {
                        ($_.Name -in $Database -or !$Database) -and
                        ($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                        ($_.Owner -in $Owner -or !$Owner) -and
                        ($_.RecoveryModel -in $RecoveryModel -or !$_.RecoveryModel) -and
                        $_.EncryptionEnabled -in $Encrypt
                    }
            } else {
                $inputObject = $inputObject |
                    Where-Object {
                        ($_.Name -in $Database -or !$Database) -and
                        ($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                        ($_.Owner -in $Owner -or !$Owner) -and
                        $_.ReadOnly -in $Readonly -and
                        $_.IsAccessible -in $AccessibleFilter -and
                        $_.IsSystemObject -in $DBType -and
                        ((Compare-Object @($_.Status.tostring().split(',').trim()) $Status -ExcludeDifferent -IncludeEqual).inputobject.count -ge 1 -or !$status) -and
                        ($_.RecoveryModel -in $RecoveryModel -or !$_.RecoveryModel) -and
                        $_.EncryptionEnabled -in $Encrypt
                    }
            }
            if ($NoFullBackup -or $NoFullBackupSince) {
                $lastFullBackups = Get-DbaDbBackupHistory -SqlInstance $server -LastFull
                $lastCopyOnlyBackups = Get-DbaDbBackupHistory -SqlInstance $server -LastFull -IncludeCopyOnly | Where-Object IsCopyOnly
                if ($NoFullBackupSince) {
                    $lastFullBackups = $lastFullBackups | Where-Object End -gt $NoFullBackupSince
                    $lastCopyOnlyBackups = $lastCopyOnlyBackups | Where-Object End -gt $NoFullBackupSince
                }

                $hasCopyOnly = $inputObject | Compare-DbaCollationSensitiveObject -Property Name -In -Value $lastCopyOnlyBackups.Database -Collation $server.Collation
                $inputObject = $inputObject | Where-Object Name -cne 'tempdb'
                $inputObject = $inputObject | Compare-DbaCollationSensitiveObject -Property Name -NotIn -Value $lastFullBackups.Database -Collation $server.Collation
            }
            if ($NoLogBackup -or $NoLogBackupSince) {
                if (!$NoLogBackupSince) {
                    $NoLogBackupSince = New-Object -TypeName DateTime
                    $NoLogBackupSince = $NoLogBackupSince.AddMilliSeconds(1)
                }
                $inputObject = $inputObject | Where-Object { $_.LastLogBackupDate -lt $NoLogBackupSince -and $_.RecoveryModel -ne 'Simple' }
            }

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'IsAccessible', 'RecoveryModel',
            'LogReuseWaitStatus', 'Size as SizeMB', 'CompatibilityLevel as Compatibility', 'Collation', 'Owner', 'EncryptionEnabled as Encrypted',
            'LastBackupDate as LastFullBackup', 'LastDifferentialBackupDate as LastDiffBackup',
            'LastLogBackupDate as LastLogBackup'

            if ($NoFullBackup -or $NoFullBackupSince) {
                $defaults += ('BackupStatus')
            }
            if ($IncludeLastUsed) {
                # Add Last Used to the default view
                $defaults += ('LastRead as LastIndexRead', 'LastWrite as LastIndexWrite')
            }

            try {
                foreach ($db in $inputObject) {

                    $backupStatus = $null
                    if ($NoFullBackup -or $NoFullBackupSince) {
                        if ($db -cin $hasCopyOnly) {
                            $backupStatus = "Only CopyOnly backups"
                        }
                    }

                    $lastusedinfo = $dblastused | Where-Object { $_.dbname -eq $db.name }
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name BackupStatus -Value $backupStatus
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastRead -Value $lastusedinfo.last_read
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastWrite -Value $lastusedinfo.last_write
                    Select-DefaultView -InputObject $db -Property $defaults
                }
            } catch {
                Stop-Function -ErrorRecord $_ -Target $instance -Message "Failure. Collection may have been modified. If so, please use parens (Get-DbaDatabase ....) | when working with commands that modify the collection such as Remove-DbaDatabase." -Continue
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWBoUwnVCAHVJVxEik50IlRjs
# 0pqgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFE9FuhIdqpDg8AdvXw6EISzYkueIMA0G
# CSqGSIb3DQEBAQUABIIBAB1dtrV1WvRmVp8phL3GwjyrKcBa7OlZlJBj3uzj20Vu
# CdT5lzuaLkarHwv+Sj/9EAlIncRIUZODCs6Exes3TcZQ2xqWOZdIrM7OZEPxmnLd
# hnW+lHMXGrfOA+L48bp5jMIZxJ7zkw/1Anqf+oFRTXwS8kPbpLeOjoAHBsfDuViN
# HXHYeeXltZtcwXSCut4L7nCjXy9dXPUodbYcUtMHeYWMLxMQazOcsuvWikRqyaeT
# edDUETyii4JdU1wZr8cNGWMlSYg1zguCNS1UZbEW0EGKb6+Cmdg5Lh4RcEvECOw7
# y24p55dM14vfLcT23k0JbiMtf876hkplfaFUmqe3ilWhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzI2WjAvBgkqhkiG9w0BCQQxIgQgvFqrSRT6j3twCStSXh10
# ZYrHB9R51fegKTMhMJmbFwAwDQYJKoZIhvcNAQEBBQAEggIAbePWBK3IxH2WyXMi
# iNsyRDmZ9xhBqTwTm9BSqpx6aIPBRjzOXzppsRxChIYqULR52r403GlsAF+tgAB5
# zuYJ5ABt4tphYVKbQ9Fx5vimKhcS+k+77WZOrBryL/4j4XdAi/7z2jmDHeq81+oV
# POpItE1toSoQ80oBwVkM6ppoPiDSpl8MwKVP2rjYuhbTUhcHH8Rn8NzLS+sGedXw
# yhsX0EWnHo1f7/OvpqtMPPsAbwFNiE5XTjkz5TlE2NFEKvRLScyAz4nZBdcw+ubT
# AaXy531YuuIQZ5l0tg9g4JnZla3/bpsrgf9hEkfgJ58r7TbrZmUXEjlXhTeRisu3
# xOJUS2UoB/zqYM5YbPUPZuYGcLjKe12sHcR5AsgS7Z+Fe1ciXZuVSUYqF92SaQL8
# edbL0yHiPRjlx55zhcKiXECVOl4OuGLtDgcpAaSXGkwPFiFwflDJGXny0eNFjnmc
# qHBBCEOIjl7ZNO9LQB641wJwuo/jN6pamB5drB2p4PRFNP1F8PwE7cHGTiuTUzfL
# xgvmMO6Fm0ApsTFWgAc/9u/HlEv1/ZRd2gumDHcBH0Rkn5ToCW3l3vWdxZhs8XiS
# kB+vmK2aYeQxaixZQACCsZFyn9o2iGIq9ue6XQzKTwy3A6jom2pTi18msMI6b6ru
# +mcgcTo8M/LmAY91RBPeBTL0C7M=
# SIG # End signature block
