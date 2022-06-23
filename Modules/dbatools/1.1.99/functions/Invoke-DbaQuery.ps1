function Invoke-DbaQuery {
    <#
    .SYNOPSIS
        A command to run explicit T-SQL commands or files.

    .DESCRIPTION
        This function is a wrapper command around Invoke-DbaAsync, which in turn is based on Invoke-SqlCmd2.
        It was designed to be more convenient to use in a pipeline and to behave in a way consistent with the rest of our functions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        The database to select before running the query. This list is auto-populated from the server.

    .PARAMETER Query
        Specifies one or more queries to be run. The queries can be Transact-SQL, XQuery statements, or sqlcmd commands. Multiple queries in a single batch may be separated by a semicolon or a GO

        Escape any double quotation marks included in the string.

        Consider using bracketed identifiers such as [MyTable] instead of quoted identifiers such as "MyTable".

    .PARAMETER QueryTimeout
        Specifies the number of seconds before the queries time out.

    .PARAMETER File
        Specifies the path to one or several files to be used as the query input.

    .PARAMETER SqlObject
        Specify one or more SQL objects. Those will be converted to script and their scripts run on the target system(s).

    .PARAMETER As
        Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject', 'PSObjectArray', and 'SingleValue'.

        PSObject and PSObjectArray output introduces overhead but adds flexibility for working with results: https://forums.powershell.org/t/dealing-with-dbnull/2328/2

    .PARAMETER SqlParameter
        Specifies a hashtable of parameters or output from New-DbaSqlParameter for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

    .PARAMETER AppendServerInstance
        If this switch is enabled, the SQL Server instance will be appended to PSObject and DataRow output.

    .PARAMETER MessagesToOutput
        Use this switch to have on the output stream messages too (e.g. PRINT statements). Output will hold the resultset too.

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ReadOnly
        Execute the query with ReadOnly application intent.

    .PARAMETER CommandType
        Specifies the type of command represented by the query string. Valid options for this parameter are 'Text', 'TableDirect', and 'StoredProcedure'.
        Default is 'Text'. Further information: https://docs.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlcommand.commandtype

    .PARAMETER NoExec
        Use this switch to prepend SET NOEXEC ON and append SET NOEXEC OFF to each statement, useful for checking query formal errors


    .NOTES
        Tags: Database, Query, Utility
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaQuery

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance server\instance -Query 'SELECT foo FROM bar'

        Runs the sql query 'SELECT foo FROM bar' against the instance 'server\instance'

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance [SERVERNAME] -Group [GROUPNAME] | Invoke-DbaQuery -Query 'SELECT foo FROM bar'

        Runs the sql query 'SELECT foo FROM bar' against all instances in the group [GROUPNAME] on the CMS [SERVERNAME]

    .EXAMPLE
        PS C:\> "server1", "server1\nordwind", "server2" | Invoke-DbaQuery -File "C:\scripts\sql\rebuild.sql"

        Runs the sql commands stored in rebuild.sql against the instances "server1", "server1\nordwind" and "server2"

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance "server1", "server1\nordwind", "server2" | Invoke-DbaQuery -File "C:\scripts\sql\rebuild.sql"

        Runs the sql commands stored in rebuild.sql against all accessible databases of the instances "server1", "server1\nordwind" and "server2"

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance . -Query 'SELECT * FROM users WHERE Givenname = @name' -SqlParameter @{ Name = "Maria" }

        Executes a simple query against the users table using SQL Parameters.
        This avoids accidental SQL Injection and is the safest way to execute queries with dynamic content.
        Keep in mind the limitations inherent in parameters - it is quite impossible to use them for content references.
        While it is possible to parameterize a where condition, it is impossible to use this to select which columns to select.
        The inserted text will always be treated as string content, and not as a reference to any SQL entity (such as columns, tables or databases).
    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance aglistener1 -ReadOnly -Query "select something from readonlydb.dbo.atable"

        Executes a query with ReadOnly application intent on aglistener1.

    .EXAMPLE
        PS C:\> Invoke-DbaQuery -SqlInstance server1 -Database tempdb -Query Example_SP -SqlParameter @{ Name = "Maria" } -CommandType StoredProcedure

        Executes a stored procedure Example_SP using SQL Parameters

    .EXAMPLE
        PS C:\> $queryParameters = @{
        >>     StartDate = $startdate
        >>     EndDate   = $enddate
        >> }
        PS C:\> Invoke-DbaQuery -SqlInstance server1 -Database tempdb -Query Example_SP -SqlParameter $queryParameters -CommandType StoredProcedure

        Executes a stored procedure Example_SP using multiple SQL Parameters

    .EXAMPLE
        PS C:\> $inparam = @()
        PS C:\> $inparam += [pscustomobject]@{
        >>     somestring = 'string1'
        >>     somedate = '2021-07-15T01:02:00'
        >> }
        PS C:\> $inparam += [pscustomobject]@{
        >>     somestring = 'string2'
        >>     somedate = '2021-07-15T02:03:00'
        >> }
        >> $inparamAsDataTable = ConvertTo-DbaDataTable -InputObject $inparam
        PS C:\> New-DbaSqlParameter -SqlDbType structured -Value $inparamAsDataTable -TypeName 'dbatools_tabletype'
        PS C:\> Invoke-DbaQuery -SqlInstance localhost -Database master -CommandType StoredProcedure -Query my_proc -SqlParameter $inparamAsDataTable

        Creates an TVP input parameter and uses it to invoke a stored procedure.

    .EXAMPLE
        PS C:\> $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output
        PS C:\> Invoke-DbaQuery -SqlInstance localhost -Database master -CommandType StoredProcedure -Query my_proc -SqlParameter $output
        PS C:\> $output.Value

        Creates an output parameter and uses it to invoke a stored procedure.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance localhost -Database master -AlwaysEncrypted
        PS C:\> $inputparamSSN = New-DbaSqlParameter -Direction Input -ParameterName "@SSN" -DbType AnsiStringFixedLength -Size 11 -SqlValue "444-44-4444" -ForceColumnEncryption
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query 'SELECT * FROM bar WHERE SSN_col = @SSN' -SqlParameter @inputparamSSN

        Creates an input parameter using Always Encrypted
    #>
    [CmdletBinding(DefaultParameterSetName = "Query")]
    param (
        [Parameter(ValueFromPipeline)]
        [Parameter(ParameterSetName = 'Query', Position = 0)]
        [Parameter(ParameterSetName = 'File', Position = 0)]
        [Parameter(ParameterSetName = 'SMO', Position = 0)]
        [DbaInstance[]]$SqlInstance,
        [PsCredential]$SqlCredential,
        [string]$Database,
        [Parameter(Mandatory, ParameterSetName = "Query")]
        [string]$Query,
        [Int32]$QueryTimeout,
        [Parameter(Mandatory, ParameterSetName = "File")]
        [Alias("InputFile")]
        [object[]]$File,
        [Parameter(Mandatory, ParameterSetName = "SMO")]
        [Microsoft.SqlServer.Management.Smo.SqlSmoObject[]]$SqlObject,
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "PSObjectArray", "SingleValue")]
        [string]$As = "DataRow",
        [Alias("SqlParameters")]
        [psobject[]]$SqlParameter,
        [System.Data.CommandType]$CommandType = 'Text',
        [switch]$AppendServerInstance,
        [switch]$MessagesToOutput,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$ReadOnly,
        [switch]$NoExec,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        if ($PSBoundParameters.SqlParameter) {
            $first = $SqlParameter | Select-Object -First 1
            if ($first -isnot [Microsoft.Data.SqlClient.SqlParameter] -and ($first -isnot [System.Collections.IDictionary] -or $SqlParameter -is [System.Collections.IDictionary[]])) {
                Stop-Function -Message "SqlParameter only accepts a single hashtable or Microsoft.Data.SqlClient.SqlParameter"
                return
            }
        }

        $splatInvokeDbaSqlAsync = @{
            As          = $As
            CommandType = $CommandType
        }

        if (Test-Bound -ParameterName "SqlParameter") {
            $splatInvokeDbaSqlAsync["SqlParameter"] = $SqlParameter
        }
        if (Test-Bound -ParameterName "AppendServerInstance") {
            $splatInvokeDbaSqlAsync["AppendServerInstance"] = $AppendServerInstance
        }
        if (Test-Bound -ParameterName "Query") {
            $splatInvokeDbaSqlAsync["Query"] = $Query
        }
        if (Test-Bound -ParameterName "QueryTimeout") {
            $splatInvokeDbaSqlAsync["QueryTimeout"] = $QueryTimeout
        }
        if (Test-Bound -ParameterName "MessagesToOutput") {
            $splatInvokeDbaSqlAsync["MessagesToOutput"] = $MessagesToOutput
        }
        if (Test-Bound -ParameterName "Verbose") {
            $splatInvokeDbaSqlAsync["Verbose"] = $Verbose
        }
        if (Test-Bound -ParameterName "NoExec") {
            $splatInvokeDbaSqlAsync["NoExec"] = $NoExec
        }

        if (Test-Bound -ParameterName "File") {
            $files = @()
            $temporaryFiles = @()
            $temporaryFilesCount = 0
            $temporaryFilesPrefix = (97 .. 122 | Get-Random -Count 10 | ForEach-Object { [char]$_ }) -join ''

            foreach ($item in $File) {
                if ($null -eq $item) { continue }

                $type = $item.GetType().FullName

                switch ($type) {
                    "System.IO.DirectoryInfo" {
                        if (-not $item.Exists) {
                            Stop-Function -Message "Directory not found" -Category ObjectNotFound
                            return
                        }
                        $files += ($item.GetFiles() | Where-Object Extension -EQ ".sql").FullName

                    }
                    "System.IO.FileInfo" {
                        if (-not $item.Exists) {
                            Stop-Function -Message "Directory not found." -Category ObjectNotFound
                            return
                        }

                        $files += $item.FullName
                    }
                    "System.String" {
                        try {
                            if (Test-PsVersion -Maximum 4) {
                                $uri = [uri]$item
                            } else {
                                $uri = New-Object uri -ArgumentList $item
                            }
                            $uriScheme = $uri.Scheme
                        } catch {
                            $uriScheme = $null
                        }

                        switch -regex ($uriScheme) {
                            "http" {
                                $tempfile = "$(Get-DbatoolsPath -Name temp)\$temporaryFilesPrefix-$temporaryFilesCount.sql"
                                try {
                                    try {
                                        Invoke-TlsWebRequest -Uri $item -OutFile $tempfile -ErrorAction Stop
                                    } catch {
                                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                                        Invoke-TlsWebRequest -Uri $item -OutFile $tempfile -ErrorAction Stop
                                    }
                                    $files += $tempfile
                                    $temporaryFilesCount++
                                    $temporaryFiles += $tempfile
                                } catch {
                                    Stop-Function -Message "Failed to download file $item" -ErrorRecord $_
                                    return
                                }
                            }
                            default {
                                try {
                                    $paths = Resolve-Path $item | Select-Object -ExpandProperty Path | Get-Item -ErrorAction Stop
                                } catch {
                                    Stop-Function -Message "Failed to resolve path: $item" -ErrorRecord $_
                                    return
                                }

                                foreach ($path in $paths) {
                                    if (-not $path.PSIsContainer) {
                                        if (Test-PsVersion -Is 3) {
                                            if (([uri]$path.FullName).Scheme -ne 'file') {
                                                Stop-Function -Message "Could not resolve path $path as filesystem object"
                                                return
                                            }
                                        } else {
                                            if ((New-Object uri -ArgumentList $path).Scheme -ne 'file') {
                                                Stop-Function -Message "Could not resolve path $path as filesystem object"
                                                return
                                            }
                                        }
                                        $files += $path.FullName
                                    }
                                }
                            }
                        }
                    }
                    default {
                        Stop-Function -Message "Unkown input type: $type" -Category InvalidArgument
                        return
                    }
                }
            }
        }

        if (Test-Bound -ParameterName "SqlObject") {
            $files = @()
            $temporaryFiles = @()
            $temporaryFilesCount = 0
            $temporaryFilesPrefix = (97 .. 122 | Get-Random -Count 10 | ForEach-Object { [char]$_ }) -join ''

            foreach ($object in $SqlObject) {
                try { $code = Export-DbaScript -InputObject $object -Passthru -EnableException }
                catch {
                    Stop-Function -Message "Failed to generate script for object $object" -ErrorRecord $_
                    return
                }

                try {
                    $newfile = "$(Get-DbatoolsPath -Name temp)\$temporaryFilesPrefix-$temporaryFilesCount.sql"
                    Set-Content -Value $code -Path $newfile -Force -ErrorAction Stop -Encoding UTF8
                    $files += $newfile
                    $temporaryFilesCount++
                    $temporaryFiles += $newfile
                } catch {
                    Stop-Function -Message "Failed to write sql script to temp" -ErrorRecord $_
                    return
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        if (Test-Bound -ParameterName "Database", "InputObject" -And) {
            Stop-Function -Category InvalidArgument -Message "You can't use -Database with piped databases"
            return
        }
        if (Test-Bound -ParameterName "SqlInstance", "InputObject" -And) {
            Stop-Function -Category InvalidArgument -Message "You can't use -SqlInstance with piped databases"
            return
        }
        if (Test-Bound -ParameterName "SqlInstance", "InputObject" -Not) {
            Stop-Function -Category InvalidArgument -Message "Please provide either SqlInstance or InputObject"
            return
        }


        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }
            $server = $db.Parent
            $conncontext = $server.ConnectionContext
            if ($conncontext.DatabaseName -ne $db.Name) {
                # Save StatementTimeout because it might be reset on GetDatabaseConnection
                $savedStatementTimeout = $conncontext.StatementTimeout
                $conncontext = $conncontext.Copy().GetDatabaseConnection($db.Name)
                $conncontext.StatementTimeout = $savedStatementTimeout
            }
            try {
                if ($File -or $SqlObject) {
                    foreach ($item in $files) {
                        if ($null -eq $item) { continue }
                        $filePath = $(Resolve-Path -LiteralPath $item).ProviderPath
                        $QueryfromFile = [System.IO.File]::ReadAllText("$filePath")
                        Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync -Query $QueryfromFile
                    }
                } else { Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync }
            } catch {
                Stop-Function -Message "[$db] Failed during execution" -ErrorRecord $_ -Target $server -Continue
            }
        }
        foreach ($instance in $SqlInstance) {
            # Verbose output in Invoke-DbaQuery is special, because it's the only way to assure on all versions of Powershell to have separate outputs (results and messages) coming from the TSQL Query.
            # We suppress the verbosity of all other functions in order to be sure the output is consistent with what you get, e.g., executing the same in SSMS
            Write-Message -Level Debug -Message "SqlInstance passed in, will work on: $instance"
            try {
                $connDbaInstanceParams = @{
                    SqlInstance   = $instance
                    SqlCredential = $SqlCredential
                    Database      = $Database
                    Verbose       = $false
                }
                if ($ReadOnly) {
                    $connDbaInstanceParams.ApplicationIntent = "ReadOnly"
                }
                # Test for a windows credential and request a non-pooled connection in that case to keep the security context (see #7725 for details)
                if ($SqlCredential.UserName -like '*\*' -or $SqlCredential.UserName -like '*@*') {
                    Write-Message -Level Debug -Message "Windows credential detected, so requesting a non-pooled connection"
                    $connDbaInstanceParams.NonPooledConnection = $true
                }
                $server = Connect-DbaInstance @connDbaInstanceParams
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }
            $conncontext = $server.ConnectionContext
            try {
                if ($File -or $SqlObject) {
                    foreach ($item in $files) {
                        if ($null -eq $item) { continue }
                        $filePath = $(Resolve-Path -LiteralPath $item).ProviderPath
                        $QueryfromFile = [System.IO.File]::ReadAllText("$filePath")
                        Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync -Query $QueryfromFile
                    }
                } else {
                    Invoke-DbaAsync -SQLConnection $conncontext @splatInvokeDbaSqlAsync
                }
            } catch {
                Stop-Function -Message "[$instance] Failed during execution" -ErrorRecord $_ -Target $instance -Continue
            }
            if ($connDbaInstanceParams.NonPooledConnection) {
                # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
                $null = $server | Disconnect-DbaInstance -Verbose:$false
            }
        }
    }

    end {
        # Execute end even when interrupting, as only used for cleanup

        if ($temporaryFiles) {
            # Clean up temporary files that were downloaded
            foreach ($item in $temporaryFiles) {
                Remove-Item -Path $item -ErrorAction Ignore
            }
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUVQkOhWCjjQlNpUB+Q5cwWUFp
# DD2gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFMMuY1iB1UFKH3b71G2509/hfB7QMA0G
# CSqGSIb3DQEBAQUABIIBAFYO/b+BO2Wuq7ZvBse6MchsVNutAqnq71fA5g66D59N
# ZCbfxKUJtXgATwiOyFzOzsZyvQI8J48p78/BSLgsJQVTBIf5w9vb+hjYOdViZN3f
# +S25U2jx0q4+xaj4DdXqQSe7kY+ycre2N0HP0ohZZYjTEOmGLZ/z2NuJ70fSPgB4
# Is/lEk1MxKunyzlez8DRx+JebLYgFRKVSTjvdBXphV5i+ZOTTztMG1T8lh8AZIEk
# BstnzMNjHWAskV9WeSzvW9Qf1dR1HIiE8GSz8n7gMUlpJuU4t+P9okk+INtuFzNe
# oUuy9PAtPsxrAibSAex0yuzbPHyHuhGYQ5VihBTeqLihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU3WjAvBgkqhkiG9w0BCQQxIgQgVZclP5M1qrRHlFPMBje7
# I8jh17Tcl3qj4jDppy+qv1owDQYJKoZIhvcNAQEBBQAEggIAU5hFQrbnk4rExg5O
# 8OtDX+5xWqKiHtD/Nhyi7gWXPicsXgFyD8W4Bo14+pBQel7FQqkmQquOL9+amGnb
# F6zgpwtTB+kA03BgySp8rrocmR2h9hm/5Hv+RKzskXjJKWuu4MWWA+coy4XpznXh
# h0SIO/D1eyjyTp2ZtR1s8RWGBmra/z4SswCQ4cvL50yMWK87/lI2X+IUIk7frzKw
# LokaySlxX1t2a8lOI6WTJbGlzC3mr22C73ed911DXXUfD52j8hrpfLQa7qokltJc
# pyZlJvnu821VcivWz5edZYti34ZExDsAgVfl9bZa4g6Qjv7o3OvGohU1gx5BSMnR
# SKfs03JWx35lj0HKWRH99huZyeBI4Uu0T/0vCtVERdxzH5dR1IkuJiHyU5i4IdFy
# hBnP3rfHLlO5WlqnoeegNpo1YpLjMJETZcKdamrpdy5VDM+Nv20utMxv2cFoE9If
# pBeDA+tmaYSKJ50s1VXBFXD5Nmky6m3HYDhae1FHkjl2hFwDgIRRbPlWeTfNbIku
# KEtc+cuXexQedFgWGg9ah7hyZynFf0TNzDLgsvreGVzzWerUpKfwoues9jWHy1vd
# M2dOzLL/LNonZcmgOz2mYXhPQZyzIMl4uXwbc02gWsb9sH42mD43u8508+shIuAP
# yTxCe+fkFoVypkh250DWt1fPdtQ=
# SIG # End signature block
