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
        try {
            $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($server.ConnectionContext.SqlConnectionObject, $bulkCopyOptions, $null)
        } catch {
            $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($server.ConnectionContext.ConnectionString, $bulkCopyOptions)
        }

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
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAaGWbu1A19t12b
# /ykjNhrTGMqRwUz94cj40Tn4bk1yzqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDbHXLABcyYtUFMVLSNSxVwiT81Mitw7jF/
# Inqtz7ZqhDANBgkqhkiG9w0BAQEFAASCAQCQgWrIT+0ZWajP7XhVSgu5IvufJnnm
# zgmUGHeecWP4V6/dW0UJvmGVtnXNLoBpf/6cO2GGLzu+zcH4KBsw5E6+fRJx3y6O
# 7oCGkJNqD94qKfHpqE0uYFP/Bs3aMWKbSlYnCCQk0IytjeRmaVbwP9IibPVuAZiq
# /u5BiuBgU2G2q7P3FD9XwcS9cvY9v9C0/o6R2t8nVbzVKbEAilC4B9g1vGLCU422
# mz/TMzTNWbGSDp9j1smC335BWwrrmGuo92jT8Og52NvzA1KhEUBI+WtsyGcSHXMK
# JGfp92FM3AguZFObZNTAyAZGTxXERveI9MixxxPaO8FTovENtbcUgfVeoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQxMlowLwYJKoZIhvcNAQkEMSIEIJYk1dJb
# rZOs3yk5ipAsNnqmU2nzLE7ZltS3DsB8N9e+MA0GCSqGSIb3DQEBAQUABIICADYu
# bXFmFqUoSGE1q9p0KlNE13cZEQpeZZLFoekt8eztgY5e0vw4TehasUVnYmBcZCk4
# DKkkqO3L4YVAqlhf7F5Znag88ND3lgu5DaXA6U7RFzxSUh8mRuz7udJvqJ2jr/c9
# WkInBdZUjk2TwJHpWZU9F4PliW5b4YsiSbaSU1fMZWngE6IP463J0P95cm+e/OL/
# NK9yOnoZggxDth3x42DVHuqj3ybryEohSw21k/9u9fbzSuTFEMZi8pYBM/e5Q77a
# Y8wbD+JkyUfzPlhxIfzOlGXKX4BzQgbMsKc+Wmc2lhPQA2rwuc/vCsWD0+otOjDH
# sJzEPSyFSQGt3Y3oxttrixweVfm8Z03RXoWDBaSr0BVZi3luuX7YJnJA647LFV2Q
# qzMHTmGDdMz4jwfBgn2qvlRknVjgIVflCFi3OHQgMVh0mlDuzqIPrT8M1XEwfLsS
# O08Ba5axiiY4eLWkBJ9wje1EZmS9VwjV+nmRn8ny2ufHci1QBNmiSWSVrg+6lMUR
# hmst9JYgyPIMMg8No/9giNx9/7i7P/hDsDOFGkkbaUihVNM4gROBXHTYp9nslhkM
# G+KksXLchFgZJjDd4TTtDGJRXbqPZv8RrJ2ZF3/pANXEyPnVz/i6kr25i4zvh9wi
# XsaGw6vvNQowK98oQoHI0JNExr5ArSyuH1XePK/G
# SIG # End signature block
