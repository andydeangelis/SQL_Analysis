function Invoke-DbaAsync {
    <#
        .SYNOPSIS
            Runs a T-SQL script.

        .DESCRIPTION
            Runs a T-SQL script. It's a stripped down version of https://github.com/dataplat/Invoke-SqlCmd2 and adapted to use dbatools' facilities.
            If you're looking for a public usable function, see Invoke-DbaQuery

        .PARAMETER SQLConnection
            Specifies an existing SQLConnection object to use in connecting to SQL Server.

        .PARAMETER Query
            Specifies one or more queries to be run. The queries can be Transact-SQL, XQuery statements, or sqlcmd commands. Multiple queries in a single batch may be separated by a semicolon.

            Do not specify the sqlcmd GO separator (or, use the ParseGo parameter). Escape any double quotation marks included in the string.

            Consider using bracketed identifiers such as [MyTable] instead of quoted identifiers such as "MyTable".

        .PARAMETER QueryTimeout
            Specifies the number of seconds before the queries time out.

        .PARAMETER As
            Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject', 'PSObjectArray', and 'SingleValue'

            PSObject and PSObjectArray output introduces overhead but adds flexibility for working with results: http://powershell.org/wp/forums/topic/dealing-with-dbnull/

        .PARAMETER SqlParameter
            Specifies a hashtable of parameters or output from New-DbaSqlParameter for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

        .PARAMETER AppendServerInstance
            If this switch is enabled, the SQL Server instance will be appended to PSObject and DataRow output.

        .PARAMETER MessagesToOutput
            Use this switch to have on the output stream messages too (e.g. PRINT statements). Output will hold the resultset too. See examples for detail

        .PARAMETER NoExec
            Use this switch to prepend SET NOEXEC ON and append SET NOEXEC OFF to each statement

        .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        .PARAMETER CommandType
            Specifies the type of command represented by the query string.  Default is Text
    #>

    param (
        [Alias('Connection', 'Conn')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.SqlServer.Management.Common.ServerConnection]$SQLConnection,

        [Parameter(Mandatory, ParameterSetName = "Query")]
        [string]
        $Query,

        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "PSObjectArray", "SingleValue")]
        [string]
        $As = "DataRow",

        [Alias("SqlParameters")]
        [psobject[]]$SqlParameter,

        [System.Data.CommandType]
        $CommandType = 'Text',

        [switch]
        $AppendServerInstance,

        [Int32]$QueryTimeout,

        [switch]
        $MessagesToOutput,

        [switch]
        $NoExec,

        [switch]$EnableException
    )

    begin {
        if ($PSBoundParameters.SqlParameter) {
            $first = $SqlParameter | Select-Object -First 1
            if ($first -isnot [Microsoft.Data.SqlClient.SqlParameter] -and ($first -isnot [System.Collections.IDictionary] -or $SqlParameter -is [System.Collections.IDictionary[]])) {
                Stop-Function -Message "SqlParameter only accepts a single hashtable or Microsoft.Data.SqlClient.SqlParameter"
                return
            }
        }
        if (-not $PSBoundParameters.QueryTimeout) {
            $QueryTimeout = $SQLConnection.StatementTimeout
        }
        function Resolve-SqlError {
            param($Err)
            if ($Err) {
                if ($Err.Exception.GetType().Name -eq 'SqlException') {
                    # For SQL exception
                    #$Err = $_
                    Write-Message -Level Debug -Message "Capture SQL Error"
                    if ($PSBoundParameters.Verbose) {
                        Write-Message -Level Verbose -Message "SQL Error:  $Err"
                    } #Shiyang, add the verbose output of exception
                    switch ($ErrorActionPreference.ToString()) {
                        { 'SilentlyContinue', 'Ignore' -contains $_ } { }
                        'Stop' { throw $Err }
                        'Continue' { throw $Err }
                        Default { Throw $Err }
                    }
                } else {
                    # For other exception
                    Write-Message -Level Debug -Message "Capture Other Error"
                    if ($PSBoundParameters.Verbose) {
                        Write-Message -Level Verbose -Message "Other Error:  $Err"
                    }
                    switch ($ErrorActionPreference.ToString()) {
                        { 'SilentlyContinue', 'Ignore' -contains $_ } { }
                        'Stop' { throw $Err }
                        'Continue' { throw $Err }
                        Default { throw $Err }
                    }
                }
            }

        }

        if ($As -in "PSObject", "PSObjectArray") {
            #This code scrubs DBNulls.  Props to Dave Wyatt
            $cSharp = @'
                using System;
                using System.Data;
                using System.Management.Automation;

                public class DBNullScrubber
                {
                    public static PSObject DataRowToPSObject(DataRow row)
                    {
                        PSObject psObject = new PSObject();

                        if (row != null && (row.RowState & DataRowState.Detached) != DataRowState.Detached)
                        {
                            foreach (DataColumn column in row.Table.Columns)
                            {
                                Object value = null;
                                if (!row.IsNull(column))
                                {
                                    value = row[column];
                                }

                                psObject.Properties.Add(new PSNoteProperty(column.ColumnName, value));
                            }
                        }

                        return psObject;
                    }
                }
'@

            try {
                if ($PSEdition -eq 'Core') {
                    $assemblies = @('System.Management.Automation', 'System.Data.Common', 'System.ComponentModel.TypeConverter')
                } else {
                    $assemblies = @('System.Data', 'System.Xml')
                }
                Add-Type -TypeDefinition $cSharp -ReferencedAssemblies $assemblies -ErrorAction stop
            } catch {
                if (-not $_.ToString() -like "*The type name 'DBNullScrubber' already exists*") {
                    Write-Warning "Could not load DBNullScrubber.  Defaulting to DataRow output: $_."
                    $As = "Datarow"
                }
            }
        }

        $GoSplitterRegex = [regex]'(?smi)^[\s]*GO[\s]*$'

    }
    process {
        if (Test-FunctionInterrupt) { return }
        $Conn = $SQLConnection.SqlConnectionObject


        Write-Message -Level Debug -Message "Stripping GOs from source"
        $Pieces = $GoSplitterRegex.Split($Query)

        # Only execute non-empty statements
        $Pieces = $Pieces | Where-Object { $_.Trim().Length -gt 0 }
        foreach ($piece in $Pieces) {
            $runningStatement = $piece
            if ($NoExec) {
                $runningStatement = "SET NOEXEC ON; " + $piece + " ;SET NOEXEC OFF;"
            }
            $cmd = New-Object Microsoft.Data.SqlClient.SqlCommand($runningStatement, $conn)
            $cmd.CommandType = $CommandType
            $cmd.CommandTimeout = $QueryTimeout

            if ($null -ne $SqlParameter) {
                if (($SqlParameter | Select-Object -First 1) -is [Microsoft.Data.SqlClient.SqlParameter]) {
                    foreach ($sqlparam in $SqlParameter) {
                        $null = $cmd.Parameters.Add($sqlparam)
                    }
                } else {
                    ($SqlParameter | Select-Object -First 1).GetEnumerator() | ForEach-Object {
                        if ($null -ne $_.Value) {
                            if (($_.Value -is [Microsoft.Data.SqlClient.SqlParameter])) {
                                if ($_.Value.ParameterName -ne $_.Key) {
                                    $_.Value.ParameterName = $_.Key
                                }
                                $cmd.Parameters.Add($_.Value)
                            } else {
                                $cmd.Parameters.AddWithValue($_.Key, $_.Value)
                            }
                        } else {
                            $cmd.Parameters.AddWithValue($_.Key, [DBNull]::Value)
                        }
                    } > $null
                }
            }

            $ds = New-Object System.Data.DataSet
            $da = New-Object Microsoft.Data.SqlClient.SqlDataAdapter($cmd)

            if ($MessagesToOutput) {
                $defaultrunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
                $pool = [RunspaceFactory]::CreateRunspacePool(1, [int]$env:NUMBER_OF_PROCESSORS + 1)
                $pool.ApartmentState = "MTA"
                $pool.Open()
                $runspaces = @()
                $scriptBlock = {
                    param ($da, $ds, $conn, $queue )
                    $conn.FireInfoMessageEventOnUserErrors = $false
                    $handler = [Microsoft.Data.SqlClient.SqlInfoMessageEventHandler] { $queue.Enqueue($_) }
                    $conn.add_InfoMessage($handler)
                    $Err = $null
                    try {
                        [void]$da.fill($ds)
                    } catch {
                        $Err = $_
                    } finally {
                        $conn.remove_InfoMessage($handler)
                    }
                    return $Err
                }
                $queue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
                $runspace = [PowerShell]::Create()
                $null = $runspace.AddScript($scriptBlock)
                $null = $runspace.AddArgument($da)
                $null = $runspace.AddArgument($ds)
                $null = $runspace.AddArgument($Conn)
                $null = $runspace.AddArgument($queue)
                $runspace.RunspacePool = $pool
                $runspaces += [PSCustomObject]@{ Pipe = $runspace; Status = $runspace.BeginInvoke() }
                # While streaming ...
                while ($runspaces.Status.IsCompleted -notcontains $true) {
                    $item = $null
                    if ($queue.TryDequeue([ref]$item)) {
                        "$item"
                    }
                }
                # Drain the stream as the runspace is closed, just to be safe
                if ($queue.IsEmpty -ne $true) {
                    $item = $null
                    while ($queue.TryDequeue([ref]$item)) {
                        "$item"
                    }
                }
                foreach ($runspace in $runspaces) {
                    $results = $runspace.Pipe.EndInvoke($runspace.Status)
                    $runspace.Pipe.Dispose()
                    if ($null -ne $results) {
                        Resolve-SqlError $results[0]
                    }
                }
                $pool.Close()
                $pool.Dispose()
                [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $defaultrunspace
            } else {
                #Following EventHandler is used for PRINT and RAISERROR T-SQL statements. Executed when -Verbose parameter specified by caller and no -MessageToOutput
                if ($PSBoundParameters.Verbose) {
                    $conn.FireInfoMessageEventOnUserErrors = $false
                    $handler = [Microsoft.Data.SqlClient.SqlInfoMessageEventHandler] { Write-Verbose -Message "$($_)" }
                    $conn.add_InfoMessage($handler)
                }
                $Err = $null
                try {
                    [void]$da.fill($ds)
                } catch {
                    $Err = $_
                } finally {
                    if ($PSBoundParameters.Verbose) {
                        $conn.remove_InfoMessage($handler)
                    }
                }
                Resolve-SqlError $Err
            }
            if ($AppendServerInstance) {
                #Basics from Chad Miller
                $Column = New-Object Data.DataColumn
                $Column.ColumnName = "ServerInstance"

                if ($ds.Tables.Count -ne 0) {
                    $ds.Tables[0].Columns.Add($Column)
                    Foreach ($row in $ds.Tables[0]) {
                        $row.ServerInstance = $SQLConnection.ServerInstance
                    }
                }
            }

            switch ($As) {
                'DataSet' {
                    $ds
                }
                'DataTable' {
                    $ds.Tables
                }
                'DataRow' {
                    if ($ds.Tables.Count -ne 0) {
                        $ds.Tables[0]
                    }
                }
                'PSObject' {
                    foreach ($table in $ds.Tables) {
                        #Scrub DBNulls - Provides convenient results you can use comparisons with
                        #Introduces overhead (e.g. ~2000 rows w/ ~80 columns went from .15 Seconds to .65 Seconds - depending on your data could be much more!)
                        foreach ($row in $table.Rows) {
                            [DBNullScrubber]::DataRowToPSObject($row)
                        }
                    }
                }
                'PSObjectArray' {
                    foreach ($table in $ds.Tables) {
                        $rows = foreach ($row in $table.Rows) {
                            [DBNullScrubber]::DataRowToPSObject($row)
                        }
                        , $rows
                    }
                }
                'SingleValue' {
                    if ($ds.Tables.Count -ne 0) {
                        $ds.Tables[0] | Select-Object -ExpandProperty $ds.Tables[0].Columns[0].ColumnName
                    }
                }
            }
        } #foreach ($piece in $Pieces)

    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUK5Y11FiVnQBk0AQLKB2laW6A
# GoqgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFNu62Fb/O9Cg3r69SEZWH+WPFp/OMA0G
# CSqGSIb3DQEBAQUABIIBADe0RFipdlZSeFgHbDsJ2AYKAdpZetEsjCibpqIjKjWh
# PxBfWyfjRi2/FxPNIZfzgGRPdoxxg1GT2v4kMmy7hdcsPGz8vwrz7nVnocpwdPSq
# LJrSxv6f/59mAxqjyZyDF/M9XLZ8No4Cw89APFP0vqGDHziNoDzbWQplosXY1Csh
# WECUUmb40wVT7LnKL9Kpt5ry1KPeCX4z7ycZXqcCG1EOweIEE0+JMIKA5nqhR4WS
# 9oqsB5aBdIxeYjKCg1LykMHHA3frzQN0Wn4vml9Urn3b8BYe/WSywAoRgsY5hjw+
# jgCudvgP9B/HS4YPs0h0jyV5i5pvhpx0vVkP7R+fe4ihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDUzWjAvBgkqhkiG9w0BCQQxIgQgm7qkh8aVBPPMODqToggc
# nYe59qQl+O2tCVUyLedv2yUwDQYJKoZIhvcNAQEBBQAEggIAsTT1bUj07RgNMPWb
# ClwhBt4psApgCjOI71biTjitCtZFOqFqa1ctDIeMXA6mPzj47dXDjR883AY79TaY
# y2CkZ/4k7Z8sOPbDxd4DSRJ27qjHRqzY4EKYm4/l6EGAC4LoF+KGHOn2bUtSS8oX
# 073FOcdHufmOPXP8ZxK8nH3GySC5ORjzd04oymH4FWfRz0Wphiz6MUBpsfM3Lo5J
# fr8R3oSvlEUHM1Lh6zs12HA2+7wb0tGZXj+nMruL+pZrwW0Iglzn5XYKrdkVMPSx
# ecTRp1YfD8jAB4l3wPmZbfvmi08lNWCo7fuhX7Xs42rbu1Sk01x6N7vDG6d9CQvH
# XFPoqunhfbc91Uo8SGV5MiVQ82/RbM+WePhkJxgFm1uoS8r7cDrAAsPHzNyva6gU
# 7S2sBe6K2mr8LEYmsrYcpgcmJqxMaS08zNflt/DX63T/gUHi2aHL7/sAoxBC2KEg
# yD42mAsGbyY4QvyXjafBflWY6AeKuQN7/3m7UtdYmiCHvc6aqCDhrXZHwP5DrsPh
# 3aYW0KsFCwTVM5YNNbP4qJQYTNb2B03yyG4rhpErnKLQIYagGXr8g7PpS1nZQeme
# xV4acUusjqtm7lMTVIQFXcy7kYARim1YqF27osqklgGkR4VPFbV5WJSq6K/qKJ1S
# CGocH3ObQ2SkJnvRgLFiCEwZk9Q=
# SIG # End signature block
