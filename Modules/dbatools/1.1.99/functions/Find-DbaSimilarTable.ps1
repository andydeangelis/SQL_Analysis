function Find-DbaSimilarTable {
    <#
    .SYNOPSIS
        Returns all tables/views that are similar in structure by comparing the column names of matching and matched tables/views

    .DESCRIPTION
        This function can either run against specific databases or all databases searching all/specific tables and views including in system databases.
        Typically one would use this to find for example archive version(s) of a table whose structures are similar.
        This can also be used to find tables/views that are very similar to a given table/view structure to see where a table/view might be used.

        More information can be found here: https://sqljana.wordpress.com/2017/03/31/sql-server-find-tables-with-similar-table-structure/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER SchemaName
        If you are looking in a specific schema whose table structures is to be used as reference structure, provide the name of the schema.
        If no schema is provided, looks at all schemas

    .PARAMETER TableName
        If you are looking in a specific table whose structure is to be used as reference structure, provide the name of the table.
        If no table is provided, looks at all tables
        If the table name exists in multiple schemas, all of them would qualify

    .PARAMETER ExcludeViews
        By default, views are included. You can exclude them by setting this switch to $false
        This excludes views in both matching and matched list

    .PARAMETER IncludeSystemDatabases
        By default system databases are ignored but you can include them within the search using this parameter

    .PARAMETER MatchPercentThreshold
        The minimum percentage of column names that should match between the matching and matched objects.
        Entries with no matches are eliminated

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Table, Lookup
        Author: Jana Sattainathan (@SQLJana), http://sqljana.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaSimilarTable

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01

        Searches all user database tables and views for each, returns all tables or views with their matching tables/views and match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks

        Searches AdventureWorks database and lists tables/views and their corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -SchemaName HumanResource

        Searches AdventureWorks database and lists tables/views in the HumanResource schema with their corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -SchemaName HumanResource -Table Employee

        Searches AdventureWorks database and lists tables/views in the HumanResource schema and table Employee with its corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -MatchPercentThreshold 60

        Searches AdventureWorks database and lists all tables/views with its corresponding matching tables/views with match percent greater than or equal to 60

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string]$SchemaName,
        [string]$TableName,
        [switch]$ExcludeViews,
        [switch]$IncludeSystemDatabases,
        [int]$MatchPercentThreshold,
        [switch]$EnableException
    )

    begin {
        $everyServerVwCount = 0

        $sqlSelect = "WITH ColCountsByTable
                AS
                (
                      SELECT
                            c.TABLE_CATALOG,
                            c.TABLE_SCHEMA,
                            c.TABLE_NAME,
                            COUNT(1) AS Column_Count
                      FROM INFORMATION_SCHEMA.COLUMNS c
                      GROUP BY
                            c.TABLE_CATALOG,
                            c.TABLE_SCHEMA,
                            c.TABLE_NAME
                )
                SELECT
                      100 * COUNT(c2.COLUMN_NAME) /*Matching_Column_Count*/ / MIN(ColCountsByTable.Column_Count) /*Column_Count*/ AS MatchPercent,
                      DENSE_RANK() OVER(ORDER BY c.TABLE_CATALOG, c.TABLE_SCHEMA, c.TABLE_NAME) TableNameRankInDB,
                      c.TABLE_CATALOG AS DatabaseName,
                      c.TABLE_SCHEMA AS SchemaName,
                      c.TABLE_NAME AS TableName,
                      t.TABLE_TYPE AS TableType,
                      MIN(ColCountsByTable.Column_Count) AS ColumnCount,
                      c2.TABLE_CATALOG AS MatchingDatabaseName,
                      c2.TABLE_SCHEMA AS MatchingSchemaName,
                      c2.TABLE_NAME AS MatchingTableName,
                      t2.TABLE_TYPE AS MatchingTableType,
                      COUNT(c2.COLUMN_NAME) AS MatchingColumnCount
                FROM INFORMATION_SCHEMA.TABLES t
                      INNER JOIN INFORMATION_SCHEMA.COLUMNS c
                            ON t.TABLE_CATALOG = c.TABLE_CATALOG
                                  AND t.TABLE_SCHEMA = c.TABLE_SCHEMA
                                  AND t.TABLE_NAME = c.TABLE_NAME
                      INNER JOIN ColCountsByTable
                            ON t.TABLE_CATALOG = ColCountsByTable.TABLE_CATALOG
                                  AND t.TABLE_SCHEMA = ColCountsByTable.TABLE_SCHEMA
                                  AND t.TABLE_NAME = ColCountsByTable.TABLE_NAME
                      LEFT OUTER JOIN INFORMATION_SCHEMA.COLUMNS c2
                            ON t.TABLE_NAME != c2.TABLE_NAME
                                  AND c.COLUMN_NAME = c2.COLUMN_NAME
                      LEFT JOIN INFORMATION_SCHEMA.TABLES t2
                            ON c2.TABLE_NAME = t2.TABLE_NAME"

        $sqlWhere = "
                WHERE "

        $sqlGroupBy = "
                GROUP BY
                      c.TABLE_CATALOG,
                      c.TABLE_SCHEMA,
                      c.TABLE_NAME,
                      t.TABLE_TYPE,
                      c2.TABLE_CATALOG,
                      c2.TABLE_SCHEMA,
                      c2.TABLE_NAME,
                      t2.TABLE_TYPE "

        $sqlHaving = "
                HAVING
                    /*Match_Percent should be greater than 0 at minimum!*/
                    "

        $sqlOrderBy = "
                ORDER BY
                      MatchPercent DESC"


        $sql = ''
        $wherearray = @()

        if ($ExcludeViews) {
            $wherearray += " (t.TABLE_TYPE <> 'VIEW' AND t2.TABLE_TYPE <> 'VIEW') "
        }

        if ($SchemaName) {
            $wherearray += (" (c.TABLE_SCHEMA = '{0}') " -f $SchemaName.Replace("'", "''")) #Replace single quotes with two single quotes!
        }

        if ($TableName) {
            $wherearray += (" (c.TABLE_NAME = '{0}') " -f $TableName.Replace("'", "''")) #Replace single quotes with two single quotes!

        }

        if ($wherearray.length -gt 0) {
            $sqlWhere = "$sqlWhere " + ($wherearray -join " AND ")
        } else {
            $sqlWhere = ""
        }


        $matchThreshold = 0
        if ($MatchPercentThreshold) {
            $matchThreshold = $MatchPercentThreshold
        } else {
            $matchThreshold = 0
        }

        $sqlHaving += (" (100 * COUNT(c2.COLUMN_NAME) / MIN(ColCountsByTable.Column_Count) >= {0}) " -f $matchThreshold)



        $sql = "$sqlSelect $sqlWhere $sqlGroupBy $sqlHaving $sqlOrderBy"

        Write-Message -Level Debug -Message $sql

    }

    process {
        foreach ($Instance in $SqlInstance) {

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            #Use IsAccessible instead of Status -eq 'normal' because databases that are on readable secondaries for AG or mirroring replicas will cause errors to be thrown
            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true }
            } else {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $server.Databases | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }


            $totalCount = 0
            $dbCount = $dbs.count
            foreach ($db in $dbs) {

                Write-Message -Level Verbose -Message "Searching on database $db"
                $rows = $db.Query($sql)

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        ComputerName              = $server.ComputerName
                        InstanceName              = $server.ServiceName
                        SqlInstance               = $server.DomainInstanceName
                        Table                     = "$($row.DatabaseName).$($row.SchemaName).$($row.TableName)"
                        MatchingTable             = "$($row.MatchingDatabaseName).$($row.MatchingSchemaName).$($row.MatchingTableName)"
                        MatchPercent              = $row.MatchPercent
                        OriginalDatabaseName      = $row.DatabaseName
                        OriginalSchemaName        = $row.SchemaName
                        OriginalTableName         = $row.TableName
                        OriginalTableNameRankInDB = $row.TableNameRankInDB
                        OriginalTableType         = $row.TableType
                        OriginalColumnCount       = $row.ColumnCount
                        MatchingDatabaseName      = $row.MatchingDatabaseName
                        MatchingSchemaName        = $row.MatchingSchemaName
                        MatchingTableName         = $row.MatchingTableName
                        MatchingTableType         = $row.MatchingTableType
                        MatchingColumnCount       = $row.MatchingColumnCount
                    }
                }

                $vwCount = $vwCount + $rows.Count
                $totalCount = $totalCount + $rows.Count
                $everyServerVwCount = $everyServerVwCount + $rows.Count

                Write-Message -Level Verbose -Message "Found $vwCount tables/views in $db"
            }

            Write-Message -Level Verbose -Message "Found $totalCount total tables/views in $dbCount databases"
        }
    }
    end {
        Write-Message -Level Verbose -Message "Found $everyServerVwCount total tables/views"
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUsHT/33tuppenbfYgI5hQeRpc
# s/igghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFFxIEHEct7CfQo7uTYCxR07cDXiaMA0G
# CSqGSIb3DQEBAQUABIIBAFWfp760QQdWqPrqssF/JopiWwTZxowS4XUN1hJmOHoo
# 5g3kYBz6ng16WSNW3L2cI428vu/nzmGWG6YljAgZMrqtyP/3Cu1oMzBYJLxNxA0J
# hUvASLrrzOmM1vbwGP4hSIblLmCe78W8FZPTxRRwfG6Fcg0Yi2OZyE4BFPn++js5
# qlnMegBkEoRp0eqtymxVBlFSmk+jat31zTDBHafBzJTcuh4Aiee4XKBS0EbSpht9
# xJOKZIOz9RhPyu1bhIHexvYcUbAlaHwAR68AlVstZ9hfobEgkRCnLNQjQUEzi6G1
# tx0gKUK4PXF5WE+8vaLy+DAFyQu7KkI+6QCfZIMfJr2hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzIxWjAvBgkqhkiG9w0BCQQxIgQgveT+EyutObDw8VDWqXsO
# GR8IbSn5Kyy7H9dI+xpZVw4wDQYJKoZIhvcNAQEBBQAEggIAoXZU32ZLNakeem/f
# K61ppDvAf094vKhbKQrkQqyVh6rVv/D79NUq27NggdJcFlT8Q7F4e7ej8X+7ORW9
# 95xB3urrsbopVwxMCb4FWB81UFqSG90fqHQN0E2BJs9EKrNn96kidXtTssfByJ2e
# mWyOiGshF18w9kW33dZaSHw3gZ6guMp/wyyWy5xrvdehoSqZ9yaCdwQAh199pz/m
# 1c61Acwyqbz1Om+6irZWIqW7zaxtLq9IWOsowdRZhO4slC8gC5V7sr0oZ4jnRn5X
# 5ObI/1d7/h6RO2rbwiDkaVtttEHa4al6+5QkDTHbWw/3Jo8bkuffuyVwbidnXb6D
# khhF813vQ590lPYvFVZMsavta6iYcnXT1WfKU0lFY0YEZak9xkWn73eECmM/ZwsR
# fkeGq4rW96Qzzfx9NObHxe2Z8fW2fRuImrpva68bXSxX41xxSIWy1hnRj1EIH0/j
# L+RwtpsZswfb1zk6u4QbSDVMawF55XvkxyTfEJBCVFlN74tZ3xbqICDVhEILhawf
# PNMUPD5HStZqwg1UDLgSG89azwFy4iRGyS3P55ADmcZdJPFDv2Wko7CooOhZw9Cu
# CKEx8oEIUjXYNov1ugv2kL/u5ggMXvudVLn9Lt+722mTHkgjhXeugfIWK7Hq9yOC
# SuOW3NwC17HB8O0to/SmyZYZ0IY=
# SIG # End signature block
