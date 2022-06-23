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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUo8q7JNCU6COFMtU3kyazN+qY
# qV+gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFEtI66Pv4A1852VPtHaBqMtWvjgGMA0G
# CSqGSIb3DQEBAQUABIIBAH0r6AQ0aaYWRLrVT8bHgUwcdOcMrJzym7hom9kfG+Pm
# 4dQAsnZkt5MwHsYVv559XYWrkSKgLyXHwprN9VbZnzRJhVx/JhsXwaxdm1UJEVmk
# pjRhTSo3wppF6uhD/yZXZqW9R4iu8VuCegjoPMCjeOnLHIDOwKoHp65P8gDx1eHm
# ZfsezRUhTaMj7Ft2n+pezn2cOPe7hd1iCOj9r337s4u8P+APFCnAlw1ESxqZcNKc
# 6hPlzrMlDs3K48FURp+HGviGh2jtmYUcOIZo39bdrqczobV7LbUxT4LIqb4GfdHu
# Pa3+tpYZXctUBLtPvdenTYUWajDM9CBVrsTj8ZfKo46hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU3WjAvBgkqhkiG9w0BCQQxIgQgoSeBAnrhaUZuN2Kou2bD
# P2JJLgjw5UyB10faVqz7tyMwDQYJKoZIhvcNAQEBBQAEggIAffiCutksLRI2GGU2
# Sb+qR6eEEyN3ilLlMbS8/gwMdUIn/yBKjgwx9AqMfj5/Mw3KpzSUjHpxt5O0mSbC
# FEQV2sQtuB81pU3gAQWzsZBypkH9yua8RlQYdXziZR3pBwuTrMqE2fikgq5CGV8w
# gf53K0M4l/mrRExIHGRmCGHJc3GCwO+wxV4mUAv76Q5hTGqIEE7zEhVwplozZ5C0
# a7dQqGV7cvqbdpvg7R+PHhiyGByIgJ5L7KjOxQhMK8uNJmlxGP2cnPUQmRsY1Vru
# NaWUuQcqcaVtihGZvkCVFVk+lrzk9fhWU/UqPIvG621yrWWA9QY89iOmHJv8slhy
# gQZKtWL9hbG2WWewe+MCeDXxVZbDDobq1E3MJdKF22AHDmnIxU3WvD165CHO6xNJ
# aEk0oWwHBDOK1rtVpXYfCKNhkY7M85JwR7VPP5ggIMlyCHi6dJsVVNkQDBdeP+7N
# /h4ng9PlDJINyheCOOzSTj0q5QNGgxYMLKk+6SaxNC3pabl6EwgDEWBTsI/zjULU
# mFV6ILvIPC1GDhrZR0/zyoQcXCiDs8prh4f8QUIx12x+ODxEZ5xZNYEwTBbvwNQZ
# AwZ1UIZleC632ddBXMhCSzrrqTs6zpmMaRwBxGZGAzc3m5rEEzTL7tDG25hxO4LQ
# lhGz0f7+bQxn2zFX9Pi+UmV5eGg=
# SIG # End signature block
