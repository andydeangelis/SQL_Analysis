function Copy-DbaSysDbUserObject {
    <#
    .SYNOPSIS
        Imports all user objects found in source SQL Server's master, msdb and model databases to the destination.

    .DESCRIPTION
        Imports all user objects found in source SQL Server's master, msdb and model databases to the destination. This is useful because many DBAs store backup/maintenance procs/tables/triggers/etc (among other things) in master or msdb.

        It is also useful for migrating objects within the model database.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Classic
        Perform the migration the old way

    .PARAMETER Force
        Drop destination objects first. Has no effect if you use Classic. This doesn't work really well, honestly.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, SystemDatabase, UserObject
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaSysDbUserObject

    .EXAMPLE
        PS C:\> Copy-DbaSysDbUserObject -Source sqlserver2014a -Destination sqlcluster

        Copies user objects found in system databases master, msdb and model from sqlserver2014a instance to the sqlcluster instance.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [switch]$Force,
        [switch]$Classic,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        function get-sqltypename ($type) {
            switch ($type) {
                "VIEW" { "view" }
                "SQL_TABLE_VALUED_FUNCTION" { "User table valued fsunction" }
                "DEFAULT_CONSTRAINT" { "User default constraint" }
                "SQL_STORED_PROCEDURE" { "User stored procedure" }
                "RULE" { "User rule" }
                "SQL_INLINE_TABLE_VALUED_FUNCTION" { "User inline table valued function" }
                "SQL_TRIGGER" { "User server trigger" }
                "SQL_SCALAR_FUNCTION" { "User scalar function" }
                default { $type }
            }
        }
    }
    process {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting."
            return
        }

        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $destinstance" -Continue
            }

            $systemDbs = "master", "model", "msdb"

            if (-not $Classic) {
                foreach ($systemDb in $systemDbs) {
                    $smodb = $sourceServer.databases[$systemDb]
                    $destdb = $destserver.databases[$systemDb]

                    $tables = $smodb.Tables | Where-Object IsSystemObject -ne $true
                    $schemas = $smodb.Schemas | Where-Object IsSystemObject -ne $true

                    foreach ($schema in $schemas) {
                        $copyobject = [pscustomobject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Name              = $schema
                            Type              = "User schema in $systemDb"
                            Status            = $null
                            Notes             = $null
                            DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }

                        $destschema = $destdb.Schemas | Where-Object Name -eq $schema.Name
                        $schmadoit = $true

                        if ($destschema) {
                            if (-not $force) {
                                $copyobject.Status = "Skipped"
                                $copyobject.Notes = "Already exists on destination"
                                $schmadoit = $false
                            } else {
                                if ($PSCmdlet.ShouldProcess($destServer, "Dropping schema $schema in $systemDb")) {
                                    try {
                                        Write-Message -Level Verbose -Message "Force specified. Dropping $schema in $destdb on $destinstance"
                                        $destschema.Drop()
                                    } catch {
                                        $schmadoit = $false
                                        $copyobject.Status = "Failed"
                                        $copyobject.Notes = $_.Exception.InnerException.InnerException.InnerException.Message
                                    }
                                }
                            }
                        }

                        if ($schmadoit) {
                            $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
                            $null = $transfer.CopyAllObjects = $false
                            $null = $transfer.Options.WithDependencies = $true
                            $null = $transfer.ObjectList.Add($schema)
                            if ($PSCmdlet.ShouldProcess($destServer, "Attempting to add schema $($schema.Name) to $systemDb")) {
                                try {
                                    $sql = $transfer.ScriptTransfer()
                                    Write-Message -Level Debug -Message "$sql"
                                    $null = $destServer.Query($sql, $systemDb)
                                    $copyobject.Status = "Successful"
                                    $copyobject.Notes = "May have also created dependencies"
                                } catch {
                                    $copyobject.Status = "Failed"
                                    $copyobject.Notes = (Get-ErrorMessage -Record $_)
                                }
                            }
                        }

                        $copyobject | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }

                    foreach ($table in $tables) {
                        $copyobject = [pscustomobject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Name              = $table
                            Type              = "User table in $systemDb"
                            Status            = $null
                            Notes             = $null
                            DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }

                        $desttable = $destdb.Tables.Item($table.Name, $table.Schema)
                        $doit = $true

                        if ($desttable) {
                            if (-not $force) {
                                $copyobject.Status = "Skipped"
                                $copyobject.Notes = "Already exists on destination"
                                $doit = $false
                            } else {
                                if ($PSCmdlet.ShouldProcess($destServer, "Dropping table $table in $systemDb")) {
                                    try {
                                        Write-Message -Level Verbose -Message "Force specified. Dropping $table in $destdb on $destinstance"
                                        $desttable.Drop()
                                    } catch {
                                        $doit = $false
                                        $copyobject.Status = "Failed"
                                        $copyobject.Notes = $_.Exception.InnerException.InnerException.InnerException.Message
                                    }
                                }
                            }
                        }

                        if ($doit) {
                            $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
                            $null = $transfer.CopyAllObjects = $false
                            $null = $transfer.Options.WithDependencies = $true
                            $null = $transfer.ObjectList.Add($table)
                            if ($PSCmdlet.ShouldProcess($destServer, "Attempting to add table $table to $systemDb")) {
                                try {
                                    $sql = $transfer.ScriptTransfer()
                                    Write-Message -Level Debug -Message "$sql"
                                    $null = $destServer.Query($sql, $systemDb)
                                    $copyobject.Status = "Successful"
                                    $copyobject.Notes = "May have also created dependencies"
                                } catch {
                                    $copyobject.Status = "Failed"
                                    $copyobject.Notes = (Get-ErrorMessage -Record $_)
                                }
                            }
                        }
                        $copyobject | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }

                    $userobjects = Get-DbaModule -SqlInstance $sourceserver -Database $systemDb -ExcludeSystemObjects | Sort-Object Type
                    Write-Message -Level Verbose -Message "Copying from $systemDb"
                    foreach ($userobject in $userobjects) {

                        $name = "[$($userobject.SchemaName)].[$($userobject.Name)]"
                        $db = $userobject.Database
                        $type = get-sqltypename $userobject.Type
                        $sql = $userobject.Definition
                        $schema = $userobject.SchemaName

                        $copyobject = [pscustomobject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Name              = $name
                            Type              = "$type in $systemDb"
                            Status            = $null
                            Notes             = $null
                            DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }
                        Write-Message -Level Debug -Message $sql
                        try {
                            Write-Message -Level Verbose -Message "Searching for $name in $db on $destinstance"
                            $result = Get-DbaModule -SqlInstance $destServer -ExcludeSystemObjects -Database $db |
                                Where-Object { $psitem.Name -eq $userobject.Name -and $psitem.Type -eq $userobject.Type }
                            if ($result) {
                                Write-Message -Level Verbose -Message "Found $name in $db on $destinstance"
                                if (-not $Force) {
                                    $copyobject.Status = "Skipped"
                                    $copyobject.Notes = "Already exists on destination"
                                } else {
                                    $smobject = switch ($userobject.Type) {
                                        "VIEW" { $smodb.Views.Item($userobject.Name, $userobject.SchemaName) }
                                        "SQL_STORED_PROCEDURE" { $smodb.StoredProcedures.Item($userobject.Name, $userobject.SchemaName) }
                                        "RULE" { $smodb.Rules.Item($userobject.Name, $userobject.SchemaName) }
                                        "SQL_TRIGGER" { $smodb.Triggers.Item($userobject.Name, $userobject.SchemaName) }
                                        "SQL_TABLE_VALUED_FUNCTION" { $smodb.UserDefinedFunctions.Item($name) }
                                        "SQL_INLINE_TABLE_VALUED_FUNCTION" { $smodb.UserDefinedFunctions.Item($name) }
                                        "SQL_SCALAR_FUNCTION" { $smodb.UserDefinedFunctions.Item($name) }
                                    }

                                    if ($smobject) {
                                        Write-Message -Level Verbose -Message "Force specified. Dropping $smobject on $destdb on $destinstance using SMO"
                                        $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
                                        $null = $transfer.CopyAllObjects = $false
                                        $null = $transfer.Options.WithDependencies = $true
                                        $null = $transfer.ObjectList.Add($smobject)
                                        $null = $transfer.Options.ScriptDrops = $true
                                        $dropsql = $transfer.ScriptTransfer()
                                        Write-Message -Level Debug -Message "$dropsql"
                                        if ($PSCmdlet.ShouldProcess($destServer, "Attempting to drop $type $name from $systemDb")) {
                                            $null = $destdb.Query("$dropsql")
                                        }
                                    } else {
                                        if ($PSCmdlet.ShouldProcess($destServer, "Attempting to drop $type $name from $systemDb using T-SQL")) {
                                            $null = $destdb.Query("DROP FUNCTION $($userobject.name)")
                                        }
                                    }
                                    if ($PSCmdlet.ShouldProcess($destServer, "Attempting to add $type $name to $systemDb")) {
                                        $null = $destdb.Query("$sql")
                                        $copyobject.Status = "Successful"
                                    }
                                }
                            } else {
                                if ($PSCmdlet.ShouldProcess($destServer, "Attempting to add $type $name to $systemDb")) {
                                    $null = $destdb.Query("$sql")
                                    $copyobject.Status = "Successful"
                                }
                            }
                        } catch {
                            try {
                                $smobject = switch ($userobject.Type) {
                                    "VIEW" { $smodb.Views.Item($userobject.Name, $userobject.SchemaName) }
                                    "SQL_STORED_PROCEDURE" { $smodb.StoredProcedures.Item($userobject.Name, $userobject.SchemaName) }
                                    "RULE" { $smodb.Rules.Item($userobject.Name, $userobject.SchemaName) }
                                    "SQL_TRIGGER" { $smodb.Triggers.Item($userobject.Name, $userobject.SchemaName) }
                                }
                                if ($smobject) {
                                    $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
                                    $null = $transfer.CopyAllObjects = $false
                                    $null = $transfer.Options.WithDependencies = $true
                                    $null = $transfer.ObjectList.Add($smobject)
                                    $sql = $transfer.ScriptTransfer()
                                    Write-Message -Level Debug -Message "$sql"
                                    Write-Message -Level Verbose -Message "Adding $smoobject on $destdb on $destinstance"
                                    if ($PSCmdlet.ShouldProcess($destServer, "Attempting to add $type $name to $systemDb")) {
                                        $null = $destdb.Query("$sql")
                                    }
                                    $copyobject.Status = "Successful"
                                    $copyobject.Notes = "May have also installed dependencies"
                                } else {
                                    $copyobject.Status = "Failed"
                                    $copyobject.Notes = (Get-ErrorMessage -Record $_)
                                }
                            } catch {
                                $copyobject.Status = "Failed"
                                $copyobject.Notes = (Get-ErrorMessage -Record $_)
                            }
                        }
                        $copyobject | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                }
            } else {
                foreach ($systemDb in $systemDbs) {
                    $sysdb = $sourceServer.databases[$systemDb]
                    $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $sysdb
                    $transfer.CopyAllObjects = $false
                    $transfer.CopyAllDatabaseTriggers = $true
                    $transfer.CopyAllDefaults = $true
                    $transfer.CopyAllRoles = $true
                    $transfer.CopyAllRules = $true
                    $transfer.CopyAllSchemas = $true
                    $transfer.CopyAllSequences = $true
                    $transfer.CopyAllSqlAssemblies = $true
                    $transfer.CopyAllSynonyms = $true
                    $transfer.CopyAllTables = $true
                    $transfer.CopyAllViews = $true
                    $transfer.CopyAllStoredProcedures = $true
                    $transfer.CopyAllUserDefinedAggregates = $true
                    $transfer.CopyAllUserDefinedDataTypes = $true
                    $transfer.CopyAllUserDefinedTableTypes = $true
                    $transfer.CopyAllUserDefinedTypes = $true
                    $transfer.CopyAllUserDefinedFunctions = $true
                    $transfer.CopyAllUsers = $true
                    $transfer.PreserveDbo = $true
                    $transfer.Options.AllowSystemObjects = $false
                    $transfer.Options.ContinueScriptingOnError = $true
                    $transfer.Options.IncludeDatabaseRoleMemberships = $true
                    $transfer.Options.Indexes = $true
                    $transfer.Options.Permissions = $true
                    $transfer.Options.WithDependencies = $false

                    Write-Message -Level Output -Message "Copying from $systemDb."
                    try {
                        $sqlQueries = $transfer.ScriptTransfer()

                        foreach ($sql in $sqlQueries) {
                            Write-Message -Level Debug -Message "$sql"
                            if ($PSCmdlet.ShouldProcess($destServer, $sql)) {
                                try {
                                    $destServer.Query($sql, $systemDb)
                                } catch {
                                    # Don't care - long story having to do with duplicate stuff
                                    # here to avoid an empty catch
                                    $null = 1
                                }
                            }
                        }
                    } catch {
                        # Don't care - long story having to do with duplicate stuff
                        # here to avoid an empty catch
                        $null = 1
                    }
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUmOZnLzZz86cwf7N++RX8W8au
# pwqgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFKKgf4HVCL7pMVt0PpHjyNkL4eHKMA0G
# CSqGSIb3DQEBAQUABIIBAH2DbqkMjwdPco4R8ANrfYe1926F/22NHTL/N0Mo5ZO3
# 9x1ftF2CcN0BrX5Bn2OB6fJW+zh+jotvV0HL8nO6vhsM0ZwccLd+2fs9qJZcu+3d
# aDymjrRt3X8jHvrPo30qcAOBuUmYKzGd2m1a2leaYm8EvhDRg5Z2zzfXVuRBI7L1
# P4sEbMeBNhY8CIcuTfW0kqJnIlKVxcHI+E/1MRpdJeMrRz/JAJZTmmJHGLG4YW6a
# w3o/gCQPcmu3ReCsKOE/iuRRlty8ozfdvyP5lrPvVA3hVbuFOtTAuig2dwnwS22B
# wWBlnbCqYl2yPKGUtUfPK/tCBlL+PO4sElCaj+0FRimhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzE0WjAvBgkqhkiG9w0BCQQxIgQgjXPn6SLaXh/qRyk6xIui
# EdaNfNndmpJKNVbuBtPScbgwDQYJKoZIhvcNAQEBBQAEggIAh4NF4QMC/ogzr2SR
# eZrSHNXoS617qiXykwgaeFmnkbL64PGZlRVNnuzhcUaT5wDBUaMmM7hgG97BZlXY
# 9Fs7f12eSjiSixJNTHilsGtWxSQ4SV76adIocjx5WzQVOzRqduH8PC+o/W1TPykH
# bLULYTM03NV97O7ItCAu3m3ipbLbwFixfzy7GQ+dVuDUfT1Pbs0cABv6UHp0Q4A7
# l+5pVuqIC0LD323wlhGm5+/g8dDIBPv1KJImBKGUt97kyVi7psx1v15pmiEx7pRV
# IhmZAfIV+Yu/dDyVd1MgmZ8u3MjprmAO2rlQIDjdf2lRESuxO9BEpm8j1c5UThFs
# D4IMersY5ew0bcfGjF+fuHr/0PCdv89HPqYQNboLNQi624IYlKVrw/3CFO2Y7m63
# lP5ZE07c4h+SHaN59MdFSBd3KXN6QwCzS3gcxx6EY+NqCz9qK2jW0f8NGt1bS4Hx
# 3T9HbR6n9evjcCZHtZuxqjc9JKlHbpzx2z1BDyU3W1worv1hwDlSMzm1e4ksbiH9
# or7hT7tA7vISlamhCnd/BkghutPTwxB27V3ZbF3TaUy4VLCfOKtdeaZp5f/dZC+7
# zF8aAj/FRbLtD65OTAq+e/jamr47z2rN0Dv8wbMarB8aKyBTxVovUe8u2IuZoXWh
# cIGV6rZ24txKlAXxxNcJgz21oL8=
# SIG # End signature block
