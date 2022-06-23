function Invoke-DbaDbDataMasking {
    <#
    .SYNOPSIS
        Masks data by using randomized values determined by a configuration file and a randomizer framework

    .DESCRIPTION
        TMasks data by using randomized values determined by a configuration file and a randomizer framework

        It will use a configuration file that can be made manually or generated using New-DbaDbMaskingConfig

        Note that the following column and data types are not currently supported:
        Identity
        ForeignKey
        Computed
        Hierarchyid
        Geography
        Geometry
        Xml

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Databases to process through

    .PARAMETER Table
        Tables to process. By default all the tables will be processed

    .PARAMETER Column
        Columns to process. By default all the columns will be processed

    .PARAMETER FilePath
        Configuration file that contains the which tables and columns need to be masked

    .PARAMETER Locale
        Set the local to enable certain settings in the masking

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER ExcludeTable
        Exclude specific tables even if it's listed in the config file.

    .PARAMETER ExcludeColumn
        Exclude specific columns even if it's listed in the config file.

    .PARAMETER MaxValue
        Force a max length of strings instead of relying on datatype maxes. Note if a string datatype has a lower MaxValue, that will be used instead.

        Useful for adhoc updates and testing, otherwise, the config file should be used.

    .PARAMETER ModulusFactor
        Calculating the next nullable by using the remainder from the modulus. Default is every 10.

    .PARAMETER ExactLength
        Mask string values to the same length. So 'Tate' will be replaced with 4 random characters.

    .PARAMETER CommandTimeout
        Timeout for the database connection in seconds. Default is 300.

    .PARAMETER BatchSize
        Size of the batch to use to write the masked data back to the database

    .PARAMETER Retry
        The amount of retries to generate a unique row for a table. Default is 1000.

    .PARAMETER DictionaryFilePath
        Import the dictionary to be used in in the database masking

    .PARAMETER DictionaryExportPath
        Export the dictionary to the given path. Naming convention will be [computername]_[instancename]_[database]_Dictionary.csv

        Be careful with this feature, this export is the key to get the original values which is a security risk!

    .PARAMETER Force
        Forcefully execute commands when needed

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Masking, DataMasking
        Author: Sander Stad (@sqlstad, sqlstad.nl) | Chrissy LeMaire (@cl, netnerds.net)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDataMasking

    .EXAMPLE
        Invoke-DbaDbDataMasking -SqlInstance SQLDB2 -Database DB1 -FilePath C:\Temp\sqldb1.db1.tables.json

        Apply the data masking configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2. Prompt for confirmation for each table.

    .EXAMPLE
        Get-ChildItem -Path C:\Temp\sqldb1.db1.tables.json | Invoke-DbaDbDataMasking -SqlInstance SQLDB2 -Database DB1 -Confirm:$false

        Apply the data masking configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2. Do not prompt for confirmation.

    .EXAMPLE
        New-DbaDbMaskingConfig -SqlInstance SQLDB1 -Database DB1 -Path C:\Temp\clone -OutVariable file
        $file | Invoke-DbaDbDataMasking -SqlInstance SQLDB2 -Database DB1 -Confirm:$false

        Create the data masking configuration file "sqldb1.db1.tables.json", then use it to mask the db1 database on sqldb2. Do not prompt for confirmation.

    .EXAMPLE
        Get-ChildItem -Path C:\Temp\sqldb1.db1.tables.json | Invoke-DbaDbDataMasking -SqlInstance SQLDB2, sqldb3 -Database DB1 -Confirm:$false

        See what would happen if you the data masking configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2 and sqldb3. Do not prompt for confirmation.
    #>
    [CmdLetBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('Path', 'FullName')]
        [object]$FilePath,
        [string]$Locale = 'en',
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string[]]$Table,
        [string[]]$Column,
        [string[]]$ExcludeTable,
        [string[]]$ExcludeColumn,
        [int]$MaxValue,
        [int]$ModulusFactor,
        [switch]$ExactLength,
        [int]$CommandTimeout,
        [int]$BatchSize,
        [int]$Retry,
        [string[]]$DictionaryFilePath,
        [string]$DictionaryExportPath,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $supportedDataTypes = @(
            'bit', 'bigint', 'bool',
            'char', 'date',
            'datetime', 'datetime2', 'decimal',
            'float',
            'int',
            'money',
            'nchar', 'ntext', 'nvarchar',
            'smalldatetime', 'smallint',
            'text', 'time', 'tinyint',
            'uniqueidentifier', 'userdefineddatatype',
            'varchar'
        )

        $supportedFakerMaskingTypes = Get-DbaRandomizedType | Select-Object Type -ExpandProperty Type -Unique

        $supportedFakerSubTypes = Get-DbaRandomizedType | Select-Object Subtype -ExpandProperty Subtype -Unique

        $supportedFakerSubTypes += "Date"

        # Set defaults
        if (-not $ModulusFactor) {
            $ModulusFactor = 10
            Write-Message -Level Verbose -Message "Modulus factor set to $ModulusFactor"
        }

        if (-not $CommandTimeout) {
            $CommandTimeout = 300
            Write-Message -Level Verbose -Message "Command time-out set to $CommandTimeout"
        }

        if (-not $BatchSize) {
            $BatchSize = 1000
            Write-Message -Level Verbose -Message "Batch size set to $BatchSize"
        }

        if (-not $Retry) {
            $Retry = 1000
            Write-Message -Level Verbose -Message "Retry count set to $Retry"
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($FilePath.ToString().StartsWith('http')) {
            $tables = Invoke-RestMethod -Uri $FilePath
        } else {
            # Test the configuration file
            try {
                $configErrors = @()

                $configErrors += Test-DbaDbDataMaskingConfig -FilePath $FilePath -EnableException

                if ($configErrors.Count -ge 1) {
                    Stop-Function -Message "Errors found testing the configuration file." -Target $FilePath
                    return $configErrors
                }
            } catch {
                Stop-Function -Message "Something went wrong testing the configuration file" -ErrorRecord $_ -Target $FilePath
                return
            }

            # Get all the items that should be processed
            try {
                $tables = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath
                return
            }
        }

        # Test the columns for data types
        foreach ($tabletest in $tables.Tables) {
            if ($Table -and $tabletest.Name -notin $Table) {
                continue
            }

            foreach ($columntest in $tabletest.Columns) {
                if ($columntest.ColumnType -in 'hierarchyid', 'geography', 'xml', 'geometry' -and $columntest.Name -notin $Column) {
                    Stop-Function -Message "$($columntest.ColumnType) is not supported, please remove the column $($columntest.Name) from the $($tabletest.Name) table" -Target $tables -Continue
                }
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check if the deterministic values table is already present
            if ($server.Databases['tempdb'].Tables.Name -contains 'DeterministicValues') {
                Write-Message -Level Verbose -Message "Deterministic values table already exists. Dropping it...."
                $query = "DROP TABLE [dbo].[DeterministicValues];"
                $server.Databases['tempdb'].Query($query)
            }

            # Create the deterministic value table
            $query = "
                CREATE TABLE dbo.DeterministicValues
                (
                    [ValueKey] VARCHAR(900),
                    [NewValue] VARCHAR(900)
                )

                CREATE UNIQUE NONCLUSTERED INDEX UNX__DeterministicValues_ValueKey
                ON dbo.DeterministicValues ( ValueKey )
            "

            $null = $server.Databases['tempdb'].Query($query)

            # Import the dictionary files
            if ($DictionaryFilePath.Count -ge 1) {
                foreach ($file in $DictionaryFilePath) {
                    Write-Message -Level Verbose -Message "Importing dictionary file '$file'"
                    if (Test-Path -Path $file) {
                        try {
                            # Import the keys and values
                            Import-DbaCsv -Path $file -SqlInstance $server -Database tempdb -Schema dbo -Table DeterministicValues
                        } catch {
                            Stop-Function -Message "Could not import csv data from file '$file'" -ErrorRecord $_ -Target $file
                        }
                    } else {
                        Stop-Function -Message "Could not import dictionary file '$file'" -ErrorRecord $_ -Target $file
                    }
                }
            }

            # Get the database name
            if (-not $Database) {
                $Database = $tables.Name
            }

            # Loop through the databases
            foreach ($dbName in $Database) {
                if ($server.VersionMajor -lt 9) {
                    Stop-Function -Message "SQL Server version must be 2005 or greater" -Continue
                }

                $db = $server.Databases[$($dbName)]

                #$stepcounter = $nullmod = 0
                $nullmod = 0

                #region for each table
                foreach ($tableobject in $tables.Tables) {
                    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

                    $uniqueDataTableName = $null
                    $uniqueValueColumns = @()
                    $stringBuilder = [System.Text.StringBuilder]''

                    if ($tableobject.Name -in $ExcludeTable) {
                        Write-Message -Level Verbose -Message "Skipping $($tableobject.Name) because it is explicitly excluded"
                        continue
                    }

                    if ($tableobject.Name -notin $db.Tables.Name) {
                        Stop-Function -Message "Table $($tableobject.Name) is not present in $db" -Target $db -Continue
                    }

                    $dbTable = $db.Tables | Where-Object { $_.Schema -eq $tableobject.Schema -and $_.Name -eq $tableobject.Name }

                    [bool]$cleanupIdentityColumn = $false

                    # Make sure there is an identity column present to speed things up
                    if (-not ($dbTable.Columns | Where-Object { $_.Identity -eq $true })) {
                        Write-Message -Level Verbose -Message "Adding identity column to table [$($dbTable.Schema)].[$($dbTable.Name)]"
                        $query = "ALTER TABLE [$($dbTable.Schema)].[$($dbTable.Name)] ADD MaskingID BIGINT IDENTITY(1, 1) NOT NULL;"

                        try {
                            Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database $db.Name -Query $query
                        } catch {
                            Stop-Function -Message "Could not alter the table to add the masking id" -Target $db -Continue
                        }

                        $cleanupIdentityColumn = $true

                        $identityColumn = "MaskingID"

                        $dbTable.Columns.Refresh()
                    } else {
                        $identityColumn = $dbTable.Columns | Where-Object { $_.Identity } | Select-Object -ExpandProperty Name
                    }

                    # Check if the index for the identity column is already present
                    $maskingIndexName = "NIX__$($dbTable.Schema)_$($dbTable.Name)_Masking"
                    try {
                        if ($dbTable.Indexes.Name -contains $maskingIndexName) {
                            Write-Message -Level Verbose -Message "Masking index already exists in table [$($dbTable.Schema)].[$($dbTable.Name)]. Dropping it..."
                            $dbTable.Indexes[$($maskingIndexName)].Drop()
                        }
                    } catch {
                        Stop-Function -Message "Could not remove identity index to table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue
                    }

                    # Create the index for the identity column
                    try {
                        Write-Message -Level Verbose -Message "Adding index on identity column [$($identityColumn)] in table [$($dbTable.Schema)].[$($dbTable.Name)]"

                        $query = "CREATE NONCLUSTERED INDEX [$($maskingIndexName)] ON [$($dbTable.Schema)].[$($dbTable.Name)]([$($identityColumn)])"

                        $queryParams = @{
                            SqlInstance   = $server
                            SqlCredential = $SqlCredential
                            Database      = $db.Name
                            Query         = $query
                            QueryTimeout  = $CommandTimeout
                        }

                        Invoke-DbaQuery @queryParams
                    } catch {
                        Stop-Function -Message "Could not add identity index to table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue
                    }

                    try {
                        if (-not $tableobject.FilterQuery) {
                            # Get all the columns from the table
                            $columnString = "[" + (($dbTable.Columns | Where-Object { $_.DataType -in $supportedDataTypes } | Select-Object Name -ExpandProperty Name) -join "],[") + "]"

                            # Add the identifier column
                            $columnString += ",[$($identityColumn)]"

                            # Put it all together
                            $query = "SELECT $($columnString) FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                        } else {
                            # Get the query from the table objects
                            $query = ($tableobject.FilterQuery).ToLower()

                            # Check if the query already contains the identifier column
                            if (-not ($query | Select-String -Pattern $identityColumn)) {
                                # Split up the query from the first "from"
                                $queryParts = $query -split "from", 2

                                # Put it all together again with the identifier
                                $query = "$($queryParts[0].Trim()), $($identityColumn) FROM $($queryParts[1].Trim())"
                            }
                        }

                        # Get the data
                        [array]$data = $db.Query($query)
                    } catch {
                        Stop-Function -Message "Failure retrieving the data from table [$($tableobject.Schema)].[$($tableobject.Name)]" -Target $Database -ErrorRecord $_ -Continue
                    }

                    #region unique indexes
                    # Check if the table contains unique indexes
                    if ($tableobject.HasUniqueIndex) {

                        # Loop through the rows and generate a unique value for each row
                        Write-Message -Level Verbose -Message "Generating unique values for [$($tableobject.Schema)].[$($tableobject.Name)]"

                        $params = @{
                            SqlInstance   = $server
                            SqlCredential = $SqlCredential
                            Database      = $db.name
                            Schema        = $tableobject.Schema
                            Table         = $tableobject.Name
                        }

                        $indexToTable = Convert-DbaIndexToTable @params

                        if ($indexToTable) {
                            # compare the index columns to the column in the json table object
                            $compareParams = @{
                                ReferenceObject  = $indexToTable.Columns
                                DifferenceObject = $tableobject.Columns.Name
                                IncludeEqual     = $true
                            }
                            $maskingColumnIndexCount = (Compare-Object @compareParams | Where-Object { $_.SideIndicator -eq "==" }).Count

                            # Check if there is any need to generate unique values
                            if ($maskingColumnIndexCount -ge 1) {

                                # Check if the temporary table already exists
                                $server.Databases['tempdb'].Tables.Refresh()
                                $uniqueDataTableName = $indexToTable.TempTableName

                                if ($server.Databases['tempdb'].Tables.Name -contains $indexToTable.TempTableName) {
                                    Write-Message -Level Verbose -Message "Table '$($indexToTable.TempTableName)' already exists. Dropping it.."
                                    try {
                                        $query = "DROP TABLE $($indexToTable.TempTableName)"
                                        Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $query
                                    } catch {
                                        Stop-Function -Message "Could not drop temporary table"
                                    }
                                }

                                # Create the temporary table
                                try {
                                    Write-Message -Level Verbose -Message "Creating temporary table '$($indexToTable.TempTableName)'"
                                    Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $indexToTable.CreateStatement
                                } catch {
                                    Stop-Function -Message "Could not create temporary table #[$($tableobject.Schema)].[$($tableobject.Name)]"
                                }

                                # Create the unique index table
                                try {
                                    Write-Message -Level Verbose -Message "Creating the unique index for temporary table '$($indexToTable.TempTableName)'"
                                    Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $indexToTable.UniqueIndexStatement
                                } catch {
                                    Stop-Function -Message "Could not create temporary table #[$($tableobject.Schema)].[$($tableobject.Name)]"
                                }

                                # Create a unique row
                                $retryCount = 0
                                for ($i = 0; $i -lt $data.Count; $i++) {
                                    $insertQuery = "INSERT INTO [$($indexToTable.TempTableName)]([$($indexToTable.Columns -join '],[')]) VALUES("
                                    $insertFailed = $false
                                    $insertValues = @()

                                    foreach ($indexColumn in $indexToTable.Columns) {
                                        $columnMaskInfo = $tableobject.Columns | Where-Object { $_.Name -eq $indexColumn }

                                        if ($indexColumn -eq "RowNr") {
                                            $newValue = $i + 1
                                        } elseif ($columnMaskInfo) {
                                            # make sure min is good
                                            if ($columnMaskInfo.MinValue) {
                                                $min = $columnMaskInfo.MinValue
                                            } else {
                                                if ($columnMaskInfo.CharacterString) {
                                                    $min = 1
                                                } else {
                                                    $min = 0
                                                }
                                            }

                                            # make sure max is good
                                            if ($MaxValue) {
                                                if ($columnMaskInfo.MaxValue -le $MaxValue) {
                                                    $max = $columnMaskInfo.MaxValue
                                                } else {
                                                    $max = $MaxValue
                                                }
                                            } else {
                                                $max = $columnMaskInfo.MaxValue
                                            }

                                            if (-not $columnMaskInfo.MaxValue -and -not (Test-Bound -ParameterName MaxValue)) {
                                                $max = 10
                                            }

                                            if ((-not $columnMaskInfo.MinValue -or -not $columnMaskInfo.MaxValue) -and ($columnMaskInfo.ColumnType -match 'date')) {
                                                if (-not $columnMaskInfo.MinValue) {
                                                    $min = (Get-Date).AddDays(-365)
                                                }
                                                if (-not $columnMaskInfo.MaxValue) {
                                                    $max = (Get-Date).AddDays(365)
                                                }
                                            }

                                            if ($columnMaskInfo.CharacterString) {
                                                $charstring = $columnMaskInfo.CharacterString
                                            } else {
                                                $charstring = $CharacterString
                                            }

                                            # Generate a new value
                                            $newValue = $null

                                            $newValueParams = $null

                                            try {
                                                $newValueParams = $null
                                                if (-not $columnobject.SubType -and $columnobject.ColumnType -in $supportedDataTypes) {
                                                    $newValueParams = @{
                                                        DataType = $columnMaskInfo.SubType
                                                        Min      = $columnMaskInfo.MinValue
                                                        Max      = $columnMaskInfo.MaxValue
                                                        Locale   = $Locale
                                                    }
                                                } else {
                                                    $newValueParams = @{
                                                        RandomizerType    = $columnMaskInfo.MaskingType
                                                        RandomizerSubtype = $columnMaskInfo.SubType
                                                        Min               = $min
                                                        Max               = $max
                                                        CharacterString   = $charstring
                                                        Format            = $columnMaskInfo.Format
                                                        Separator         = $columnMaskInfo.Separator
                                                        Locale            = $Locale
                                                    }
                                                }

                                                $newValue = Get-DbaRandomizedValue @newValueParams
                                            } catch {
                                                Stop-Function -Message "Failure" -Target $columnMaskInfo -Continue -ErrorRecord $_
                                            }
                                        } else {
                                            $newValue = $null
                                        }

                                        if ($columnMaskInfo) {
                                            try {
                                                $insertValue = Convert-DbaMaskingValue -Value $newValue -DataType $columnMaskInfo.ColumnType -Nullable:$columnMaskInfo.Nullable -EnableException

                                                if ($convertedValue.ErrorMessage) {
                                                    $maskingErrorFlag = $true
                                                    Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                                }
                                            } catch {
                                                Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $newValue
                                            }

                                            $insertValues += $insertValue.NewValue
                                        } elseif ($indexColumn -eq "RowNr") {
                                            $insertValues += $newValue
                                        } else {
                                            $insertValues += "NULL"
                                        }

                                        $uniqueValueColumns += $columnMaskInfo.Name
                                    }

                                    # Join all the values to the insert query
                                    $insertQuery += "$($insertValues -join ','));"

                                    # Try inserting the value
                                    try {
                                        $null = $server.Databases['tempdb'].Query($insertQuery)
                                        $insertFailed = $false
                                    } catch {
                                        Write-PSFMessage -Level Verbose -Message "Could not insert value"
                                        $insertFailed = $true
                                    }

                                    # Try to insert the value as long it's failed
                                    while ($insertFailed) {
                                        if ($retryCount -eq $Retry) {
                                            Stop-Function -Message "Could not create a unique row after $retryCount tries. Stopping..."
                                            return
                                        }

                                        $insertQuery = "INSERT INTO [$($indexToTable.TempTableName)]([$($indexToTable.Columns -join '],[')]) VALUES("

                                        foreach ($indexColumn in $indexToTable.Columns) {
                                            $columnMaskInfo = $tableobject.Columns | Where-Object { $_.Name -eq $indexColumn }

                                            if ($indexColumn -eq "RowNr") {
                                                $newValue = $i + 1
                                            } elseif ($columnMaskInfo) {
                                                # make sure min is good
                                                if ($columnMaskInfo.MinValue) {
                                                    $min = $columnMaskInfo.MinValue
                                                } else {
                                                    if ($columnMaskInfo.CharacterString) {
                                                        $min = 1
                                                    } else {
                                                        $min = 0
                                                    }
                                                }

                                                # make sure max is good
                                                if ($MaxValue) {
                                                    if ($columnMaskInfo.MaxValue -le $MaxValue) {
                                                        $max = $columnMaskInfo.MaxValue
                                                    } else {
                                                        $max = $MaxValue
                                                    }
                                                } else {
                                                    $max = $columnMaskInfo.MaxValue
                                                }

                                                if (-not $columnMaskInfo.MaxValue -and -not (Test-Bound -ParameterName MaxValue)) {
                                                    $max = 10
                                                }

                                                if ((-not $columnMaskInfo.MinValue -or -not $columnMaskInfo.MaxValue) -and ($columnMaskInfo.ColumnType -match 'date')) {
                                                    if (-not $columnMaskInfo.MinValue) {
                                                        $min = (Get-Date).AddDays(-365)
                                                    }
                                                    if (-not $columnMaskInfo.MaxValue) {
                                                        $max = (Get-Date).AddDays(365)
                                                    }
                                                }

                                                if ($columnMaskInfo.CharacterString) {
                                                    $charstring = $columnMaskInfo.CharacterString
                                                } else {
                                                    $charstring = $CharacterString
                                                }

                                                # Generate a new value
                                                $newValue = $null

                                                $newValueParams = $null

                                                try {
                                                    $newValueParams = $null
                                                    if (-not $columnobject.SubType -and $columnobject.ColumnType -in $supportedDataTypes) {
                                                        $newValueParams = @{
                                                            DataType = $columnMaskInfo.SubType
                                                            Min      = $columnMaskInfo.MinValue
                                                            Max      = $columnMaskInfo.MaxValue
                                                            Locale   = $Locale
                                                        }
                                                    } else {
                                                        $newValueParams = @{
                                                            RandomizerType    = $columnMaskInfo.MaskingType
                                                            RandomizerSubtype = $columnMaskInfo.SubType
                                                            Min               = $min
                                                            Max               = $max
                                                            CharacterString   = $charstring
                                                            Format            = $columnMaskInfo.Format
                                                            Separator         = $columnMaskInfo.Separator
                                                            Locale            = $Locale
                                                        }
                                                    }

                                                    $newValue = Get-DbaRandomizedValue @newValueParams
                                                } catch {
                                                    Stop-Function -Message "Failure" -Target $columnMaskInfo -Continue -ErrorRecord $_
                                                }
                                            } else {
                                                $newValue = $null
                                            }

                                            if ($columnMaskInfo) {
                                                try {
                                                    $insertValue = Convert-DbaMaskingValue -Value $newValue -DataType $columnMaskInfo.ColumnType -Nullable:$columnMaskInfo.Nullable -EnableException

                                                    if ($convertedValue.ErrorMessage) {
                                                        $maskingErrorFlag = $true
                                                        Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                                    }
                                                } catch {
                                                    Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $newValue
                                                }

                                                $insertValues += $insertValue.NewValue
                                            } elseif ($indexColumn -eq "RowNr") {
                                                $insertValues += $newValue
                                            } else {
                                                $insertValues += "NULL"
                                            }
                                        }

                                        # Join all the values to the insert query
                                        $insertQuery += "$($insertValues -join ','));"

                                        # Try inserting the value
                                        try {
                                            $null = $server.Databases['tempdb'].Query($insertQuery)
                                            $insertFailed = $false
                                        } catch {
                                            Write-PSFMessage -Level Verbose -Message "Could not insert value"
                                            $insertFailed = $true
                                            $retryCount++
                                        }
                                    }
                                }

                                try {
                                    Write-Message -Level Verbose -Message "Creating masking index for [$($indexToTable.TempTableName)]"
                                    $query = "CREATE NONCLUSTERED INDEX [NIX_$($indexToTable.TempTableName)_MaskID] ON [$($indexToTable.TempTableName)]([RowNr])"
                                    $null = $server.Databases['tempdb'].Query($query)
                                } catch {
                                    Stop-Function -Message "Could not add masking index for [$($indexToTable.TempTableName)]" -ErrorRecord $_
                                }
                            } else {
                                Write-PSFMessage -Level Verbose -Message "Table [$($tableobject.Schema)].[$($tableobject.Name)] does not contain any masking index columns to process"
                            }
                        } else {
                            Stop-Function -Message "The table does not have any indexes"
                        }
                    }

                    #endregion unique indexes

                    $tablecolumns = $tableobject.Columns

                    if ($Column) {
                        $tablecolumns = $tablecolumns | Where-Object { $_.Name -in $Column }
                    }

                    if ($ExcludeColumn) {
                        if ([string]$uniqueIndex.Columns -match ($ExcludeColumn -join "|")) {
                            Stop-Function -Message "Column present in -ExcludeColumn cannot be excluded because it's part of an unique index" -Target $ExcludeColumn -Continue
                        }

                        $tablecolumns = $tablecolumns | Where-Object { $_.Name -notin $ExcludeColumn }
                    }

                    if (-not $tablecolumns) {
                        Write-Message -Level Verbose "No columns to process in [$($dbName)].[$($tableobject.Schema)].[$($tableobject.Name)], moving on"
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess($instance, "Masking $($data.Count) row(s) for column [$($tablecolumns.Name -join ', ')] in $($dbName).$($tableobject.Schema).$($tableobject.Name)")) {
                        $totalBatches = [System.Math]::Ceiling($data.Count / $BatchSize)

                        # Figure out if the columns has actions
                        $columnsWithActions = @()
                        $columnsWithActions += $tableobject.Columns | Where-Object { $null -ne $_.Action }

                        # Figure out if the columns has composites
                        $columnsWithComposites = @()
                        $columnsWithComposites += $tableobject.Columns | Where-Object { $null -ne $_.Composite }

                        # Check for both special actions
                        if (($columnsWithComposites.Count -ge 1) -and ($columnsWithActions.Count -ge 1)) {
                            Stop-Function -Message "You cannot use both composites and actions"
                        }

                        # Loop through each of the rows and change them
                        foreach ($columnobject in $tablecolumns) {
                            # Set the masking error
                            [bool]$maskingErrorFlag = $false

                            # Only start generating values if the column is not using Actions or Composites
                            if (($columnobject.Name -notin $columnsWithActions.Name) -and ($columnobject.Name -notin $columnsWithComposites.Name)) {

                                # Set the counters
                                $rowNumber = $batchRowNr = $batchNr = 0

                                if ($columnobject.StaticValue) {
                                    $newValue = $columnobject.StaticValue

                                    if ($null -eq $newValue -and -not $columnobject.Nullable) {
                                        Write-PSFMessage -Message "Column '$($columnobject.Name)' static value cannot null when column is set not to be nullable."
                                    } else {
                                        try {
                                            $convertedValue = Convert-DbaMaskingValue -Value $newValue -DataType $columnobject.ColumnType -Nullable:$columnobject.Nullable -EnableException

                                            if ($convertedValue.ErrorMessage) {
                                                $maskingErrorFlag = $true
                                                Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                            } else {
                                                $null = $stringBuilder.AppendLine("UPDATE [$($tableobject.Schema)].[$($tableobject.Name)] SET [$($columnObject.Name)] = $($convertedValue.NewValue)")
                                            }

                                        } catch {
                                            Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $newValue
                                        }

                                        $batchRowNr++
                                    }
                                } else {
                                    Write-Message -Level Verbose -Message "Processing column [$($columnObject.Name)]"
                                    # Column does not have an action
                                    foreach ($row in $data) {
                                        # Start counting the rows
                                        $rowNumber++

                                        if ((($batchRowNr) % 100) -eq 0) {

                                            $progressParams = @{
                                                StepNumber = $batchNr
                                                TotalSteps = $totalBatches
                                                Activity   = "Masking $($data.Count) rows in $($tableobject.Schema).$($tableobject.Name) in $($dbName) on $instance"
                                                Message    = "Generating Updates"
                                            }

                                            Write-ProgressHelper @progressParams
                                        }

                                        $updates = @()
                                        $newValue = $null

                                        # Check for value being in deterministic masking table
                                        if (($null -ne $row.($columnobject.Name)) -and ($row.($columnobject.Name) -ne '')) {
                                            try {
                                                $lookupValue = Convert-DbaMaskingValue -Value $row.($columnobject.Name) -DataType varchar -Nullable:$columnobject.Nullable -EnableException

                                                if ($convertedValue.ErrorMessage) {
                                                    $maskingErrorFlag = $true
                                                    Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                                }
                                            } catch {
                                                Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $row.($columnobject.Name)
                                            }

                                            $query = "SELECT [NewValue] FROM dbo.DeterministicValues WHERE [ValueKey] = $($lookupValue.NewValue)"

                                            try {
                                                $lookupResult = $null
                                                $lookupResult = $server.Databases['tempdb'].Query($query)
                                            } catch {
                                                Stop-Function -Message "Something went wrong retrieving the deterministic values" -Target $query -ErrorRecord $_
                                            }
                                        }

                                        # Check the columnobject properties and possible scenarios
                                        if ($columnobject.MaskingType -eq 'Static') {
                                            $newValue = $columnobject.StaticValue
                                        } elseif ($columnobject.KeepNull -and $columnobject.Nullable -and (($row.($columnobject.Name)).GetType().Name -eq 'DBNull') -or ($row.($columnobject.Name) -eq '')) {
                                            $newValue = $null
                                        } elseif (-not $columnobject.KeepNull -and $columnobject.Nullable -and (($nullmod++) % $ModulusFactor -eq 0)) {
                                            $newValue = $null
                                        } elseif ($tableobject.HasUniqueIndex -and $columnobject.Name -in $uniqueValueColumns) {
                                            $query = "SELECT $($columnobject.Name) FROM $($uniqueDataTableName) WHERE [RowNr] = $rowNumber"

                                            try {
                                                $uniqueData = Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database tempdb -Query $query
                                            } catch {
                                                Stop-Function -Message "Something went wrong getting the unique data" -Target $query -ErrorRecord $_
                                            }

                                            if ($null -eq $uniqueData) {
                                                Stop-Function -Message "Could not find any unique values" -Target $tableobject
                                                return
                                            }

                                            $newValue = $uniqueData.$($columnobject.Name)
                                        } elseif ($columnobject.Deterministic -and $lookupResult.NewValue) {
                                            $newValue = $lookupResult.NewValue
                                        } else {
                                            # make sure min is good
                                            if ($columnobject.MinValue) {
                                                $min = $columnobject.MinValue
                                            } else {
                                                if ($columnobject.CharacterString) {
                                                    $min = 1
                                                } else {
                                                    $min = 0
                                                }
                                            }

                                            # make sure max is good
                                            if ($MaxValue) {
                                                if ($columnobject.MaxValue -le $MaxValue) {
                                                    $max = $columnobject.MaxValue
                                                } else {
                                                    $max = $MaxValue
                                                }
                                            } else {
                                                $max = $columnobject.MaxValue
                                            }

                                            if (-not $columnobject.MaxValue -and -not (Test-Bound -ParameterName MaxValue)) {
                                                $max = 10
                                            }

                                            if ((-not $columnobject.MinValue -or -not $columnobject.MaxValue) -and ($columnobject.ColumnType -match 'date')) {
                                                if (-not $columnobject.MinValue) {
                                                    $min = (Get-Date).AddDays(-365)
                                                }
                                                if (-not $columnobject.MaxValue) {
                                                    $max = (Get-Date).AddDays(365)
                                                }
                                            }

                                            if ($columnobject.CharacterString) {
                                                $charstring = $columnobject.CharacterString
                                            } else {
                                                $charstring = $CharacterString
                                            }

                                            # Setup the new value parameters
                                            $newValueParams = $null

                                            if ($null -eq $columnobject.SubType) {
                                                $newValueParams = @{
                                                    DataType        = $columnobject.ColumnType
                                                    Min             = $min
                                                    Max             = $max
                                                    CharacterString = $charstring
                                                    Format          = $columnobject.Format
                                                    Locale          = $Locale
                                                }
                                            } elseif ($columnobject.SubType.ToLowerInvariant() -eq 'shuffle') {
                                                if ($columnobject.ColumnType -in 'bigint', 'char', 'int', 'nchar', 'nvarchar', 'smallint', 'tinyint', 'varchar') {
                                                    $newValueParams = @{
                                                        RandomizerType    = "Random"
                                                        RandomizerSubtype = "Shuffle"
                                                        Value             = ($row.$($columnobject.Name))
                                                        Locale            = $Locale
                                                    }
                                                } elseif ($columnobject.ColumnType -in 'decimal', 'numeric', 'float', 'money', 'smallmoney', 'real') {
                                                    $newValueParams = @{
                                                        RandomizerType    = "Random"
                                                        RandomizerSubtype = "Shuffle"
                                                        Value             = ($row.$($columnobject.Name))
                                                        Locale            = $Locale
                                                    }
                                                }
                                            } else {
                                                $newValueParams = @{
                                                    RandomizerType    = $columnobject.MaskingType
                                                    RandomizerSubtype = $columnobject.SubType
                                                    Min               = $min
                                                    Max               = $max
                                                    CharacterString   = $charstring
                                                    Format            = $columnobject.Format
                                                    Separator         = $columnobject.Separator
                                                    Locale            = $Locale
                                                }
                                            }

                                            # Generate the new value
                                            try {
                                                $newValue = Get-DbaRandomizedValue @newValueParams
                                            } catch {
                                                $maskingErrorFlag = $true
                                                Stop-Function -Message "Failure" -Target $columnobject -Continue -ErrorRecord $_
                                            }
                                        }

                                        # Convert the values so they can used in T-SQL
                                        try {
                                            if ($row.($columnobject.Name) -eq '') {
                                                $convertedValue = Convert-DbaMaskingValue -Value ' ' -DataType $columnobject.ColumnType -Nullable:$columnobject.Nullable -EnableException
                                            } else {
                                                $convertedValue = Convert-DbaMaskingValue -Value $newValue -DataType $columnobject.ColumnType -Nullable:$columnobject.Nullable -EnableException
                                            }

                                            if ($convertedValue.ErrorMessage) {
                                                $maskingErrorFlag = $true
                                                Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                            }
                                        } catch {
                                            Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $newValue
                                        }

                                        # Add to the updates
                                        $updates += "[$($columnobject.Name)] = $($convertedValue.NewValue)"

                                        # Check if this value is determinisic
                                        if ($columnobject.Deterministic -and ($null -eq $lookupResult.NewValue)) {
                                            if (($null -ne $row.($columnobject.Name)) -and ($row.($columnobject.Name) -ne '')) {
                                                try {
                                                    $previous = Convert-DbaMaskingValue -Value $row.($columnobject.Name) -DataType $columnobject.ColumnType -Nullable:$columnobject.Nullable -EnableException

                                                    if ($convertedValue.ErrorMessage) {
                                                        $maskingErrorFlag = $true
                                                        Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                                    }
                                                } catch {
                                                    Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $row.($columnobject.Name)
                                                }

                                                $query = "INSERT INTO dbo.DeterministicValues (ValueKey, NewValue) VALUES ($($previous.NewValue), $($convertedValue.NewValue));"
                                                try {
                                                    $null = $server.Databases['tempdb'].Query($query)
                                                } catch {
                                                    Stop-Function -Message "Could not save deterministic value.`n$_" -Target $query -ErrorRecord $_
                                                }
                                            }
                                        }

                                        # Setup the query
                                        $updateQuery = "UPDATE [$($tableobject.Schema)].[$($tableobject.Name)] SET $($updates -join ', ') WHERE [$($identityColumn)] = $($row.$($identityColumn)); "
                                        $null = $stringBuilder.AppendLine($updateQuery)

                                        # Increase the batch row number to keep track of the batches
                                        $batchRowNr++

                                        # if we reached the batchsize
                                        if ($batchRowNr -eq $BatchSize) {
                                            # Increase the batch nr if it's not already reached
                                            if ($batchNr -lt $totalBatches) {
                                                $batchNr++
                                            }

                                            # Execute the batch
                                            try {
                                                $progressParams = @{
                                                    StepNumber = $batchNr
                                                    TotalSteps = $totalBatches
                                                    Activity   = "Masking $($data.Count) rows in $($tableobject.Schema).$($tableobject.Name).$($columnobject.Name) in $($dbName) on $instance"
                                                    Message    = "Executing Batch $batchNr/$totalBatches"
                                                }

                                                Write-ProgressHelper @progressParams

                                                Write-Message -Level Verbose -Message "Executing batch $batchNr/$totalBatches"

                                                $queryParams = @{
                                                    SqlInstance     = $instance
                                                    SqlCredential   = $SqlCredential
                                                    Database        = $db.Name
                                                    Query           = $stringBuilder.ToString()
                                                    EnableException = $EnableException
                                                    QueryTimeout    = $CommandTimeout
                                                }

                                                Invoke-DbaQuery @queryParams
                                            } catch {
                                                $maskingErrorFlag = $true
                                                Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name): $_ `n$($stringBuilder.ToString())" -Target $stringBuilder.ToString() -Continue -ErrorRecord $_
                                            }

                                            $null = $stringBuilder.Clear()
                                            $batchRowNr = 0
                                        }
                                    }

                                    if ($stringBuilder.Length -ge 1) {
                                        if ($batchNr -lt $totalBatches) {
                                            $batchNr++
                                        }

                                        try {
                                            $progressParams = @{
                                                StepNumber = $batchNr
                                                TotalSteps = $totalBatches
                                                Activity   = "Masking $($data.Count) rows in $($tableobject.Schema).$($tableobject.Name) in $($dbName) on $instance"
                                                Message    = "Executing Batch $batchNr/$totalBatches"
                                            }

                                            Write-ProgressHelper @progressParams

                                            Write-Message -Level Verbose -Message "Executing batch $batchNr/$totalBatches"

                                            $queryParams = @{
                                                SqlInstance     = $instance
                                                SqlCredential   = $SqlCredential
                                                Database        = $db.Name
                                                Query           = $stringBuilder.ToString()
                                                EnableException = $EnableException
                                                QueryTimeout    = $CommandTimeout
                                            }

                                            Invoke-DbaQuery @queryParams
                                        } catch {
                                            $maskingErrorFlag = $true
                                            Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name): $_`n$($stringBuilder.ToString())" -Target $stringBuilder.ToString() -Continue -ErrorRecord $_
                                        }
                                    }
                                }
                            }
                        }

                        $null = $stringBuilder.Clear()

                        # Go through the actions
                        if ($columnsWithActions.Count -ge 1) {
                            foreach ($columnObject in $columnsWithActions) {
                                Write-Message -Level Verbose -Message "Processing action for [$($columnObject.Name)]"

                                [bool]$validAction = $true

                                $columnAction = $columnobject.Action

                                $query = "UPDATE [$($tableobject.Schema)].[$($tableobject.Name)] SET [$($columnObject.Name)] = "

                                if ($columnAction.Category -eq 'DateTime') {
                                    switch ($columnAction.Type) {
                                        "Add" {
                                            $query += "DATEADD($($columnAction.SubCategory), $($columnAction.Value), [$($columnObject.Name)]);"
                                        }
                                        "Subtract" {
                                            $query += "DATEADD($($columnAction.SubCategory), - $($columnAction.Value), [$($columnObject.Name)]);"
                                        }
                                        default {
                                            $validAction = $false
                                        }
                                    }
                                } elseif ($columnAction.Category -eq 'Number') {
                                    switch ($columnAction.Type) {
                                        "Add" {
                                            $query += "[$($columnObject.Name)] + $($columnAction.Value);"
                                        }
                                        "Divide" {
                                            $query += "[$($columnObject.Name)] / $($columnAction.Value);"
                                        }
                                        "Multiply" {
                                            $query += "[$($columnObject.Name)] * $($columnAction.Value);"
                                        }
                                        "Subtract" {
                                            $query += "[$($columnObject.Name)] - $($columnAction.Value);"
                                        }
                                        default {
                                            $validAction = $false
                                        }
                                    }
                                } elseif ($columnAction.Category -eq 'Column') {
                                    switch ($columnAction.Type) {
                                        "Set" {
                                            if ($columnobject.ColumnType -like '*int*' -or $columnobject.ColumnType -in 'bit', 'bool', 'decimal', 'numeric', 'float', 'money', 'smallmoney', 'real') {
                                                $query += "$($columnAction.Value)"
                                            } elseif ($columnobject.ColumnType -in '*date*', 'time', 'uniqueidentifier') {
                                                $query += "'$($columnAction.Value)'"
                                            } else {
                                                $query += "'$($columnAction.Value)'"
                                            }
                                        }
                                        "Nullify" {
                                            if ($columnobject.Nullable) {
                                                $query += "NULL"
                                            } else {
                                                $validAction = $false
                                            }
                                        }
                                        default {
                                            $validAction = $false
                                        }
                                    }
                                }
                                # Add the query to the rest
                                if ($validAction) {
                                    $null = $stringBuilder.AppendLine($query)
                                }
                            }

                            try {
                                if ($stringBuilder.Length -ge 1) {
                                    Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $db.Name -Query $stringBuilder.ToString() -EnableException
                                }
                            } catch {
                                $stringBuilder.ToString()
                                Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name): $_" -Target $stringBuilder -Continue -ErrorRecord $_
                            }

                            $null = $stringBuilder.Clear()
                        }

                        # Go through the composites
                        if ($columnsWithComposites.Count -ge 1) {
                            foreach ($columnObject in $columnsWithComposites) {
                                Write-Message -Level Verbose -Message "Processing composite for [$($columnObject.Name)]"

                                $compositeItems = @()

                                foreach ($columnComposite in $columnObject.Composite) {
                                    if ($columnComposite.Type -eq 'Column') {
                                        $compositeItems += "[$($columnComposite.Value)]"
                                    } elseif ($columnComposite.Type -eq 'Static') {
                                        $compositeItems += "'$($columnComposite.Value)'"
                                    } elseif ($columnComposite.Type -in $supportedFakerMaskingTypes) {
                                        try {
                                            $newValue = $null

                                            if ($columnobject.SubType -in $supportedDataTypes) {
                                                $newValueParams = @{
                                                    DataType        = $columnobject.SubType
                                                    CharacterString = $charstring
                                                    Min             = $columnComposite.Min
                                                    Max             = $columnComposite.Max
                                                    Locale          = $Locale
                                                }

                                                $newValue = Get-DbaRandomizedValue @newValueParams
                                            } else {
                                                $newValueParams = @{
                                                    RandomizerType    = $columnobject.MaskingType
                                                    RandomizerSubtype = $columnobject.SubType
                                                    Min               = $min
                                                    Max               = $max
                                                    CharacterString   = $charstring
                                                    Format            = $columnobject.Format
                                                    Separator         = $columnobject.Separator
                                                    Locale            = $Locale
                                                }

                                                $newValue = Get-DbaRandomizedValue @newValueParams
                                            }
                                        } catch {
                                            Stop-Function -Message "Failure" -Target $faker -Continue -ErrorRecord $_
                                        }

                                        if ($columnobject.ColumnType -match 'int') {
                                            $compositeItems += " $newValue"
                                        } elseif ($columnobject.ColumnType -in 'bit', 'bool') {
                                            if ($columnValue) {
                                                $compositeItems += "1"
                                            } else {
                                                $compositeItems += "0"
                                            }
                                        } else {
                                            $newValue = ($newValue).Tostring().Replace("'", "''")
                                            $compositeItems += "'$newValue'"
                                        }
                                    } else {
                                        $compositeItems += ""
                                    }
                                }

                                $compositeItemsUpdated = $compositeItems | ForEach-Object { $_ = "ISNULL($($_), '')"; $_ }

                                $null = $stringBuilder.AppendLine("UPDATE [$($tableobject.Schema)].[$($tableobject.Name)] SET [$($columnObject.Name)] = $($compositeItemsUpdated -join ' + ')")
                            }

                            try {
                                $stringBuilder.ToString()
                                Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $db.Name -Query $stringBuilder.ToString() -EnableException
                            } catch {
                                Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name): $_" -Target $stringBuilder -Continue -ErrorRecord $_
                            }

                            $null = $stringBuilder.Clear()
                        }

                        # Clean up the masking index
                        try {
                            # Refresh the indexes to make sure to have the latest list
                            $dbTable.Indexes.Refresh()

                            # Check if the index is there
                            if ($dbTable.Indexes.Name -contains $maskingIndexName) {
                                Write-Message -Level verbose -Message "Removing identity index from table [$($dbTable.Schema)].[$($dbTable.Name)]"
                                $dbTable.Indexes[$($maskingIndexName)].Drop()
                            }
                        } catch {
                            Stop-Function -Message "Could not remove identity index from table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue
                        }

                        # Clean up the identity column
                        if ($cleanupIdentityColumn) {
                            try {
                                Write-Message -Level Verbose -Message "Removing identity column [$($identityColumn)] from table [$($dbTable.Schema)].[$($dbTable.Name)]"

                                $query = "ALTER TABLE [$($dbTable.Schema)].[$($dbTable.Name)] DROP COLUMN [$($identityColumn)]"

                                Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $db.Name -Query $query -EnableException
                            } catch {
                                Stop-Function -Message "Could not remove identity column from table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue
                            }
                        }

                        # Return the masking results
                        if ($maskingErrorFlag) {
                            $maskingStatus = "Failed"
                        } else {
                            $maskingStatus = "Successful"
                        }

                        [pscustomobject]@{
                            ComputerName = $db.Parent.ComputerName
                            InstanceName = $db.Parent.ServiceName
                            SqlInstance  = $db.Parent.DomainInstanceName
                            Database     = $dbName
                            Schema       = $tableobject.Schema
                            Table        = $tableobject.Name
                            Columns      = $tableobject.Columns.Name
                            Rows         = $($data.Count)
                            Elapsed      = [prettytimespan]$elapsed.Elapsed
                            Status       = $maskingStatus
                        }


                        # Reset time
                        $null = $elapsed.Reset()
                    }

                    # Cleanup
                    if ($uniqueDataTableName) {
                        Write-Message -Message "Cleaning up unique temporary table '$uniqueDataTableName'" -Level verbose
                        $query = "DROP TABLE [$($uniqueDataTableName)];"
                        try {
                            $null = Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $query -EnableException
                        } catch {
                            Stop-Function -Message "Could not clean up unique values table '$uniqueDataTableName'" -Target $uniqueDataTableName -ErrorRecord $_
                        }
                    }
                }
                #endregion for each table

                # Export the dictionary when needed
                if ($DictionaryExportPath) {
                    try {
                        # Handle dictionary
                        $query = "SELECT [ValueKey], [NewValue] FROM dbo.DeterministicValues"
                        [array]$dictResult = $server.Databases['tempdb'].Query($query)

                        if ($dictResult.Count -ge 1) {
                            Write-Message -Message "Writing dictionary for $($db.Name)" -Level Verbose

                            # Check if the output directory already exists
                            if (-not (Test-Path -Path $DictionaryExportPath)) {
                                $null = New-Item -Path $DictionaryExportPath -ItemType Directory
                            }

                            # Of course with Linux we need to change the slashes
                            if (-not $script:isWindows) {
                                $dictionaryFileName = $dictionaryFileName.Replace("\", "/")
                            }

                            # Setup the file paths
                            $filenamepart = $server.Name.Replace('\', '$').Replace('TCP:', '').Replace(',', '.')
                            $dictionaryFileName = "$DictionaryExportPath\$($filenamepart).$($db.Name).Dictionary.csv"

                            # Export dictionary
                            $null = $dictResult | Export-Csv -Path $dictionaryFileName -NoTypeInformation

                            Get-ChildItem -Path $dictionaryFileName
                        } else {
                            Write-Message -Level Verbose -Message "No values to export as a dictionary"
                        }
                    } catch {
                        Stop-Function -Message "Something went wrong writing the dictionary to the $DictionaryExportPath" -Target $DictionaryExportPath -Continue -ErrorRecord $_
                    }
                }
            } # End foreach database

            # Do some cleanup
            $null = $server.Databases['tempdb'].Tables.Refresh()

            if ($server.Databases['tempdb'].Tables.Name -contains 'DeterministicValues') {
                $query = "DROP TABLE dbo.DeterministicValues"

                try {
                    Write-Message -Level Verbose -Message "Cleaning up deterministic values table"
                    $null = $server.Databases['tempdb'].Query($query)
                } catch {
                    Stop-Function -Message "Could not remove deterministic value table" -ErrorRecord $_
                }
            }

        } # End foreach instance
    } # End process block
} # End
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUsO2v3KjTa62vC22jH6vD2+es
# RJegghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFLsW8RTpwP3e1fzQcZIcMbdOGszqMA0G
# CSqGSIb3DQEBAQUABIIBAI8apMBs4A3raPUDnjCqjaLsonCq2gQWIuucHkfWiagA
# 9fNtMO+O3/nycSsZiJb/QD0T0TEZNf9NzZTsIYJfhXnohQqQZ8BMvVyX16AjFsUh
# U9IVE5qDItvGJR2rZ4a9agu9IyYcemYxkR7KPk0IkukDToPpTnOzyytl3Qm2IoYx
# E1QMlE0xDQTLDhWiGAQSqok62yVUr5tJ7bVgJHAczIEmXuaq4cGjJ3LrsndHvY3b
# zoj+hPp4txhTT3oXkiRwYVQIX9qPWDqZHTI3YrWbcINMpmOo0wgVD2J/QC9iTcrM
# 5bl2tkD+difAhU03xpQ4m7bxYFczL7flKBdY35I4uX2hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU1WjAvBgkqhkiG9w0BCQQxIgQgJBD9SdZTPjlUbIorp3Gd
# s119I7h63z99zhQALPrrojcwDQYJKoZIhvcNAQEBBQAEggIAbnDUBK2pIMxIMJjP
# CEWSNFcWJqCl+LEvWLigYJZLNJhKH9rJH6Bmd+laNAlAGqmpVNDTbL2NDHFLmJx+
# eTMJCbVHPu+NTFQhoRXX4OadZvkLuoE5JQ7406K4qDvHlTb8B+Ic97FTqvkvicIP
# JL7objvQ3smJktu+pWJRm0aqDxAbaeCTFHHNkXB598Mql6mWz0AQ1zxCzDuBQFrh
# poxmG0FTUOws2B21G3sA4OZtphMSHwNlbwCaXkMi254fmKpz8uNRwPUoeT2clUMJ
# PO5P4oiFC6ewuH/MoE4lAj6Q7Z2dtdLx2L45er2uTZzbDrAYpozj4LQLYsnkhvp4
# 2SWPNf+x9c6c2uEVGq86whdXjcl731sdEP8e49AuYpC3fBghUXlS939vR4YSdrr6
# XDYvAEfF10BAPiERAy60kSHbE0af7BI/uDAAbOo0/NT7VIb0vMFUdIvYHkK6pL96
# 9fZMX2IoTV2j6ebXl1KVMXxrHdjWig9HomN8ju8NSiQD2HMgD/i4HRGV09iDAHqu
# 6VEDDe4xk1zvedp4r60PBNPUZIrxvOxGZq4BY3sdRshN8mPoq16mOoeXrK59RY2C
# ciVUjAzk+xhZI4HySqcvsKAZlzp5XqisTRkfivhHFccTWI8oGCokBW3IxiVgZDHg
# kKTX89d4IOUrFAKrlqKhBSF3e6k=
# SIG # End signature block
