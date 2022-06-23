function New-DbaDbTable {
    <#
    .SYNOPSIS
        Creates a new table in a database

    .DESCRIPTION
        Creates a new table in a database

   .PARAMETER SqlInstance
       The target SQL Server instance or instances.

    .PARAMETER SqlCredential
       Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases where the table will be created

    .PARAMETER Name
        The name of the table

    .PARAMETER Schema
        The schema for the table, defaults to dbo

    .PARAMETER ColumnMap
        Hashtable for easy column creation. See Examples for details

    .PARAMETER ColumnObject
        If you want to get fancy, you can build your own column objects and pass them in

    .PARAMETER InputObject
        Allows piped input from Get-DbaDatabase

    .PARAMETER AnsiNullsStatus
        No information provided by Microsoft

    .PARAMETER ChangeTrackingEnabled
        No information provided by Microsoft

    .PARAMETER DataSourceName
        No information provided by Microsoft

    .PARAMETER Durability
        No information provided by Microsoft

    .PARAMETER ExternalTableDistribution
        No information provided by Microsoft

    .PARAMETER FileFormatName
        No information provided by Microsoft

    .PARAMETER FileGroup
        No information provided by Microsoft

    .PARAMETER FileStreamFileGroup
        No information provided by Microsoft

    .PARAMETER FileStreamPartitionScheme
        No information provided by Microsoft

    .PARAMETER FileTableDirectoryName
        No information provided by Microsoft

    .PARAMETER FileTableNameColumnCollation
        No information provided by Microsoft

    .PARAMETER FileTableNamespaceEnabled
        No information provided by Microsoft

    .PARAMETER HistoryTableName
        No information provided by Microsoft

    .PARAMETER HistoryTableSchema
        No information provided by Microsoft

    .PARAMETER IsExternal
        No information provided by Microsoft

    .PARAMETER IsFileTable
        No information provided by Microsoft

    .PARAMETER IsMemoryOptimized
        No information provided by Microsoft

    .PARAMETER IsSystemVersioned
        No information provided by Microsoft

    .PARAMETER Location
        No information provided by Microsoft

    .PARAMETER LockEscalation
        No information provided by Microsoft

    .PARAMETER Owner
        No information provided by Microsoft

    .PARAMETER PartitionScheme
        No information provided by Microsoft

    .PARAMETER QuotedIdentifierStatus
        No information provided by Microsoft

    .PARAMETER RejectSampleValue
        No information provided by Microsoft

    .PARAMETER RejectType
        No information provided by Microsoft

    .PARAMETER RejectValue
        No information provided by Microsoft

    .PARAMETER RemoteDataArchiveDataMigrationState
        No information provided by Microsoft

    .PARAMETER RemoteDataArchiveEnabled
        No information provided by Microsoft

    .PARAMETER RemoteDataArchiveFilterPredicate
        No information provided by Microsoft

    .PARAMETER RemoteObjectName
        No information provided by Microsoft

    .PARAMETER RemoteSchemaName
        No information provided by Microsoft

    .PARAMETER RemoteTableName
        No information provided by Microsoft

    .PARAMETER RemoteTableProvisioned
        No information provided by Microsoft

    .PARAMETER ShardingColumnName
        No information provided by Microsoft

    .PARAMETER TextFileGroup
        No information provided by Microsoft

    .PARAMETER TrackColumnsUpdatedEnabled
        No information provided by Microsoft

    .PARAMETER HistoryRetentionPeriod
        No information provided by Microsoft

    .PARAMETER HistoryRetentionPeriodUnit
        No information provided by Microsoft

    .PARAMETER DwTableDistribution
        No information provided by Microsoft

    .PARAMETER RejectedRowLocation
        No information provided by Microsoft

    .PARAMETER OnlineHeapOperation
        No information provided by Microsoft

    .PARAMETER LowPriorityMaxDuration
        No information provided by Microsoft

    .PARAMETER DataConsistencyCheck
        No information provided by Microsoft

    .PARAMETER LowPriorityAbortAfterWait
        No information provided by Microsoft

    .PARAMETER MaximumDegreeOfParallelism
        No information provided by Microsoft

    .PARAMETER IsNode
        No information provided by Microsoft

    .PARAMETER IsEdge
        No information provided by Microsoft

    .PARAMETER IsVarDecimalStorageFormatEnabled
        No information provided by Microsoft

    .PARAMETER Passthru
        Don't create the table, just print the table script on the screen.

    .PARAMETER WhatIf
       Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
       Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
       By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
       This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
       Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
       Tags: table
       Author: Chrissy LeMaire (@cl)
       Website: https://dbatools.io
       Copyright: (c) 2019 by dbatools, licensed under MIT
       License: MIT https://opensource.org/licenses/MIT

    .LINK
       https://dbatools.io/New-DbaDbTable

    .EXAMPLE
       PS C:\> $col = @{
       >> Name      = 'test'
       >> Type      = 'varchar'
       >> MaxLength = 20
       >> Nullable  = $true
       >> }
       PS C:\> New-DbaDbTable -SqlInstance sql2017 -Database tempdb -Name testtable -ColumnMap $col

       Creates a new table on sql2017 in tempdb with the name testtable and one column

    .EXAMPLE
       PS C:\> $cols = @( )
       >> $cols += @{
       >>     Name              = 'Id'
       >>     Type              = 'varchar'
       >>     MaxLength         = 36
       >>     DefaultExpression = 'NEWID()'
       >> }
       >> $cols += @{
       >>     Name          = 'Since'
       >>     Type          = 'datetime2'
       >>     DefaultString = '2021-12-31'
       >> }
       PS C:\> New-DbaDbTable -SqlInstance sql2017 -Database tempdb -Name testtable -ColumnMap $cols

       Creates a new table on sql2017 in tempdb with the name testtable and two columns.
       Uses "DefaultExpression" to interpret the value "NEWID()" as an expression regardless of the data type of the column.
       Uses "DefaultString" to interpret the value "2021-12-31" as a string regardless of the data type of the column.

    .EXAMPLE
        PS C:\> # Create collection
        >> $cols = @()

        >> # Add columns to collection
        >> $cols += @{
        >>     Name      = 'testId'
        >>     Type      = 'int'
        >>     Identity  = $true
        >> }
        >> $cols += @{
        >>     Name      = 'test'
        >>     Type      = 'varchar'
        >>     MaxLength = 20
        >>     Nullable  = $true
        >> }
        >> $cols += @{
        >>     Name      = 'test2'
        >>     Type      = 'int'
        >>     Nullable  = $false
        >> }
        >> $cols += @{
        >>     Name      = 'test3'
        >>     Type      = 'decimal'
        >>     MaxLength = 9
        >>     Nullable  = $true
        >> }
        >> $cols += @{
        >>     Name      = 'test4'
        >>     Type      = 'decimal'
        >>     Precision = 8
        >>     Scale = 2
        >>     Nullable  = $false
        >> }
        >> $cols += @{
        >>     Name      = 'test5'
        >>     Type      = 'Nvarchar'
        >>     MaxLength = 50
        >>     Nullable  =  $false
        >>     Default  =  'Hello'
        >>     DefaultName = 'DF_Name_test5'
        >> }
        >> $cols += @{
        >>     Name      = 'test6'
        >>     Type      = 'int'
        >>     Nullable  =  $false
        >>     Default  =  '0'
        >> }
        >> $cols += @{
        >>     Name      = 'test7'
        >>     Type      = 'smallint'
        >>     Nullable  =  $false
        >>     Default  =  100
        >> }
        >> $cols += @{
        >>     Name      = 'test8'
        >>     Type      = 'Nchar'
        >>     MaxLength = 3
        >>     Nullable  =  $false
        >>     Default  =  'ABC'
        >> }
        >> $cols += @{
        >>     Name      = 'test9'
        >>     Type      = 'char'
        >>     MaxLength = 4
        >>     Nullable  =  $false
        >>     Default  =  'XPTO'
        >> }
        >> $cols += @{
        >>     Name      = 'test10'
        >>     Type      = 'datetime'
        >>     Nullable  =  $false
        >>     Default  =  'GETDATE()'
        >> }

        PS C:\> New-DbaDbTable -SqlInstance sql2017 -Database tempdb -Name testtable -ColumnMap $cols

        Creates a new table on sql2017 in tempdb with the name testtable and ten columns.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String[]]$Database,
        [String]$Name,
        [String]$Schema = "dbo",
        [hashtable[]]$ColumnMap,
        [Microsoft.SqlServer.Management.Smo.Column[]]$ColumnObject,
        [Switch]$AnsiNullsStatus,
        [Switch]$ChangeTrackingEnabled,
        [String]$DataSourceName,
        [Microsoft.SqlServer.Management.Smo.DurabilityType]$Durability,
        [Microsoft.SqlServer.Management.Smo.ExternalTableDistributionType]$ExternalTableDistribution,
        [String]$FileFormatName,
        [String]$FileGroup,
        [String]$FileStreamFileGroup,
        [String]$FileStreamPartitionScheme,
        [String]$FileTableDirectoryName,
        [String]$FileTableNameColumnCollation,
        [Switch]$FileTableNamespaceEnabled,
        [String]$HistoryTableName,
        [String]$HistoryTableSchema,
        [Switch]$IsExternal,
        [Switch]$IsFileTable,
        [Switch]$IsMemoryOptimized,
        [Switch]$IsSystemVersioned,
        [String]$Location,
        [Microsoft.SqlServer.Management.Smo.LockEscalationType]$LockEscalation,
        [String]$Owner,
        [String]$PartitionScheme,
        [Switch]$QuotedIdentifierStatus,
        [Double]$RejectSampleValue,
        [Microsoft.SqlServer.Management.Smo.ExternalTableRejectType]$RejectType,
        [Double]$RejectValue,
        [Microsoft.SqlServer.Management.Smo.RemoteDataArchiveMigrationState]$RemoteDataArchiveDataMigrationState,
        [Switch]$RemoteDataArchiveEnabled,
        [String]$RemoteDataArchiveFilterPredicate,
        [String]$RemoteObjectName,
        [String]$RemoteSchemaName,
        [String]$RemoteTableName,
        [Switch]$RemoteTableProvisioned,
        [String]$ShardingColumnName,
        [String]$TextFileGroup,
        [Switch]$TrackColumnsUpdatedEnabled,
        [Int32]$HistoryRetentionPeriod,
        [Microsoft.SqlServer.Management.Smo.TemporalHistoryRetentionPeriodUnit]$HistoryRetentionPeriodUnit,
        [Microsoft.SqlServer.Management.Smo.DwTableDistributionType]$DwTableDistribution,
        [String]$RejectedRowLocation,
        [Switch]$OnlineHeapOperation,
        [Int32]$LowPriorityMaxDuration,
        [Switch]$DataConsistencyCheck,
        [Microsoft.SqlServer.Management.Smo.AbortAfterWait]$LowPriorityAbortAfterWait,
        [Int32]$MaximumDegreeOfParallelism,
        [Switch]$IsNode,
        [Switch]$IsEdge,
        [Switch]$IsVarDecimalStorageFormatEnabled,
        [switch]$Passthru,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        function Get-SqlType {
            param([string]$TypeName)
            switch ($TypeName) {
                'Boolean' { [Data.SqlDbType]::Bit }
                'Byte[]' { [Data.SqlDbType]::VarBinary }
                'Byte' { [Data.SQLDbType]::VarBinary }
                'Datetime' { [Data.SQLDbType]::DateTime }
                'Decimal' { [Data.SqlDbType]::Decimal }
                'Double' { [Data.SqlDbType]::Float }
                'Guid' { [Data.SqlDbType]::UniqueIdentifier }
                'Int16' { [Data.SQLDbType]::SmallInt }
                'Int32' { [Data.SQLDbType]::Int }
                'Int64' { [Data.SqlDbType]::BigInt }
                'UInt16' { [Data.SQLDbType]::SmallInt }
                'UInt32' { [Data.SQLDbType]::Int }
                'UInt64' { [Data.SqlDbType]::BigInt }
                'Single' { [Data.SqlDbType]::Decimal }
                default { [Data.SqlDbType]::VarChar }
            }
        }
    }
    process {
        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Database) -or (Test-Bound -Not -ParameterName Name)) {
                Stop-Function -Message "You must specify one or more databases and one Name when using the SqlInstance parameter."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            if ($Pscmdlet.ShouldProcess("Creating new table [$Schema].[$Name] in $db on $server")) {
                # Test if table already exists. This ways we can drop the table if part of the creation fails.
                $existingTable = $db.tables | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Name }
                if ($existingTable) {
                    Stop-Function -Message "Table [$Schema].[$Name] already exists in $db on $server" -Continue
                }
                try {
                    $object = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Table $db, $Name, $Schema
                    $properties = $PSBoundParameters | Where-Object Key -notin 'SqlInstance', 'SqlCredential', 'Name', 'Schema', 'ColumnMap', 'ColumnObject', 'InputObject', 'EnableException', 'Passthru'

                    foreach ($prop in $properties.Key) {
                        $object.$prop = $prop
                    }

                    foreach ($column in $ColumnObject) {
                        $object.Columns.Add($column)
                    }

                    foreach ($column in $ColumnMap) {
                        $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]$($column.Type)
                        if ($sqlDbType -eq 'VarBinary' -or $sqlDbType -in @('VarChar', 'NVarChar', 'Char', 'NChar')) {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.MaxLength
                            } else {
                                $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$(Get-SqlType $column.DataType.Name)Max"
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } elseif ($sqlDbType -eq 'Decimal') {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.MaxLength
                            } elseif ($column.Precision -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.Precision, $column.Scale
                            } else {
                                $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$(Get-SqlType $column.DataType.Name)Max"
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } else {
                            $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                        }
                        $sqlColumn = New-Object Microsoft.SqlServer.Management.Smo.Column $object, $column.Name, $dataType
                        $sqlColumn.Nullable = $column.Nullable

                        if ($column.DefaultName) {
                            $dfName = $column.DefaultName
                        } else {
                            $dfName = "DF_$name`_$($column.Name)"
                        }
                        if ($column.DefaultExpression) {
                            # override the default that would add quotes to an expression
                            $sqlColumn.AddDefaultConstraint($dfName).Text = $column.DefaultExpression
                        } elseif ($column.DefaultString) {
                            # override the default that would not add quotes to a date string
                            $sqlColumn.AddDefaultConstraint($dfName).Text = "'$($column.DefaultString)'"
                        } elseif ($column.Default) {
                            if ($sqlDbType -in @('NVarchar', 'NChar', 'NVarcharMax', 'NCharMax')) {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = "N'$($column.Default)'"
                            } elseif ($sqlDbType -in @('Varchar', 'Char', 'VarcharMax', 'CharMax')) {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = "'$($column.Default)'"
                            } else {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = $column.Default
                            }
                        }

                        if ($column.Identity) {
                            $sqlColumn.Identity = $true
                            if ($column.IdentitySeed) {
                                $sqlColumn.IdentitySeed = $column.IdentitySeed
                            }
                            if ($column.IdentityIncrement) {
                                $sqlColumn.IdentityIncrement = $column.IdentityIncrement
                            }
                        }
                        $object.Columns.Add($sqlColumn)
                    }

                    # user has specified a schema that does not exist yet
                    $schemaObject = $null
                    if (-not ($db | Get-DbaDbSchema -Schema $Schema -IncludeSystemSchemas)) {
                        Write-Message -Level Verbose -Message "Schema $Schema does not exist in $db and will be created."
                        $schemaObject = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Schema $db, $Schema
                    }

                    if ($Passthru) {
                        $ScriptingOptionsObject = New-DbaScriptingOption
                        $ScriptingOptionsObject.ContinueScriptingOnError = $false
                        $ScriptingOptionsObject.DriAllConstraints = $true

                        if ($schemaObject) {
                            $schemaObject.Script($ScriptingOptionsObject)
                        }

                        $object.Script($ScriptingOptionsObject)
                    } else {
                        if ($schemaObject) {
                            $null = Invoke-Create -Object $schemaObject
                        }
                        $null = Invoke-Create -Object $object
                    }
                    $db | Get-DbaDbTable -Table "[$Schema].[$Name]"
                } catch {
                    $exception = $_
                    Write-Message -Level Verbose -Message "Failed to create table or failure while adding constraints. Will try to remove table (and schema)."
                    try {
                        $object.Refresh()
                        $object.DropIfExists()
                        if ($schemaObject) {
                            $schemaObject.Refresh()
                            $schemaObject.DropIfExists()
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Failed to drop table: $_. Maybe table still exists."
                    }
                    Stop-Function -Message "Failure" -ErrorRecord $exception -Continue
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCf1o37srU+sQzR
# cVYVsFQrHzqtBEqQDQ9NxEx8bWKX2qCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCD8z+N2tEC+VJsuES8M6qOHSjcFj+/V4gpt
# vp45WBzCcTANBgkqhkiG9w0BAQEFAASCAQAh/Ld1xYWLzjdbEo3R1o6d14Sftk7u
# b4pWXVLugptzxrl9Z5TQ8HkMSckylEP4RbNpMXqniDJINaw9Uw9LoCsQCEyI9hli
# RIwcSXNOEO8B/eWgUMpmoArCKlL9XtK4KYkZbIZM1hgFCObIMHnMDdOEEdE5u9i3
# JXUODeC71HhIWLlLnyWkMXbpOtgfmN9qQKwZiwjEyIPA3tOkxA6Wx1YIuoRitvj2
# 171AtgX6LZCpcEeRTTJ5hWRc/VDj9mDRlMLE4dqkiQyHCiEYqEK4eC0eePfVn+Aa
# uIEHBmFSyHXFrhHP/NdrZDVTsnMCwSz0ZBVu21FXCafRmpE5DeGwuprqoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMzNlowLwYJKoZIhvcNAQkEMSIEIBs2h+5N
# Ppxh4LWn9M1FWg7Z0aFJCuX8VyYuC+4lmEa6MA0GCSqGSIb3DQEBAQUABIICAD2U
# RcD0DMBcZXDOJXVIBGhmYxvPxPuhIuAIEYX/7Np0rkxfrPMGzRAZYR474DNtxep0
# Pz6iuDhHy4AZ9xG2mown2cvzjE/qH3MWDuMrB2Jc2HlF6wEOpknASoyTCBQpbetF
# ij8od9BHUJnlZ3u3NuRdj10fe9qIG4DDRM1F3moFIbnEaHQxRrTkt+ZunBC9W8Tk
# e2cYwK0jZbs4Kip7GKqsUkSdBPbkWcYNiTrhGR381/SBEPA4oDwA4+MKGt46s07y
# VO0HBGP7teeHvKvPP3aLfETuRINJ1L/KhjZdm1AsXBt52JAliMWqVBmgucU2e4xW
# n01VDHTcdgwlb4MZfzXLWPH/RIsUlh93SblzrC5oa+Th+D39Kdz6fOge4bcIAkwA
# m9LzxCXb/SkFDnkyblXhCDKiBEgUYATAMz/Jn1dg6kx3ptf96ZYM/6LB5FsyzqCr
# RlRDpYvBYXSWys/Gia4gspwsPRkjCdY2gUiSJEKT0Ep1xrjnfdQUqflB3ohb02uz
# DnnD17uLDkabAaGMvOlqTNBCLhBgDZasXpj2JCgKxRENQOSMttTKfW4Dg6cbMg1h
# zeBi6szgLWJnAC1661YcEebtdCZzqXRDsxCh4+05oBd5j020p97Sd4hRZmOSfVax
# nEmMbx2cfsPY+aAefJc2+C8rBrIE2bPn1QDm66KQ
# SIG # End signature block
