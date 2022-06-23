function Test-DbaDiskSpeed {
    <#
    .SYNOPSIS
        Obtains I/O statistics based on the DMV sys.dm_io_virtual_file_stats:

        https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql

    .DESCRIPTION
        Obtains I/O statistics based on the DMV sys.dm_io_virtual_file_stats:

        https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql

        This command uses a query from Rich Benner
        https://github.com/RichBenner/PersonalCode/blob/master/Disk_Speed_Check.sql

        ...and also based on further adaptations referenced at https://github.com/dataplat/dbatools/issues/6551#issue-623216718

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AggregateBy
        Specify the level of aggregation for the statistics. The available options are 'File' (the default), 'Database', and 'Disk'.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Performance
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaDiskSpeed

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008, sqlserver2012

        Tests how disks are performing on sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -Database tempdb

        Tests how disks storing tempdb files on sql2008 are performing.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "File" -Database tempdb

        Returns the statistics aggregated to the file level. This is the default aggregation level if the -AggregateBy param is omitted. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "Database"

        Returns the statistics aggregated to the database/disk level. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "Disk"

        Returns the statistics aggregated to the disk level. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> $results = @(instance1, instance2) | Test-DbaDiskSpeed

        Returns the statistics for instance1 and instance2 as part of a pipeline command

    .EXAMPLE
        PS C:\> $databases = @('master', 'model')
        $results = Test-DbaDiskSpeed -SqlInstance sql2019 -Database $databases

        Returns the statistics for more than one database specified.

    .EXAMPLE
        PS C:\> $excludedDatabases = @('master', 'model')
        $results = Test-DbaDiskSpeed -SqlInstance sql2019 -ExcludeDatabase $excludedDatabases

        Returns the statistics for databases other than the exclusions specified.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet('Database', 'Disk', 'File')]
        [string]$AggregateBy = 'File',
        [switch]$EnableException
    )

    begin {

        $sql = $null

        # Consolidating the common SQL to hopefully make the maintenance easier. The various scenarios are enabled by uncommenting specific lines at runtime.
        $selectList =
        "SELECT
            SERVERPROPERTY('MachineName')                                                                               AS ComputerName
        ,   ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')                                                       AS InstanceName
        ,   SERVERPROPERTY('ServerName')                                                                                AS SqlInstance
        --DATABASE-SELECT,  DB_NAME(a.database_id)                                                                      AS [Database]
        --FILE-ALL,   CAST(((a.size_on_disk_bytes/1024)/1024.0)/1024 AS DECIMAL(10,2))                                  AS [SizeGB]
        --FILE-WINDOWS, RIGHT(b.physical_name, CHARINDEX('\', REVERSE(b.physical_name)) -1)                             AS [FileName]
        --FILE-LINUX, RIGHT(b.physical_name, CHARINDEX('/', REVERSE(b.physical_name)) -1)                               AS [FileName]
        --FILE-ALL,   a.file_id                                                                                         AS [FileID]
        --FILE-ALL,   CASE WHEN a.file_id = 2 THEN 'Log' ELSE 'Data' END                                                AS [FileType]
        --DATABASE-OR-DISK, a.DiskLocation                                                                              AS DiskLocation
        --FILE-WINDOWS,   UPPER(SUBSTRING(b.physical_name, 1, 2))                                                       AS DiskLocation
        --FILE-LINUX, SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1) AS DiskLocation
        ,   a.num_of_reads                                                                                              AS [Reads]
        ,   CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END            AS [AverageReadStall]
        ,   CASE
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 10 THEN 'Very Good'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 20 THEN 'OK'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 50 THEN 'Slow, Needs Attention'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END >= 50 THEN 'Serious I/O Bottleneck'
            END                                                                                                         AS [ReadPerformance]
        ,   a.num_of_writes                                                                                             AS [Writes]
        ,   CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/a.num_of_writes AS INT) END           AS [AverageWriteStall]
        ,   CASE
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 10 THEN 'Very Good'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 20 THEN 'OK'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 50 THEN 'Slow, Needs Attention'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END >= 50 THEN 'Serious I/O Bottleneck'
            END                                                                                                         AS [WritePerformance]
        ,   CASE
                WHEN (a.num_of_reads = 0 AND a.num_of_writes = 0) THEN NULL
                ELSE (a.io_stall/(a.num_of_reads + a.num_of_writes))
            END                                                                                                         AS [Avg Overall Latency]
        ,   CASE
                WHEN a.num_of_reads = 0 THEN NULL
                ELSE (a.num_of_bytes_read/a.num_of_reads)
            END                                                                                                         AS [Avg Bytes/Read]
        ,   CASE
                WHEN a.num_of_writes = 0 THEN NULL
                ELSE (a.num_of_bytes_written/a.num_of_writes)
            END                                                                                                         AS [Avg Bytes/Write]
        ,   CASE
                WHEN (a.num_of_reads = 0 AND a.num_of_writes = 0) THEN NULL
                ELSE ((a.num_of_bytes_read + a.num_of_bytes_written)/(a.num_of_reads + a.num_of_writes))
            END                                                                                                         AS [Avg Bytes/Transfer]"

        if ($AggregateBy -eq 'File') {
            $sql = "$selectList
                    FROM sys.dm_io_virtual_file_stats (NULL, NULL) a
                    JOIN sys.master_files b
                        ON a.file_id = b.file_id
                        AND a.database_id = b.database_id"

        } elseif ($AggregateBy -in ('Database', 'Disk')) {
            $sql = "$selectList
                    FROM
                    (
                        SELECT
                        --WINDOWS UPPER(SUBSTRING(b.physical_name, 1, 2))                                                           AS DiskLocation
                        --LINUX SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1)   AS DiskLocation
                        ,   SUM(a.num_of_reads)                                                                                     AS num_of_reads
                        ,   SUM(a.io_stall_read_ms)                                                                                 AS io_stall_read_ms
                        ,   SUM(a.num_of_writes)                                                                                    AS num_of_writes
                        ,   SUM(a.io_stall_write_ms)                                                                                AS io_stall_write_ms
                        ,   SUM(a.num_of_bytes_read)                                                                                AS num_of_bytes_read
                        ,   SUM(a.num_of_bytes_written)                                                                             AS num_of_bytes_written
                        ,   SUM(a.io_stall)                                                                                         AS io_stall
                        --DATABASE-GROUPBY, a.database_id                                                                           AS database_id
                        FROM sys.dm_io_virtual_file_stats (NULL, NULL) a
                        JOIN sys.master_files b
                            ON a.file_id = b.file_id
                            AND a.database_id = b.database_id
                        GROUP BY
                            --DATABASE-GROUPBYa.database_id,
                            --WINDOWS UPPER(SUBSTRING(b.physical_name, 1, 2))
                            --LINUX SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1)
                    ) AS a"
        }

        if ($Database -or $ExcludeDatabase) {
            if ($Database) {
                $where = " where db_name(a.database_id) in ('$($Database -join "','")') "
            }
            if ($ExcludeDatabase) {
                $where = " where db_name(a.database_id) not in ('$($ExcludeDatabase -join "','")') "
            }
            $sql += $where
        }

        $sql += " ORDER BY (a.num_of_reads + a.num_of_writes) DESC"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sqlToRun = $sql

            # At runtime uncomment the relevant pieces in the SQL
            if ($AggregateBy -eq 'File') {

                $sqlToRun = $sqlToRun.replace("--DATABASE-SELECT", "").replace("--FILE-ALL", "")

                if ($server.HostPlatform -eq "Linux") {
                    $sqlToRun = $sqlToRun.replace("--FILE-LINUX", "")
                } else {
                    $sqlToRun = $sqlToRun.replace("--FILE-WINDOWS", "")
                }

            } elseif ($AggregateBy -in ('Database', 'Disk')) {

                $sqlToRun = $sqlToRun.replace("--DATABASE-OR-DISK", "")

                if ($server.HostPlatform -eq "Linux") {
                    $sqlToRun = $sqlToRun.replace("--LINUX", "")
                } else {
                    $sqlToRun = $sqlToRun.replace("--WINDOWS", "")
                }

                if ($AggregateBy -eq 'Database') {
                    $sqlToRun = $sqlToRun.replace("--DATABASE-SELECT", "").replace("--DATABASE-GROUPBY", "")
                }
            }

            Write-Message -Level Debug -Message "Executing $sqlToRun"
            $server.Query("$sqlToRun")
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUKeatSRfTQ8PFYFUqCQMUkog1
# k26gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFAJ80bdLKpayFhFNuEjsH6XlkwzmMA0G
# CSqGSIb3DQEBAQUABIIBAGjUVJAdYTBK+xlJpZQmUhsM++L840072hqNrrwa22AP
# uxP1pbUHnhkmRRG8lvTmC11hKe8CClmz0R8hEnVklep0wSwy1ni7fXkF8QEywL02
# ugzMwhwr53TXMN4XmgPEhn1e8YHUMbzOFhmcZHPX1kiluzVsCMeJCWqOQy6ZGJbu
# jjUBGhkCQ+0Y49gn8rdSA06t+ElVVMQWNZvUIy0Swn18roTOpesKwn+osXYaO8S/
# /SXYKHi8MBJVgidCz2BuSQS//rRRz24NS2WLDUvdmxXQfE8qZNtd6QDqBFUWmisG
# AluDWPLw3+yDPe+JBfbF3uagRFq7rdL8xb+7SBQ129WhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDI5WjAvBgkqhkiG9w0BCQQxIgQgZXh/5/LAKcvqXxOuuMa8
# 4qLTxITGp1Y6ls6+CgpWeEQwDQYJKoZIhvcNAQEBBQAEggIAk1kYveNLSrsCLBiQ
# UqHt9AefkS/AtvRmdWe+SUdX3lCpvL9wIdgcMO+IaohHNSXRFFd3A2xw0044hi83
# tzza+oMNYdknGAhl+vMNi0DoKTeaIGx7B19+EtXw149W5xVtkW4wsui8/BUTHzn9
# FELHGcWZKjYPb9i1y0R9JxThKmIurLWYBkjZl4NFIZ3u3VC3NYAVBIgzJV4CCeTv
# 76PH8jm7q6KshtHNH0ahnhy7MOeZ24kqj546u3PhhH9FQrLtNeuOvCzVvZStlrs0
# CUDd+PNzi9g1pnYfddFtym9YPnbZvwNdv9/SDgb4d6LPTVL2WfUGRacrj1AUiwBY
# e1jsIgyLIxG3YRcM7IP/vUR4zfapLfy5M2/xH1Fvm5PJ+T5VBAnBN53iNLMupNWl
# 4UGilXJ/aan7oMGtDWZyiKpohN+xWeVCZBhfePUUNpMxjF7ke5XJWyovKbNCjk1w
# bJbbPUrnd1Q5O7VCISzqBAJHIDWWntROrPW/7jlFVwa/AfSpcuuh8j7wYTPBAnfW
# bKbxMhcQmi/xNxqMVDDCgpI9LIHWkpTYIh8zuWmT275y2TVBNO6Hkr8piPyp+fMZ
# Py/0NJpOyZ/5fNB2XGLt1deNepqCxB/Njh5WtgNDo6iGy/ICD/I7F048GHh4FLxe
# orjfVemFsekPiYl1wHaW2xTSYb0=
# SIG # End signature block
