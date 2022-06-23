function Write-DbaDbTableData {
    <#
    .SYNOPSIS
        Writes data to a SQL Server table.

    .DESCRIPTION
        Writes a .NET DataTable to a SQL Server table using SQL Bulk Copy.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database where the Input Object data will be written.

    .PARAMETER InputObject
        This is the DataTable (or data row) to import to SQL Server.

        It is very important to understand how different types of objects are beeing processed to get the best performance.
        The best performance is achieved when using the DataSet data type. If the data to be imported are determined with Invoke-DbaQuery, the option "-As DataSet" should be used. Then all records are imported in a single call of SqlBulkCopy.
        Also the data type DataTable can lead to an import of all records in a single call of SqlBulkCopy. However, it should be noted that "$varWithDataTable | Write-DbaDbTableData" causes the pipeline to convert the single object of type DataTable to a series of objects of type DataRow. These in turn lead to single calls of SqlBulkCopy per record, which negatively affects performance. This is also the reason why the use of the DataRow data type is generally discouraged.
        When using objects of type PSObject, these are first all combined into an internal object of type DataTable and then imported in a single call of SqlBulkCopy.

    .PARAMETER Table
        The table name to import data into. You can specify a one, two, or three part table name. If you specify a one or two part name, you must also use -Database.

        If the table does not exist, you can use -AutoCreateTable to automatically create the table. The table will be created with sub-optimal data types such as nvarchar(max).

        If the object has special characters please wrap them in square brackets [ ].
        Using dbo.First.Table will try to import to a table named 'Table' on schema 'First' and database 'dbo'.
        The correct way to import to a table named 'First.Table' on schema 'dbo' is by passing dbo.[First].[Table].
        Any actual usage of the ] must be escaped by duplicating the ] character.
        The correct way to import to a table Name] in schema Schema.Name is by passing [Schema.Name].[Name]]].

    .PARAMETER Schema
        Defaults to dbo if no schema is specified.

    .PARAMETER BatchSize
        The BatchSize for the import defaults to 50000.

    .PARAMETER NotifyAfter
        Sets the option to show the notification after so many rows of import. Defaults to 5000 rows.

    .PARAMETER AutoCreateTable
        If this switch is enabled, the table will be created if it does not already exist. The table will be created with sub-optimal data types such as nvarchar(max).

    .PARAMETER NoTableLock
        If this switch is enabled, a table lock (TABLOCK) will not be placed on the destination table. By default, this operation will lock the destination table while running.

    .PARAMETER CheckConstraints
        If this switch is enabled, the SqlBulkCopy option to process check constraints will be enabled.

        Per Microsoft "Check constraints while data is being inserted. By default, constraints are not checked."

    .PARAMETER FireTriggers
        If this switch is enabled, the SqlBulkCopy option to fire insert triggers will be enabled.

        Per Microsoft "When specified, cause the server to fire the insert triggers for the rows being inserted into the Database."

    .PARAMETER KeepIdentity
        If this switch is enabled, the SqlBulkCopy option to preserve source identity values will be enabled.

        Per Microsoft "Preserve source identity values. When not specified, identity values are assigned by the destination."

    .PARAMETER KeepNulls
        If this switch is enabled, the SqlBulkCopy option to preserve NULL values will be enabled.

        Per Microsoft "Preserve null values in the destination table regardless of the settings for default values. When not specified, null values are replaced by default values where applicable."

    .PARAMETER Truncate
        If this switch is enabled, the destination table will be truncated after prompting for confirmation.

    .PARAMETER BulkCopyTimeOut
        Value in seconds for the BulkCopy operations timeout. The default is 30 seconds.

    .PARAMETER ColumnMap
        By default, the bulk insert tries to automap columns. When it doesn't work as desired, this parameter will help. Check out the examples for more information.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER UseDynamicStringLength
        By default, all string columns will be NVARCHAR(MAX).
        If this switch is enabled, all columns will get the length specified by the column's MaxLength property (if specified).

    .NOTES
        Tags: Table, Data, Insert
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Write-DbaDbTableData

    .EXAMPLE
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers

        Performs a bulk insert of all the data in customers.csv into database mydb, schema dbo, table customers. A progress bar will be shown as rows are inserted. If the destination table does not exist, the import will be halted.

    .EXAMPLE
        PS C:\> $tableName = "MyTestData"
        PS C:\> $query = "SELECT name, create_date, owner_sid FROM sys.databases"
        PS C:\> $dataset = Invoke-DbaQuery -SqlInstance 'localhost,1417' -SqlCredential $containerCred -Database master -Query $query -As DataSet
        PS C:\> $dataset | Write-DbaDbTableData -SqlInstance 'localhost,1417' -SqlCredential $containerCred -Database tempdb -Table $tableName -AutoCreateTable

        Pulls data from a SQL Server instance and then performs a bulk insert of the dataset to a new, auto-generated table tempdb.dbo.MyTestData.

    .EXAMPLE
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers -AutoCreateTable -Confirm

        Performs a bulk insert of all the data in customers.csv. If mydb.dbo.customers does not exist, it will be created with inefficient but forgiving DataTypes.

        Prompts for confirmation before a variety of steps.

    .EXAMPLE
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers -Truncate

        Performs a bulk insert of all the data in customers.csv. Prior to importing into mydb.dbo.customers, the user is informed that the table will be truncated and asks for confirmation. The user is prompted again to perform the import.

    .EXAMPLE
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance sql2014 -InputObject $DataTable -Database mydb -Table customers -KeepNulls

        Performs a bulk insert of all the data in customers.csv into mydb.dbo.customers. Because Schema was not specified, dbo was used. NULL values in the destination table will be preserved.

    .EXAMPLE
        PS C:\> $passwd = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
        PS C:\> $AzureCredential = New-Object System.Management.Automation.PSCredential("AzureAccount"),$passwd)
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance AzureDB.database.windows.net -InputObject $DataTable -Database mydb -Table customers -KeepNulls -SqlCredential $AzureCredential -BulkCopyTimeOut 300

        This performs the same operation as the previous example, but against a SQL Azure Database instance using the required credentials.

    .EXAMPLE
        PS C:\> $process = Get-Process
        PS C:\> Write-DbaDbTableData -InputObject $process -SqlInstance sql2014 -Table "[[DbName]]].[Schema.With.Dots].[`"[Process]]`"]" -AutoCreateTable

        Creates a table based on the Process object with over 60 columns, converted from PowerShell data types to SQL Server data types. After the table is created a bulk insert is performed to add process information into the table
        Writes the results of Get-Process to a table named: "[Process]" in schema named: Schema.With.Dots in database named: [DbName]
        The Table name, Schema name and Database name must be wrapped in square brackets [ ]
        Special characters like " must be escaped by a ` character.
        In addition any actual instance of the ] character must be escaped by being duplicated.

        This is an example of the type conversion in action. All process properties are converted, including special types like TimeSpan. Script properties are resolved before the type conversion starts thanks to ConvertTo-DbaDataTable.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance SRV1
        PS C:\> $server.Invoke("CREATE TABLE tempdb.dbo.test (col1 INT, col2 VARCHAR(100))")
        PS C:\> $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT 123 AS value1, 'Hello world' AS value2" -As DataSet
        PS C:\> $data | Write-DbaDbTableData -SqlInstance $server -Table 'tempdb.dbo.test' -ColumnMap @{ value1 = 'col1' ; value2 = 'col2' }

        The dataset column 'value1' is inserted into SQL column 'col1' and dataset column value2 is inserted into the SQL Column 'col2'. All other columns are ignored and therefore null or default values.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [DbaInstanceParameter]$SqlInstance,
        [ValidateNotNull()]
        [PSCredential]$SqlCredential,
        [object]$Database,
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("DataTable")]
        [ValidateNotNull()]
        [object]$InputObject,
        [Parameter(Position = 3, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Table,
        [Parameter(Position = 4)]
        [ValidateNotNullOrEmpty()]
        [string]$Schema = 'dbo',
        [ValidateNotNull()]
        [int]$BatchSize = 50000,
        [ValidateNotNull()]
        [int]$NotifyAfter = 5000,
        [switch]$AutoCreateTable,
        [switch]$NoTableLock,
        [switch]$CheckConstraints,
        [switch]$FireTriggers,
        [switch]$KeepIdentity,
        [switch]$KeepNulls,
        [switch]$Truncate,
        [ValidateNotNull()]
        [int]$BulkCopyTimeOut = 5000,
        [hashtable]$ColumnMap,
        [switch]$EnableException,
        [switch]$UseDynamicStringLength
    )

    begin {
        # Null variable to make sure upper-scope variables don't interfere later
        $steppablePipeline = $null

        if (-not $PSBoundParameters.Database) {
            if ($SqlInstance.ConnectionContext.DatabaseName) {
                $Database = $SqlInstance.ConnectionContext.DatabaseName
                $PSBoundParameters.Database = $SqlInstance.ConnectionContext.DatabaseName
                $databaseName = $SqlInstance.ConnectionContext.DatabaseName
            } else {
                $dbname = (Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Query "SELECT DB_NAME() AS dbname").dbname
                $Database = $dbname
                $PSBoundParameters.Database = $dbname
                $databaseName = $dbname
            }
        }

        #region Utility Functions
        function Invoke-BulkCopy {
            <#
            .SYNOPSIS
                Copies a datatable in bulk over to a table.

            .DESCRIPTION
                Copies a datatable in bulk over to a table.

            .PARAMETER DataTable
                The datatable to copy.

            .PARAMETER SqlInstance
                Needs not be specified. The SqlInstance targeted. For message purposes only.

            .PARAMETER Fqtn
                Needs not be specified. The fqtn written to. For message purposes only.

            .PARAMETER BulkCopy
                Needs not be specified. The bulk copy object used to perform the copy operation.
        #>
            [CmdletBinding()]
            param (
                $DataTable,
                [DbaInstance]$SqlInstance = $SqlInstance,
                [string]$Fqtn = $fqtn,
                $BulkCopy = $bulkCopy
            )
            Write-Message -Level Verbose -Message "Importing in bulk to $fqtn"

            $rowCount = $DataTable.Rows.Count
            if ($rowCount -eq 0) {
                $rowCount = 1
            }

            if ($Pscmdlet.ShouldProcess($SqlInstance, "Writing $rowCount rows to $Fqtn")) {
                if ($ColumnMap) {
                    foreach ($columnname in $ColumnMap) {
                        foreach ($key in $columnname.Keys) {
                            $null = $bulkCopy.ColumnMappings.Add($key, $columnname[$key])
                        }
                    }
                } else {
                    foreach ($prop in $DataTable.Columns.ColumnName) {
                        $null = $bulkCopy.ColumnMappings.Add($prop, $prop)
                    }
                }

                $bulkCopy.WriteToServer($DataTable)
                if ($rowCount) {
                    Write-Progress -Id 1 -Activity "Inserting $rowCount rows" -Status "Complete" -Completed
                }
            }
        }

        function New-Table {
            <#
            .SYNOPSIS
                Creates a table, based upon a DataTable.

            .DESCRIPTION
                Creates a table, based upon a DataTable.

            .PARAMETER DataTable
                The DataTable to base the table structure upon.

            .PARAMETER PStoSQLTypes
                Automatically inherits from parent.

            .PARAMETER SqlInstance
                Automatically inherits from parent.

            .PARAMETER Fqtn
                Automatically inherits from parent.

            .PARAMETER Server
                Automatically inherits from parent.

            .PARAMETER DatabaseName
                Automatically inherits from parent.

            .PARAMETER EnableException
                By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
                This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
                Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

            .PARAMETER UseDynamicStringLength
                Automatically inherits from parent.
        #>
            [CmdletBinding(SupportsShouldProcess)]
            param (
                $DataTable,
                $PStoSQLTypes = $PStoSQLTypes,
                $SqlInstance = $SqlInstance,
                $Fqtn = $fqtn,
                $Server = $server,
                $DatabaseName = $databaseName,
                [switch]$EnableException
            )

            Write-Message -Level Verbose -Message "Creating table for $fqtn"

            # Get SQL datatypes by best guess on first data row
            $sqlDataTypes = @();
            $columns = $DataTable.Columns

            if ($null -eq $columns) {
                $columns = $DataTable.Table.Columns
            }

            foreach ($column in $columns) {
                $sqlColumnName = $column.ColumnName

                try {
                    $columnValue = $DataTable.Rows[0].$sqlColumnName
                } catch {
                    $columnValue = $DataTable.$sqlColumnName
                }

                if ($null -eq $columnValue) {
                    $columnValue = $DataTable.$sqlColumnName
                }

                <#
                PS to SQL type conversion
                If data type exists in hash table, use the corresponding SQL type
                Else, fallback to nvarchar.
                If UseDynamicStringLength is specified, the DataColumn MaxLength is used if specified
            #>
                if ($PStoSQLTypes.Keys -contains $column.DataType) {
                    $sqlDataType = $PStoSQLTypes[$($column.DataType.toString())]
                    if ($UseDynamicStringLength -and $column.MaxLength -gt 0 -and ($column.DataType -in ("String", "System.String"))) {
                        $sqlDataType = $sqlDataType.Replace("(MAX)", "($($column.MaxLength))")
                    }
                } else {
                    $sqlDataType = "nvarchar(MAX)"
                }

                $sqlDataTypes += "[$sqlColumnName] $sqlDataType"
            }

            $sql = "BEGIN CREATE TABLE $fqtn ($($sqlDataTypes -join ' NULL,')) END"

            Write-Message -Level Debug -Message $sql

            if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating table $Fqtn")) {
                try {
                    $null = $Server.Databases[$DatabaseName].Query($sql)
                } catch {
                    Stop-Function -Message "The following query failed: $sql" -ErrorRecord $_
                    return
                }
            }
        }

        #endregion Utility Functions

        #region Prepare type for bulk copy
        if (-not $Truncate) { $ConfirmPreference = "None" }

        #endregion Prepare type for bulk copy

        #region Resolve Full Qualified Table Name
        $fqtnObj = Get-ObjectNameParts -ObjectName $Table

        if (-not $fqtnObj.Parsed) {
            Stop-Function -Message "Unable to parse $($fqtnObj.InputValue) as a valid tablename."
            return
        }

        if ($null -eq $fqtnObj.Database -and $null -eq $Database) {
            Stop-Function -Message "You must specify a database or fully qualified table name."
            return
        }

        if (Test-Bound -ParameterName Database) {
            if ($null -eq $fqtnObj.Database) {
                $databaseName = "$Database"
            } else {
                if ($fqtnObj.Database -eq $Database) {
                    $databaseName = "$Database"
                } else {
                    Stop-Function -Message "The database parameter $($Database) differs from value from the fully qualified table name $($fqtnObj.Database)."
                    return
                }
            }
        } else {
            $databaseName = $fqtnObj.Database
        }

        if ($fqtnObj.Schema) {
            $schemaName = $fqtnObj.Schema
        } else {
            $schemaName = $Schema
        }

        $tableName = $fqtnObj.Name

        if ($tableName.StartsWith('#')) {
            Write-Message -Level Verbose -Message "The table $tableName should be in tempdb.dbo so we ignore input database and schema."
            $databaseName = 'tempdb'
            $schemaName = 'dbo'
        }

        $quotedFQTN = New-Object System.Text.StringBuilder

        #region Connect to server
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $databaseName -NonPooledConnection
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }
        #endregion Connect to server

        if ($server.ServerType -ne 'SqlAzureDatabase') {
            <#
                Skip adding database name to Fully Qualified Tablename for Azure SQL DB
                Azure SQL DB does not support Three Part names
            #>
            [void]$quotedFQTN.Append( '[' )
            if ($databaseName.Contains(']')) {
                [void]$quotedFQTN.Append( $databaseName.Replace(']', ']]') )
            } else {
                [void]$quotedFQTN.Append( $databaseName )
            }
            [void]$quotedFQTN.Append( '].' )
        }

        [void]$quotedFQTN.Append( '[' )
        if ($schemaName.Contains(']')) {
            [void]$quotedFQTN.Append( $schemaName.Replace(']', ']]') )
        } else {
            [void]$quotedFQTN.Append( $schemaName )
        }
        [void]$quotedFQTN.Append( '].' )

        [void]$quotedFQTN.Append( '[' )
        if ($tableName.Contains(']')) {
            [void]$quotedFQTN.Append( $tableName.Replace(']', ']]') )
        } else {
            [void]$quotedFQTN.Append( $tableName )
        }
        [void]$quotedFQTN.Append( ']' )

        $fqtn = $quotedFQTN.ToString()
        Write-Message -Level SomewhatVerbose -Message "FQTN processed: $fqtn"
        #endregion Resolve Full Qualified Table Name


        #region Get database
        # we used to do a try catch on $server.Databases if $server.ServerType -eq 'SqlAzureDatabase' here
        # but it seems this was fixed in the newest SMO
        try {
            # This works for both onprem and azure -- using a hash only works for onprem
            $databaseObject = $server.Databases | Where-Object Name -eq $databaseName
            #endregion Get database

            #region Prepare database and bulk operations
            if ($null -eq $databaseObject) {
                Stop-Function -Message "Database $databaseName does not exist." -Target $SqlInstance
                return
            }

            $databaseObject.Tables.Refresh()
            if ($schemaName -notin $databaseObject.Schemas.Name) {
                Stop-Function -Message "Schema $schemaName does not exist."
                return
            }

            if ($tableName.StartsWith('#')) {
                try {
                    Write-Message -Level Verbose -Message "The table $tableName should be in tempdb and we try to find it."
                    $null = $databaseObject.Query("SELECT TOP(1) 1 FROM [$tableName]")
                    $tableExists = $true
                } catch {
                    $tableExists = $false
                }
            } else {
                $targetTable = $databaseObject.Tables | Where-Object { $_.Name -eq $tableName -and $_.Schema -eq $schemaName }
                $tableExists = $targetTable.Count -eq 1
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
        }

        if ((-not $tableExists) -and (-not $AutoCreateTable)) {
            Stop-Function -Message "Table does not exist and automatic creation of the table has not been selected. Specify the '-AutoCreateTable'-parameter to generate a suitable table."
            return
        }

        $bulkCopyOptions = 0
        $options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls", "Default"

        foreach ($option in $options) {
            $optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
            if ($option -eq "TableLock" -and (!$NoTableLock)) {
                $optionValue = $true
            }
            if ($optionValue -eq $true) {
                $bulkCopyOptions += $([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::$option).value__
            }
        }

        if ($Truncate -eq $true) {
            if ($Pscmdlet.ShouldProcess($SqlInstance, "Truncating $fqtn")) {
                try {
                    Write-Message -Level Verbose -Message "Truncating $fqtn."
                    $null = $server.Databases[$databaseName].Query("TRUNCATE TABLE $fqtn")
                } catch {
                    Write-Message -Level Warning -Message "Could not truncate $fqtn. Table may not exist or may have key constraints." -ErrorRecord $_
                }
            }
        }

        Write-Message -Level Verbose -Message "Creating SqlBulkCopy object"
        $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($server.ConnectionContext.SqlConnectionObject, $bulkCopyOptions, $null)

        $bulkCopy.DestinationTableName = $fqtn
        $bulkCopy.BatchSize = $BatchSize
        $bulkCopy.NotifyAfter = $NotifyAfter
        $bulkCopy.BulkCopyTimeOut = $BulkCopyTimeOut

        # The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
        # integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
        # See https://github.com/dataplat/dbatools/issues/6927 for more details
        $script:prevRowsCopied = [int64]0
        $script:totalRowsCopied = [int64]0

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        # Add RowCount output
        $bulkCopy.Add_SqlRowsCopied( {
                $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $args[1].RowsCopied -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                $tstamp = $(Get-Date -format 'yyyyMMddHHmmss')
                Write-Message -Level Verbose -Message "[$tstamp] The bulk copy library reported RowsCopied = $($args[1].RowsCopied). The previous RowsCopied = $($script:prevRowsCopied). The adjusted total rows copied = $($script:totalRowsCopied)"

                $percent = [int](($script:totalRowsCopied / $rowCount) * 100)
                $timeTaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 1)
                Write-Progress -Id 1 -Activity "Inserting $rowCount rows." -PercentComplete $percent -Status ([System.String]::Format("Progress: {0} rows ({1}%) in {2} seconds", $script:totalRowsCopied, $percent, $timeTaken))

                # save the previous count of rows copied to be used on the next event notification
                $script:prevRowsCopied = $args[1].RowsCopied
            })

        $PStoSQLTypes = @{
            #PS datatype      = SQL data type
            'System.Int32'          = 'int';
            'System.UInt32'         = 'bigint';
            'System.Int16'          = 'smallint';
            'System.UInt16'         = 'int';
            'System.Int64'          = 'bigint';
            'System.UInt64'         = 'decimal(20,0)';
            'System.Decimal'        = 'decimal(38,5)';
            'System.Single'         = 'bigint';
            'System.Double'         = 'float';
            'System.Byte'           = 'tinyint';
            'System.Byte[]'         = 'varbinary(MAX)';
            'System.SByte'          = 'smallint';
            'System.TimeSpan'       = 'nvarchar(30)';
            'System.String'         = 'nvarchar(MAX)';
            'System.Char'           = 'nvarchar(1)'
            'System.DateTime'       = 'datetime2';
            'System.DateTimeOffset' = 'datetimeoffset';
            'System.Boolean'        = 'bit';
            'System.Guid'           = 'uniqueidentifier';
            'Int32'                 = 'int';
            'UInt32'                = 'bigint';
            'Int16'                 = 'smallint';
            'UInt16'                = 'int';
            'Int64'                 = 'bigint';
            'UInt64'                = 'decimal(20,0)';
            'Decimal'               = 'decimal(38,5)';
            'Single'                = 'bigint';
            'Double'                = 'float';
            'Byte'                  = 'tinyint';
            'Byte[]'                = 'varbinary(MAX)';
            'SByte'                 = 'smallint';
            'TimeSpan'              = 'nvarchar(30)';
            'String'                = 'nvarchar(MAX)';
            'Char'                  = 'nvarchar(1)'
            'DateTime'              = 'datetime2';
            'DateTimeOffset'        = 'datetimeoffset';
            'Boolean'               = 'bit';
            'Bool'                  = 'bit';
            'Guid'                  = 'uniqueidentifier';
            'int'                   = 'int';
            'long'                  = 'bigint';
        }

        $validTypes = @([System.Data.DataSet], [System.Data.DataTable], [System.Data.DataRow], [System.Data.DataRow[]])
        #endregion Prepare database and bulk operations

        #region ConvertTo-DbaDataTable wrapper
        try {
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('ConvertTo-DbaDataTable', [System.Management.Automation.CommandTypes]::Function)
            $splatCDDT = @{
                TimeSpanType = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.timespantype' -Fallback 'TotalMilliseconds')
                SizeType     = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.sizetype' -Fallback 'Int64')
                IgnoreNull   = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.ignorenull' -Fallback $false)
                Raw          = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.raw' -Fallback $false)
            }
            $scriptCmd = { & $wrappedCmd @splatCDDT }
            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($true)
        } catch {
            Stop-Function -Message "Failed to initialize "
        }
        #endregion ConvertTo-DbaDataTable wrapper
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($null -ne $InputObject) { $inputType = $InputObject.GetType() }
        else { $inputType = $null }

        if ($inputType -eq [System.Data.DataSet]) {
            $inputData = $InputObject.Tables
            $inputType = [System.Data.DataTable[]]
        } else {
            $inputData = $InputObject
        }

        #region Scenario 1: Single valid table
        if ($inputType -in $validTypes) {
            if (-not $tableExists) {
                try {
                    New-Table -DataTable $InputObject -EnableException
                    $tableExists = $true
                } catch {
                    Stop-Function -Message "Failed to create table $fqtn" -ErrorRecord $_ -Target $SqlInstance
                    return
                }
            }

            try { Invoke-BulkCopy -DataTable $InputObject }
            catch {
                Stop-Function -Message "Failed to bulk import to $fqtn" -ErrorRecord $_ -Target $SqlInstance
            }
            return
        }
        #endregion Scenario 1: Single valid table

        foreach ($object in $inputData) {
            #region Scenario 2: Multiple valid tables
            if ($object.GetType() -in $validTypes) {
                if (-not $tableExists) {
                    try {
                        New-Table -DataTable $object -EnableException
                        $tableExists = $true
                    } catch {
                        Stop-Function -Message "Failed to create table $fqtn" -ErrorRecord $_ -Target $SqlInstance
                        return
                    }
                }

                try { Invoke-BulkCopy -DataTable $object }
                catch {
                    Stop-Function -Message "Failed to bulk import to $fqtn" -ErrorRecord $_ -Target $SqlInstance -Continue
                }
                continue
            }
            #endregion Scenario 2: Multiple valid tables

            #region Scenario 3: Invalid data types
            else {
                $null = $steppablePipeline.Process($object)
                continue
            }
            #endregion Scenario 3: Invalid data types
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        #region ConvertTo-DbaDataTable wrapper
        $dataTable = $steppablePipeline.End()
        if ($dataTable[0].Rows.Count -gt 0) {

            if (-not $tableExists) {
                try {
                    New-Table -DataTable $dataTable[0] -EnableException
                    $tableExists = $true
                } catch {
                    Stop-Function -Message "Failed to create table $fqtn" -ErrorRecord $_ -Target $SqlInstance
                    return
                }
            }

            try { Invoke-BulkCopy -DataTable $dataTable[0] }
            catch {
                Stop-Function -Message "Failed to bulk import to $fqtn" -ErrorRecord $_ -Target $SqlInstance
            }
        }
        #endregion ConvertTo-DbaDataTable wrapper

        if ($bulkCopy) {
            $bulkCopy.Close()
            $bulkCopy.Dispose()
        }

        # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
        $null = $server | Disconnect-DbaInstance
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUbn7p3sl7o0iiQZPfZ9nlFXoz
# dtKgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFBZmNsgns+YmuPmNHLD3rKLbdhF+MA0G
# CSqGSIb3DQEBAQUABIIBAGci70bZglNHl6FDqc//42ReixgviQdCe7xPmWEQ6z+q
# 1J9/3Bn6JqN9dmqYFZ6ivSjZIGJ9e2Uq31ZGRBFXFdOI4L9YlwN3fL0oueesMLzn
# i9C3PDhEt8yePYp3RmMoJ9arDcakzL771yFng6whx/CamMHgH8ISrV/aJ6Z9ZAfz
# Gu+YCK8aer2Wc8qAmyDtnZvXbhWopxou4omu6AKuPzp2XkVl9+wtWqVjq6qmwu9Z
# /lIhIBZZumwRgCQgmQwMM1KP1Uj+uL8qv2OhRw/TeR318kjFswue5RE7NW7Xjh0s
# ftONHJMagu6ku63a9YMjcSVwmltuypqflyYGZUY1QzyhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDMzWjAvBgkqhkiG9w0BCQQxIgQgu9oNN4T0/pvGZYOTINWj
# +fZGVsysX6oRkVVaQRRK8P8wDQYJKoZIhvcNAQEBBQAEggIAho5P0iKqGN7UbnLp
# W5dNHywLiGX3V8HrgqiSafZ+CA1xsufLxt1ittXlS0hUnYs94pqz+Ca2kd75bEhb
# 2AIEqRhna5E/+O0UCidwmyfMAxSbo+gZG3+oHIoEZaLjoyQF6fK3NQj1f4IRVj6V
# aGcByjCkiaP5XvxJwc6QgcjcjwY3Lx4egZUpYT5E1ZF9Y0WZ41kLdvMV5eYPnPGZ
# Cj3jJmytdW7vNvAXWtco6FDCe2ExelVx4QcXwjAJ8J/WNloXnXhYdtVdR58g00M4
# A5tfUsXwMugh6+YZIfo3yvQXJ5qdNTLKIZpUJifPtBnMSHqmpItL2EC6/a07+jF1
# Gg6afCne2LzUraU46/36CJ56OEVdxCxUshhlBJO6v1evcpqkKiiCRjni7xMeaJlI
# tYBAGKkUC3hiME85rZCcq2M3S5+CWBBHsLruJBLfV+nEN/uty4OJxMwdovwZO7Mn
# KAcrA9vziHqLEZQrZt3djd8xwGV2wWDP7NfbMEHoztDib7AUPGho78z7TNPv4Lm5
# NmipBYhZQgzP/mwheB0HLwj2MmDGGqQo0p9umbEGBhsxOLlxbBwiFDN+vOFDoi3v
# +1gwseOCG0M0N0Z6imC7f4c6uKvLWQR/eOWl8lQzKxupEzd3f+vkhmltaOS74OfE
# 3hN0ZgHq3xl1q6q/CupbvQmiDKM=
# SIG # End signature block
