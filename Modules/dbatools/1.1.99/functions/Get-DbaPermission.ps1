function Get-DbaPermission {
    <#
    .SYNOPSIS
        Get a list of Server and Database level permissions

    .DESCRIPTION
        Retrieves a list of permissions

        Permissions link principals to securables.
        Principals exist on Windows, Instance and Database level.
        Securables exist on Instance and Database level.
        A permission state can be GRANT, DENY or REVOKE.
        The permission type can be SELECT, CONNECT, EXECUTE and more.
        The CONTROL permission is also returned for dbo users, db_owners, and schema owners.
        To see server-level implicit permissions via fixed roles run the following command: Get-DbaServerRole -SqlInstance serverName | Select-Object *

        See https://msdn.microsoft.com/en-us/library/ms191291.aspx for more information

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER IncludeServerLevel
        If this switch is enabled, information about Server Level Permissions will be output.

    .PARAMETER ExcludeSystemObjects
        If this switch is enabled, permissions on system securables will be excluded.

    .PARAMETER EnableException
        If this switch is enabled exceptions will be thrown to the caller, which will need to perform its own exception processing. Otherwise, the function will try to catch the exception, interpret it and provide a friendly error message.

    .NOTES
        Tags: Permissions, Instance, Database, Security
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPermission

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987

        Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987 | Format-Table -AutoSize

        Returns a formatted table displaying Server, Database, permission state, permission type, grantee, granteetype, securable and securabletype.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987 -ExcludeSystemObjects -IncludeServerLevel

        Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable
        in all databases and on the server level, but not on system securables.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance sql2016 -Database master

        Returns a custom object with permissions for the master database.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeServerLevel,
        [switch]$ExcludeSystemObjects,
        [switch]$EnableException
    )
    begin {
        if ($ExcludeSystemObjects) {
            $ExcludeSystemObjectssql = "WHERE major_id > 0 "
        }

        $ServPermsql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                       ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                       SERVERPROPERTY('ServerName') AS SqlInstance
                        , [Database] = ''
                        , [PermState] = state_desc
                        , [PermissionName] = permission_name
                        , [SecurableType] = COALESCE(o.type_desc,sp.class_desc)
                        , [Securable] = CASE    WHEN class = 100 THEN @@SERVERNAME
                                                WHEN class = 105 THEN OBJECT_NAME(major_id)
                                                ELSE OBJECT_NAME(major_id)
                                                END
                        , [Grantee] = SUSER_NAME(grantee_principal_id)
                        , [GranteeType] = pr.type_desc
                        , [revokeStatement] = 'REVOKE ' + permission_name + ' ' + COALESCE(OBJECT_NAME(major_id),'') + ' FROM [' + SUSER_NAME(grantee_principal_id) + ']'
                        , [grantStatement] = 'GRANT ' + permission_name + ' ' + COALESCE(OBJECT_NAME(major_id),'') + ' TO [' + SUSER_NAME(grantee_principal_id) + ']'
                            + CASE WHEN sp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
                    FROM sys.server_permissions sp
                        JOIN sys.server_principals pr ON pr.principal_id = sp.grantee_principal_id
                        LEFT OUTER JOIN sys.all_objects o ON o.object_id = sp.major_id

                    $ExcludeSystemObjectssql

                    UNION ALL
                    SELECT    SERVERPROPERTY('MachineName') AS ComputerName
                            , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName
                            , SERVERPROPERTY('ServerName') AS SqlInstance
                            , [database] = ''
                            , [PermState] = 'GRANT'
                            , [PermissionName] = pb.[permission_name]
                            , [SecurableType] = pb.class_desc
                            , [Securable] = @@SERVERNAME
                            , [Grantee] = spr.name
                            , [GranteeType] = spr.type_desc
                            , [revokestatement] = ''
                            , [grantstatement] = ''
                    FROM sys.server_principals AS spr
                    INNER JOIN sys.fn_builtin_permissions('SERVER') AS pb ON
                        spr.[name]='bulkadmin' AND pb.[permission_name]='ADMINISTER BULK OPERATIONS'
                        OR
                        spr.[name]='dbcreator' AND pb.[permission_name]='CREATE ANY DATABASE'
                        OR
                        spr.[name]='diskadmin' AND pb.[permission_name]='ALTER RESOURCES'
                        OR
                        spr.[name]='processadmin' AND pb.[permission_name] IN ('ALTER ANY CONNECTION', 'ALTER SERVER STATE')
                        OR
                        spr.[name]='sysadmin' AND pb.[permission_name]='CONTROL SERVER'
                        OR
                        spr.[name]='securityadmin' AND pb.[permission_name]='ALTER ANY LOGIN'
                        OR
                        spr.[name]='serveradmin'  AND pb.[permission_name] IN ('ALTER ANY ENDPOINT', 'ALTER RESOURCES','ALTER SERVER STATE', 'ALTER SETTINGS','SHUTDOWN', 'VIEW SERVER STATE')
                        OR
                        spr.[name]='setupadmin' AND pb.[permission_name]='ALTER ANY LINKED SERVER'
                    WHERE spr.[type]='R'
                    ;"

        $DBPermsql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS SqlInstance
                    , [Database] = DB_NAME()
                    , [PermState] = state_desc
                    , [PermissionName] = permission_name
                    , [SecurableType] = COALESCE(o.type_desc,dp.class_desc)
                    , [Securable] = CASE    WHEN class = 0 THEN DB_NAME()
                                            WHEN class = 1 THEN ISNULL(s.name + '.','')+OBJECT_NAME(major_id)
                                            WHEN class = 3 THEN SCHEMA_NAME(major_id)
                                            WHEN class = 6 THEN SCHEMA_NAME(t.schema_id)+'.' + t.name
                                            END
                    , [Grantee] = USER_NAME(grantee_principal_id)
                    , [GranteeType] = pr.type_desc
                    , [RevokeStatement] = CASE WHEN class = 3 THEN 'REVOKE ' + permission_name + ' ON Schema::[' + isnull(SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT,'') + '] FROM [' + USER_NAME(grantee_principal_id) +']'
                                            ELSE 'REVOKE ' + permission_name + ' ON [' + isnull(schema_name(o.schema_id) COLLATE DATABASE_DEFAULT+'].[','')+OBJECT_NAME(major_id)+ '] FROM [' + USER_NAME(grantee_principal_id) +']'
                                            END
                    , [GrantStatement] = CASE WHEN class = 3 THEN 'GRANT ' + permission_name + ' ON Schema::' + isnull(SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT,'') + '] TO [' + USER_NAME(grantee_principal_id) + ']'
                                            ELSE 'GRANT ' + permission_name + ' ON [' + isnull(schema_name(o.schema_id) COLLATE DATABASE_DEFAULT+'].[','')+OBJECT_NAME(major_id)+ '] TO [' + USER_NAME(grantee_principal_id) + ']'
                                            END
                        + CASE WHEN dp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
                    FROM sys.database_permissions dp
                    JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                    LEFT OUTER JOIN sys.all_objects o ON (o.object_id = dp.major_id AND dp.class NOT IN (0, 3))
                    LEFT OUTER JOIN sys.schemas s ON s.schema_id = o.schema_id
                    LEFT OUTER JOIN sys.types t on t.user_type_id = dp.major_id

                $ExcludeSystemObjectssql

                UNION ALL
                SELECT    SERVERPROPERTY('MachineName') AS ComputerName
                        , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName
                        , SERVERPROPERTY('ServerName') AS SqlInstance
                        , [database] = DB_NAME()
                        , [PermState] = ''
                        , [PermissionName] = p.[permission_name]
                        , [SecurableType] = p.class_desc
                        , [Securable] = DB_NAME()
                        , [Grantee] = dp.name
                        , [GranteeType] = dp.type_desc
                        , [revokestatement] = ''
                        , [grantstatement] = ''
                FROM sys.database_principals AS dp
                INNER JOIN sys.fn_builtin_permissions('DATABASE') AS p ON
                    dp.[name]='db_accessadmin' AND p.[permission_name] IN ('ALTER ANY USER', 'CREATE SCHEMA')
                    OR
                    dp.[name]='db_backupoperator' AND p.[permission_name] IN ('BACKUP DATABASE', 'BACKUP LOG', 'CHECKPOINT')
                    OR
                    dp.[name] IN ('db_datareader', 'db_denydatareader') AND p.[permission_name]='SELECT'
                    OR
                    dp.[name] IN ('db_datawriter', 'db_denydatawriter') AND p.[permission_name] IN ('INSERT', 'DELETE', 'UPDATE')
                    OR
                    dp.[name]='db_ddladmin' AND
                    p.[permission_name] IN ('ALTER ANY ASSEMBLY', 'ALTER ANY ASYMMETRIC KEY',
                                            'ALTER ANY CERTIFICATE', 'ALTER ANY CONTRACT',
                                            'ALTER ANY DATABASE DDL TRIGGER', 'ALTER ANY DATABASE EVENT',
                                            'NOTIFICATION', 'ALTER ANY DATASPACE', 'ALTER ANY FULLTEXT CATALOG',
                                            'ALTER ANY MESSAGE TYPE', 'ALTER ANY REMOTE SERVICE BINDING',
                                            'ALTER ANY ROUTE', 'ALTER ANY SCHEMA', 'ALTER ANY SERVICE',
                                            'ALTER ANY SYMMETRIC KEY', 'CHECKPOINT', 'CREATE AGGREGATE',
                                            'CREATE DEFAULT', 'CREATE FUNCTION', 'CREATE PROCEDURE',
                                            'CREATE QUEUE', 'CREATE RULE', 'CREATE SYNONYM', 'CREATE TABLE',
                                            'CREATE TYPE', 'CREATE VIEW', 'CREATE XML SCHEMA COLLECTION',
                                            'REFERENCES')
                    OR
                    dp.[name]='db_owner' AND p.[permission_name]='CONTROL'
                    OR
                    dp.[name]='db_securityadmin' AND p.[permission_name] IN ('ALTER ANY APPLICATION ROLE', 'ALTER ANY ROLE', 'CREATE SCHEMA', 'VIEW DEFINITION')

                WHERE dp.[type]='R'
                    AND dp.is_fixed_role=1
                UNION ALL -- include the dbo user
                SELECT
                    [ComputerName]		= SERVERPROPERTY('MachineName')
                ,	[InstanceName]		= ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,	[SqlInstance]		= SERVERPROPERTY('ServerName')
                ,	[database]			= DB_NAME()
                ,	[PermState]			= ''
                ,	[PermissionName]	= 'CONTROL'
                ,	[SecurableType]		= 'DATABASE'
                ,	[Securable]			= DB_NAME()
                ,	[Grantee]			= SUSER_SNAME(owner_sid)
                ,	[GranteeType]		= 'DATABASE OWNER (dbo user)'
                ,	[revokestatement]	= ''
                ,	[grantstatement]	= ''
                FROM
                    sys.databases
                WHERE
                    name = DB_NAME()
                UNION ALL -- include the users with the db_owner role
                SELECT
                    [ComputerName]		= SERVERPROPERTY('MachineName')
                ,	[InstanceName]		= ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,	[SqlInstance]		= SERVERPROPERTY('ServerName')
                ,	[database]			= DB_NAME()
                ,	[PermState]			= ''
                ,	[PermissionName]	= 'CONTROL'
                ,	[SecurableType]		= 'DATABASE'
                ,	[Securable]			= DB_NAME()
                ,	[Grantee]			= databaseUser.name
                ,	[GranteeType]		= 'DATABASE OWNER (db_owner role)'
                ,	[revokestatement]	= ''
                ,	[grantstatement]	= ''
                FROM
                (
                    SELECT
                        member_principal_id
                    FROM
                        sys.database_role_members AS roleMembers
                    INNER JOIN
                        sys.database_principals AS roleFilter
                            ON roleMembers.role_principal_id = roleFilter.principal_id
                            AND roleFilter.name = 'db_owner'
                ) dbOwner
                INNER JOIN
                    sys.database_principals AS databaseUser
                        ON dbOwner.member_principal_id = databaseUser.principal_id
                WHERE
                    databaseUser.name <> 'dbo'
                UNION ALL -- include the schema owners
                SELECT
                    [ComputerName]		= SERVERPROPERTY('MachineName')
                ,	[InstanceName]		= ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,	[SqlInstance]		= SERVERPROPERTY('ServerName')
                ,	[database]			= DB_NAME()
                ,	[PermState]			= ''
                ,	[PermissionName]	= 'CONTROL'
                ,	[SecurableType]		= 'SCHEMA'
                ,	[Securable]			= name
                ,	[Grantee]			= USER_NAME(principal_id)
                ,	[GranteeType]		= 'SCHEMA OWNER'
                ,	[revokestatement]	= ''
                ,	[grantstatement]	= ''
                FROM
                    sys.schemas
                WHERE
                    name NOT IN (SELECT name FROM sys.database_principals WHERE type = 'R')
                AND name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')
                ;"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($IncludeServerLevel) {
                Write-Message -Level Debug -Message "T-SQL: $ServPermsql"
                $server.Query($ServPermsql)
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance."

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db is not accessible. Skipping database."
                    Continue
                }

                Write-Message -Level Debug -Message "T-SQL: $DBPermsql"
                try {
                    $db.ExecuteWithResults($DBPermsql).Tables.Rows
                } catch {
                    Stop-Function -Message "Failure executing against $($db.Name) on $instance" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUbphtW8kLk/AvkHlcpZpr3Ex0
# hpagghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFKjcV2Aykxy20n551pf4iO2HJksvMA0G
# CSqGSIb3DQEBAQUABIIBAC02mvbv+Yxmg9ZgLjiQIrwO0w+ZxV+JNMGIhLRqZKY4
# EEGksZa/288cnQDdwRLWkZAJjxIjLocF72VTdjz/ZBepsKyRe0r9NJQBRtqC5ECi
# fHUbryADCAT7c2nX+uQf02XoU+QInkQd0sbA4r6Wsib+GnBPxt/ULe9ANma5A1hv
# jT5gqY/fljjWb0eLvybK06whZq5NzSL5CWBfexmLdgWZvNP+bT22uiD4c6jVuNAz
# p57naejLRW9tc1BCYdDtWl4GD3ww9xg4sduV12H9h3XXGDoQKq+W5NnfOtEoVT5A
# wmj3F/6SEKfPTPm4B7Vl/pthHgiIzyQxjysjMYyTeaihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzQyWjAvBgkqhkiG9w0BCQQxIgQgeue3wMF8RTlvSuKZunIz
# a1cgCiUx9fw3s/7TLd3gFiYwDQYJKoZIhvcNAQEBBQAEggIAFixS8giTmW1BlUqV
# UoVaAEUorCNI9E4KzG+hRxUrmfXohd5xKG+fVcs8JpORdT72dBd+SIzQ6ZP4Jq/L
# lm7OaZVcY7UtLR7tHQzfJzs7H27yB4N67PXTDzrnOeNqeaiQKfrKFChj4MmZTRT6
# eKhrnkgxOCo0fqd1EQbXednKqibek+bW0wNdCqN/kI/rscBmNAOhOXumUjgWqmSV
# zr4iefcKeybWrZxiC7/5YbPTQabxNgqdBDnt5+DsY/KzcWKmtg6F5saVO4M2ezI6
# ov0C2AANaRxDasYXYQpY0nN4G+0Zf8gRHLfx4TW+KQJA5lnH5D0IKOa/qXKhx77Q
# /kQz9ADYL3GOKgAOruD/iUcxhN+Y1PqQ09BXb7uTUbzylcRD4bbOXjeZtqfdnbOA
# rXyM/GQw0LVg4vGiD5tT8dHLuIZsqAbw1bz4uL1ydMY1euvO8+UePQtJQihtpbO8
# +PFK5E4rZIuiVP/pt6dTdcKVlkFKeklPA0hiOVeb3PX6Cz3bdAA05r245nF9te1b
# tPmbboE47HjkxMe98AHwim6VQM8wB+RXAcmSHTlCivfodwjbk/UKmqz/dhB0bYiL
# vwgunqKAsyINzbFICHmCZMXGAw1DMByDlG5zwG9wxZjrmllSXjvZDRxpnQDkjFVT
# gLCg5S1HQfnIfBxMYR2DUF/FOqY=
# SIG # End signature block
