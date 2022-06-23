function Get-DbaTopResourceUsage {
    <#
    .SYNOPSIS
        Returns the top 20 resource consumers for cached queries based on four different metrics: duration, frequency, IO, and CPU.

    .DESCRIPTION
        Returns the top 20 resource consumers for cached queries based on four different metrics: duration, frequency, IO, and CPU.

        This command is based off of queries provided by Michael J. Swart at http://michaeljswart.com/go/Top20

        Per Michael: "I've posted queries like this before, and others have written many other versions of this query. All these queries are based on sys.dm_exec_query_stats."

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

    .PARAMETER ExcludeSystem
        This will exclude system objects like replication procedures from being returned.

    .PARAMETER Type
        By default, all Types run but you can specify one or more of the following: Duration, Frequency, IO, or CPU

    .PARAMETER Limit
        By default, these query the Top 20 worst offenders (though more than 20 results can be returned if each of the top 20 have more than 1 subsequent result)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Performance, Query
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaTopResourceUsage

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008, sql2012

        Return the 80 (20 x 4 types) top usage results by duration, frequency, IO, and CPU servers for servers sql2008 and sql2012

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008 -Type Duration, Frequency -Database TestDB

        Return the highest usage by duration (top 20) and frequency (top 20) for the TestDB on sql2008

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2016 -Limit 30

        Return the highest usage by duration (top 30) and frequency (top 30) for the TestDB on sql2016

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008, sql2012 -ExcludeSystem

        Return the 80 (20 x 4 types) top usage results by duration, frequency, IO, and CPU servers for servers sql2008 and sql2012 without any System Objects

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2016| Select-Object *

        Return all the columns plus the QueryPlan column

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet("All", "Duration", "Frequency", "IO", "CPU")]
        [string[]]$Type = "All",
        [int]$Limit = 20,
        [switch]$EnableException,
        [switch]$ExcludeSystem
    )

    begin {

        $instancecolumns = " SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, "

        if ($database) {
            $wheredb = " and coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') in ('$($database -join '', '')')"
        }

        if ($ExcludeDatabase) {
            $wherenotdb = " and coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') not in ('$($excludedatabase -join '', '')')"
        }

        if ($ExcludeSystem) {
            $whereexcludesystem = " AND coalesce(object_name(st.objectid, st.dbid), '<none>') NOT LIKE 'sp_MS%' "
        }
        $duration = ";with long_queries as
                        (
                            select top $Limit
                                query_hash,
                                sum(total_elapsed_time) elapsed_time
                            from sys.dm_exec_query_stats
                            where query_hash <> 0x0
                            group by query_hash
                            order by sum(total_elapsed_time) desc
                        )
                        select $instancecolumns
                            coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                            coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                            qs.query_hash as QueryHash,
                            qs.total_elapsed_time / 1000 as TotalElapsedTimeMs,
                            qs.execution_count as ExecutionCount,
                            cast((total_elapsed_time / 1000) / (execution_count + 0.0) as money) as AverageDurationMs,
                            lq.elapsed_time / 1000 as QueryTotalElapsedTimeMs,
                            SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                                (CASE
                                    WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                                    ELSE qs.statement_end_offset
                                    END - qs.statement_start_offset) / 2) as QueryText,
                            qp.query_plan as QueryPlan
                        from sys.dm_exec_query_stats qs
                        join long_queries lq
                            on lq.query_hash = qs.query_hash
                        cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                        cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                        outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                        where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                        order by lq.elapsed_time desc,
                            lq.query_hash,
                            qs.total_elapsed_time desc
                        option (recompile)"

        $frequency = ";with frequent_queries as
                        (
                            select top $Limit
                                query_hash,
                                sum(execution_count) executions
                            from sys.dm_exec_query_stats
                            where query_hash <> 0x0
                            group by query_hash
                            order by sum(execution_count) desc
                        )
                        select $instancecolumns
                            coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                            coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                            qs.query_hash as QueryHash,
                            qs.execution_count as ExecutionCount,
                            executions as QueryTotalExecutions,
                            SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                                (CASE
                                    WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                                    ELSE qs.statement_end_offset
                                    END - qs.statement_start_offset) / 2) as QueryText,
                            qp.query_plan as QueryPlan
                        from sys.dm_exec_query_stats qs
                        join frequent_queries fq
                            on fq.query_hash = qs.query_hash
                        cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                        cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                        outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                        where pa.attribute = 'dbid'  $wheredb $wherenotdb $whereexcludesystem
                        order by fq.executions desc,
                            fq.query_hash,
                            qs.execution_count desc
                        option (recompile)"

        $io = ";with high_io_queries as
                (
                    select top $Limit
                        query_hash,
                        sum(total_logical_reads + total_logical_writes) io
                    from sys.dm_exec_query_stats
                    where query_hash <> 0x0
                    group by query_hash
                    order by sum(total_logical_reads + total_logical_writes) desc
                )
                select $instancecolumns
                    coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                    coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                    qs.query_hash as QueryHash,
                    qs.total_logical_reads + total_logical_writes as TotalIO,
                    qs.execution_count as ExecutionCount,
                    cast((total_logical_reads + total_logical_writes) / (execution_count + 0.0) as money) as AverageIO,
                    io as QueryTotalIO,
                    SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                        (CASE
                            WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                            ELSE qs.statement_end_offset
                            END - qs.statement_start_offset) / 2) as QueryText,
                    qp.query_plan as QueryPlan
                from sys.dm_exec_query_stats qs
                join high_io_queries fq
                    on fq.query_hash = qs.query_hash
                cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                order by fq.io desc,
                    fq.query_hash,
                    qs.total_logical_reads + total_logical_writes desc
                option (recompile)"

        $cpu = ";with high_cpu_queries as
                (
                    select top $Limit
                        query_hash,
                        sum(total_worker_time) cpuTime
                    from sys.dm_exec_query_stats
                    where query_hash <> 0x0
                    group by query_hash
                    order by sum(total_worker_time) desc
                )
                select $instancecolumns
                    coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                    coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                    qs.query_hash as QueryHash,
                    qs.total_worker_time as CpuTime,
                    qs.execution_count as ExecutionCount,
                    cast(total_worker_time / (execution_count + 0.0) as money) as AverageCpuMs,
                    cpuTime as QueryTotalCpu,
                    SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                        (CASE
                            WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                            ELSE qs.statement_end_offset
                            END - qs.statement_start_offset) / 2) as QueryText,
                    qp.query_plan as QueryPlan
                from sys.dm_exec_query_stats qs
                join high_cpu_queries hcq
                    on hcq.query_hash = qs.query_hash
                cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                order by hcq.cpuTime desc,
                    hcq.query_hash,
                    qs.total_worker_time desc
                option (recompile)"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10 -StatementTimeout 0
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Type -in "All", "Duration") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $duration"
                    $server.Query($duration) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for duration." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "Frequency") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $frequency"
                    $server.Query($frequency) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for frequency." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "IO") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $io"
                    $server.Query($io) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for IO." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "CPU") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $cpu"
                    $server.Query($cpu) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for CPU." -ErrorRecord $_ -Target $server -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDzjr1w90F77lPh
# qTe590NHQM6CM3tc246NUPM1S2pqMKCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDDLkmL+qPj2KrdUdrOU4M1/IoOsNcVOMy6
# rB4sFNAKcTANBgkqhkiG9w0BAQEFAASCAQA0qaf5/hbAuRrosUyw1NnRGKVhqJH3
# SdX2rzeszohI8Ke2L/IddU2WQGD4JrZbFPys8PrVH9R1gJ+rpACfdbxuhptd/nXr
# C6CVwwHvW1nS+JHay5w4KqYuKhqjMydI9wlxBoNu5n+pYAflIvmnCV7dohx89s8/
# P7u9OOe5VObcmdMS9mZ260DVnLekOz3dbIVPUw9CdovKCiu9Un6V1GVY8btIvcAI
# B9zYj6Sp+CJXWa04mO+EWEiZQ/bPjG6jkUFy5M4Qs1vmTCUq3PnyN/YshW8uTtVC
# mPO7NRbn/7SgwJTWdPw+NKZFVGDudnKcP1vHOtCTbpSwKS5yoCXhmcEeoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMxOVowLwYJKoZIhvcNAQkEMSIEICSSu3iI
# UcvmjWJ4zg3c5mnuvbIOoA7KWXajMddUkGmjMA0GCSqGSIb3DQEBAQUABIICAKDK
# viBGK3HzFHbDmMkVEqvTxFGH7CPsZPMZbIGOMsSe9+5vzU+jtkt6ewqPgT/be3n1
# ArTJ/cVVuHu/VxOtQLGo3UhfznqYXE4hRjGnP1WAIWWvASXKH+lO6SaeaWwqXcr4
# kWTlupdYFmACaZFKIFITo16UUeVhx5mCFP8TkSwIS9RNLhTxxweJKJG5QGAYAD2Q
# 2leXE3dlFrtkfFiDBi0xZ3RiES7QoeC/erHwJfKPMEPNkaFOFE9cXWNiyXB9jJVr
# O68MzBgPhGlfNQySrXLf3NtNH5GHA5MPjiDzkS+cosGM3aRbyQVNSchjegtthrvv
# dxz5ucx3dvaKbBiRlw5iTQf8I9ErvE53DOfNNNUIRBi7D3V27+6lhJq5jPKo3a+B
# qrvwsSotgfEE5SWR4ZIE53Mj2GrPjpIrq9GGg5NWSZ1JPcDOOZfQSAaP9dentSMF
# b5owUdn8H3NDUTXQegew62WljG+KpjguJ3kRdSndX2IC7NsN3Uwduoexnfqs1Dhh
# oQrTnBw2xtk6rDXnyKK7ai3107vBPtIfVl+hpteplVgb+Y9KnkU+YawilmdEBsoh
# Mn2AJYsnxDRCsdGK1GuZV+esNAI09XMhYdM3ATx1Mw5jpr0HxWLitg9awljLEuv6
# Rxff/xguM5u0zftZINmPpOvDne/SjaJD81iLGPWA
# SIG # End signature block
