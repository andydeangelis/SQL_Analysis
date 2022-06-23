function Invoke-DbaWhoIsActive {
    <#
    .SYNOPSIS
        Outputs results of Adam Machanic's sp_WhoIsActive DataTable

    .DESCRIPTION
        Output results of Adam Machanic's sp_WhoIsActive

        This command was built with Adam's permission. To read more about sp_WhoIsActive, please visit:

        Updates: http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx

        Also, consider donating to Adam if you find this stored procedure helpful: http://tinyurl.com/WhoIsActiveDonate

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER Database
        The database where sp_WhoIsActive is installed. Defaults to master. If the sp_WhoIsActive is not installed, the command will warn and exit.

    .PARAMETER Filter
        FiltersBoth inclusive and exclusive
        Set either filter to '' to disable
        Session is a session ID, and either 0 or '' can be used to indicate "all" sessions
        All other filter types support % or _ as wildcards

    .PARAMETER FilterType
        Valid filter types are: session, program, database, login, and host

    .PARAMETER NotFilter
        FiltersBoth inclusive and exclusive
        Set either filter to '' to disable
        Session is a session ID, and either 0 or '' can be used to indicate "all" sessions
        All other filter types support % or _ as wildcards

    .PARAMETER NotFilterType
        Valid filter types are: session, program, database, login, and host

    .PARAMETER ShowOwnSpid
        Retrieve data about the calling session?

    .PARAMETER ShowSystemSpids
        Retrieve data about system sessions?

    .PARAMETER ShowSleepingSpids
        Controls how sleeping SPIDs are handled, based on the idea of levels of interest
        0 does not pull any sleeping SPIDs
        1 pulls only those sleeping SPIDs that also have an open transaction
        2 pulls all sleeping SPIDs

    .PARAMETER GetFullInnerText
        If 1, gets the full stored procedure or running batch, when available
        If 0, gets only the actual statement that is currently running in the batch or procedure

    .PARAMETER GetPlans
        Get associated query plans for running tasks, if available
        If 1, gets the plan based on the request's statement offset
        If 2, gets the entire plan based on the request's plan_handle

    .PARAMETER GetOuterCommand
        Get the associated outer ad hoc query or stored procedure call, if available

    .PARAMETER GetTransactionInfo
        Enables pulling transaction log write info and transaction duration

    .PARAMETER GetTaskInfo
        Get information on active tasks, based on three interest levels
        Level 0 does not pull any task-related information
        Level 1 is a lightweight mode that pulls the top non-CXPACKET wait, giving preference to blockers
        Level 2 pulls all available task-based metrics, including:
        number of active tasks, current wait stats, physical I/O, context switches, and blocker information

    .PARAMETER GetLocks
        Gets associated locks for each request, aggregated in an XML format

    .PARAMETER GetAverageTime
        Get average time for past runs of an active query
        (based on the combination of plan handle, sql handle, and offset)

    .PARAMETER GetAdditonalInfo
        Get additional non-performance-related information about the session or request text_size, language, date_format, date_first, quoted_identifier, arithabort, ansi_null_dflt_on, ansi_defaults, ansi_warnings, ansi_padding, ansi_nulls, concat_null_yields_null, transaction_isolation_level, lock_timeout, deadlock_priority, row_count, command_type

        If a SQL Agent job is running, an subnode called agent_info will be populated with some or all of the following: job_id, job_name, step_id, step_name, msdb_query_error (in the event of an error)

        If @get_task_info is set to 2 and a lock wait is detected, a subnode called block_info will be populated with some or all of the following: lock_type, database_name, object_id, file_id, hobt_id, applock_hash, metadata_resource, metadata_class_id, object_name, schema_name

    .PARAMETER FindBlockLeaders
        Walk the blocking chain and count the number of
        total SPIDs blocked all the way down by a given session
        Also enables task_info Level 1, if @get_task_info is set to 0

    .PARAMETER DeltaInterval
        Pull deltas on various metrics
        Interval in seconds to wait before doing the second data pull

    .PARAMETER OutputColumnList
        List of desired output columns, in desired order
        Note that the final output will be the intersection of all enabled features and all columns in the list. Therefore, only columns associated with enabled features will actually appear in the output. Likewise, removing columns from this list may effectively disable features, even if they are turned on

        Each element in this list must be one of the valid output column names. Names must be delimited by square brackets. White space, formatting, and additional characters are allowed, as long as the list contains exact matches of delimited valid column names.

    .PARAMETER SortOrder
        Column(s) by which to sort output, optionally with sort directions.
        Valid column choices:
        session_id, physical_io, reads, physical_reads, writes, tempdb_allocations,
        tempdb_current, CPU, context_switches, used_memory, physical_io_delta,
        reads_delta, physical_reads_delta, writes_delta, tempdb_allocations_delta,
        tempdb_current_delta, CPU_delta, context_switches_delta, used_memory_delta,
        tasks, tran_start_time, open_tran_count, blocking_session_id, blocked_session_count,
        percent_complete, host_name, login_name, database_name, start_time, login_time

        Note that column names in the list must be bracket-delimited. Commas and/or white space are not required.

    .PARAMETER FormatOutput
        Formats some of the output columns in a more "human readable" form
        0 disables output format
        1 formats the output for variable-width fonts
        2 formats the output for fixed-width fonts

    .PARAMETER DestinationTable
        If set to a non-blank value, the script will attempt to insert into the specified destination table. Please note that the script will not verify that the table exists, or that it has the correct schema, before doing the insert. Table can be specified in one, two, or three-part format

    .PARAMETER ReturnSchema
        If set to 1, no data collection will happen and no result set will be returned; instead, a CREATE TABLE statement will be returned via the @schema parameter, which will match the schema of the result set that would be returned by using the same collection of the rest of the parameters. The CREATE TABLE statement will have a placeholder token of <table_name> in place of an actual table name.

    .PARAMETER Schema
        If set to 1, no data collection will happen and no result set will be returned; instead, a CREATE TABLE statement will be returned via the @schema parameter, which will match the schema of the result set that would be returned by using the same collection of the rest of the parameters. The CREATE TABLE statement will have a placeholder token of <table_name> in place of an actual table name.

    .PARAMETER Help
        Help! What do I do?

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER As
        Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject'. Default is 'DataRow'.

        PSObject output introduces overhead but adds flexibility for working with results: https://forums.powershell.org/t/dealing-with-dbnull/2328/2

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, WhoIsActive
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        http://whoisactive.com

    .LINK
        https://dbatools.io/Invoke-DbaWhoIsActive

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a

        Execute sp_whoisactive on sqlserver2014a. This command expects sp_WhoIsActive to be in the master database. Logs into the SQL Server with Windows credentials.

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -SqlCredential $credential -Database dbatools

        Execute sp_whoisactive on sqlserver2014a. This command expects sp_WhoIsActive to be in the dbatools database. Logs into the SQL Server with SQL Authentication.

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -GetAverageTime

        Similar to running sp_WhoIsActive @get_avg_time

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -GetOuterCommand -FindBlockLeaders

        Similar to running sp_WhoIsActive @get_outer_command = 1, @find_block_leaders = 1
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [string]$Database,
        [ValidateLength(0, 128)]
        [string]$Filter,
        [ValidateSet('Session', 'Program', 'Database', 'Login', 'Host')]
        [string]$FilterType = 'Session',
        [ValidateLength(0, 128)]
        [string]$NotFilter,
        [ValidateSet('Session', 'Program', 'Database', 'Login', 'Host')]
        [string]$NotFilterType = 'Session',
        [switch]$ShowOwnSpid,
        [switch]$ShowSystemSpids,
        [ValidateRange(0, 255)]
        [int]$ShowSleepingSpids,
        [switch]$GetFullInnerText,
        [ValidateRange(0, 255)]
        [int]$GetPlans,
        [switch]$GetOuterCommand,
        [switch]$GetTransactionInfo,
        [ValidateRange(0, 2)]
        [int]$GetTaskInfo,
        [switch]$GetLocks,
        [switch]$GetAverageTime,
        [switch]$GetAdditonalInfo,
        [switch]$FindBlockLeaders,
        [ValidateRange(0, 255)]
        [int]$DeltaInterval,
        [ValidateLength(0, 8000)]
        [string]$OutputColumnList = '[dd%][session_id][sql_text][sql_command][login_name][wait_info][tasks][tran_log%][cpu%][temp%][block%][reads%][writes%][context%][physical%][query_plan][locks][%]',
        [ValidateLength(0, 500)]
        [string]$SortOrder = '[start_time] ASC',
        [ValidateRange(0, 255)]
        [int]$FormatOutput = 1,
        [ValidateLength(0, 4000)]
        [string]$DestinationTable = '',
        [switch]$ReturnSchema,
        [string]$Schema,
        [switch]$Help,
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject")]
        [string]$As = "DataRow",
        [switch]$EnableException
    )
    begin {
        $passedParams = $psboundparameters.Keys | Where-Object { 'Silent', 'SqlServer', 'SqlCredential', 'OutputAs', 'ServerInstance', 'SqlInstance', 'Database' -notcontains $_ }
        $localParams = $psboundparameters

        # The procedure sp_WhoIsActive uses only lowercase values, so we convert the input in case we have a case sensitive database.
        if ($localParams.FilterType) { $localParams.FilterType = $localParams.FilterType.ToLower() }
        if ($localParams.NotFilterType) { $localParams.NotFilterType = $localParams.NotFilterType.ToLower() }
    }
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $paramDictionary = @{
                Filter             = '@filter'
                FilterType         = '@filter_type'
                NotFilter          = '@not_filter'
                NotFilterType      = '@not_filter_type'
                ShowOwnSpid        = '@show_own_spid'
                ShowSystemSpids    = '@show_system_spids'
                ShowSleepingSpids  = '@show_sleeping_spids'
                GetFullInnerText   = '@get_full_inner_text'
                GetPlans           = '@get_plans'
                GetOuterCommand    = '@get_outer_command'
                GetTransactionInfo = '@get_transaction_info'
                GetTaskInfo        = '@get_task_info'
                GetLocks           = '@get_locks '
                GetAverageTime     = '@get_avg_time'
                GetAdditonalInfo   = '@get_additional_info'
                FindBlockLeaders   = '@find_block_leaders'
                DeltaInterval      = '@delta_interval'
                OutputColumnList   = '@output_column_list'
                SortOrder          = '@sort_order'
                FormatOutput       = '@format_output '
                DestinationTable   = '@destination_table '
                ReturnSchema       = '@return_schema'
                Schema             = '@schema'
                Help               = '@help'
            }

            Write-Message -Level Verbose -Message "Collecting sp_whoisactive data from server: $instance"
            try {
                $sqlParameter = @{ }
                foreach ($param in $passedParams) {
                    Write-Message -Level Verbose -Message "Check parameter '$param'"
                    $sqlParam = $paramDictionary[$param]
                    if ($sqlParam) {
                        $value = $localParams[$param]
                        switch ($value) {
                            $true { $value = 1 }
                            $false { $value = 0 }
                        }
                        Write-Message -Level Verbose -Message "Adding parameter '$sqlParam' with value '$value'"
                        $sqlParameter[$sqlParam] = $value
                    }
                }
                Invoke-DbaQuery -SqlInstance $server -Query "dbo.sp_WhoIsActive" -CommandType "StoredProcedure" -SqlParameter $sqlParameter -As $As -EnableException
            } catch {
                if ($_.Exception.InnerException -Like "*Could not find*") {
                    Stop-Function -Message "sp_whoisactive not found, please install using Install-DbaWhoIsActive." -Continue
                } else {
                    Stop-Function -Message "Invalid query." -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCKmW/DeNJnN2LX
# ReMPlhCOZ2Rt+UzOfUYTIEn6HM6NK6CCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAiz0Kja+YisXWAp+cws3vfzqCQAJIGfO6y
# AsJECmXHrjANBgkqhkiG9w0BAQEFAASCAQBDfELbQuUwkDrdwc1+OxVbuHXwCTdQ
# QVbPqUiSyLkJusJhOgilRWnCFpqITWueyHM+17Mb4nCwD+VO1JR+pbGiGatldk8X
# vrVCamKwwYZ8iBuAH40xHqKJrWBO0z5Z/INUtnvWQBQym6t3mBtxDLx71yP0nN1Y
# ijPIH2PNyuPiBVrghKbBEKpZTFolsmp3XEC+zK/L7LULOtM35ZVbyMQ21AsqIHYA
# CeNa5o/lnyJO6ll4ijaqh5PVatej5mqUu8UWL7fQt3wl2UmURhSy5NrrKw08PIhi
# iU5w0aEzXPvgoJILmGgkqXhVR3Lxro187O8Z1Jrg/JDCu6o7/bKJEN7qoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMyOVowLwYJKoZIhvcNAQkEMSIEIC4Mwt0n
# UieRgT2xClzy5nv8TdrG1IpowXPR3QCmxBg5MA0GCSqGSIb3DQEBAQUABIICAJLa
# 3IOZMzvoMsQqNa9kt/3T6E9WjBuxkoekfUqsrP33pCDYmFNX0U7AWNJUOFnVpQfv
# /XuVz0y6jZDR1muViNxhNnwcIU4R6ABOj/NMw/sA0v7zWT+lvzUtmY7mT8xQZjtm
# M8AbPn9iRKhiz+IzJVkC90gwHAQdkYXDlyeK5Zsym7hyGgyId+awe8XPn6MaxxPc
# qFgONsd5pqaBWborWcFlLChjJ4tMgwHZ3WHO/CJISobG/jB1sFLisPSRNmJ3aUbg
# 0n/7YXLBMDPXf5FwdUG8/WWIWr6snjnH3UzdtQqIYZwZJxTrBD3P95uB8WtSVt5m
# aR8r235UTmtboboDOJYTSgwldjUz5QrTuIXa6ily9K6RvXFicgMruBk2aT6iS5Kk
# omw+5DJWlFLW6PpNctqSC2y/JjQP+5DTOEPUb0276yFVsC72DCBMoBMEzMRKyovn
# 6kCxo9/mB/faWKu7oeLM+xmEcznV9BHaNcqj1tW+vdC8pnNE0h0+gWi0nAfokjch
# Vh07kKCJRsyycNxusI5Bv22Qb9wFEkzYD8VYpRxLyji7ZvCcpuUEEcIDJISvI5Le
# kJ5Ai57SiuZ8OcgNfLIaw/71zlquUvfIggQQeo2fLD/K+22mq98uK7AmBEG6idMD
# oHYliEYxH2ldj7X7fp8BCNdoi8CJCcXkbAv3WLtV
# SIG # End signature block
