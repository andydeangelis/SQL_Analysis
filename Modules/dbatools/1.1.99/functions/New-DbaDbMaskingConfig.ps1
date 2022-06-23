function New-DbaDbMaskingConfig {
    <#
    .SYNOPSIS
        Generates a new data masking configuration file to be used with Invoke-DbaDbDataMasking

    .DESCRIPTION
        Generates a new data masking configuration file. This file is important to apply any data masking to the data in a database.

        Note that the following column and data types are not currently supported:
        Identity
        ForeignKey
        Computed
        Hierarchyid
        Geography
        Geometry
        Xml

        Read more here:
        https://sachabarbs.wordpress.com/2018/06/11/bogus-simple-fake-data-tool/
        https://github.com/bchavez/Bogus

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

    .PARAMETER Path
        Path where to save the generated JSON files.
        Th naming convention will be "servername.databasename.tables.json"

    .PARAMETER Locale
        Set the local to enable certain settings in the masking

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER SampleCount
        Amount of rows to sample to make an assessment. The default is 100

    .PARAMETER KnownNameFilePath
        Points to a file containing the custom known names

    .PARAMETER PatternFilePath
        Points to a file containing the custom patterns

    .PARAMETER ExcludeDefaultKnownName
        Excludes the default known names

    .PARAMETER ExcludeDefaultPattern
        Excludes the default patterns

    .PARAMETER Force
        Forcefully execute commands when needed

    .PARAMETER InputObject
        Used for piping the values from Invoke-DbaDbPiiScan

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        https://dbatools.io/New-DbaDbMaskingConfig

    .EXAMPLE
        New-DbaDbMaskingConfig -SqlInstance SQLDB1 -Database DB1 -Path C:\Temp\clone

        Process all tables and columns for database DB1 on instance SQLDB1

    .EXAMPLE
        New-DbaDbMaskingConfig -SqlInstance SQLDB1 -Database DB1 -Table Customer -Path C:\Temp\clone

        Process only table Customer with all the columns

    .EXAMPLE
        New-DbaDbMaskingConfig -SqlInstance SQLDB1 -Database DB1 -Table Customer -Column City -Path C:\Temp\clone

        Process only table Customer and only the column named "City"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [string[]]$Column,
        [parameter(Mandatory)]
        [string]$Path,
        [string]$Locale = 'en',
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [int]$SampleCount = 100,
        [string]$KnownNameFilePath,
        [string]$PatternFilePath ,
        [switch]$ExcludeDefaultKnownName,
        [switch]$ExcludeDefaultPattern,
        [switch]$Force,
        [parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {

        # Initialize the arrays
        $knownNames = @()
        $patterns = @()

        # Get the known names
        if (-not $ExcludeDefaultKnownName) {
            try {
                $knownNameFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-knownnames.json"
                $knownNames += Get-Content -Path $knownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse known names file" -ErrorRecord $_
                return
            }
        }

        # Get the patterns
        if (-not $ExcludeDefaultPattern) {
            try {
                $patternFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-patterns.json"
                $patterns = Get-Content -Path $patternFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse pattern file" -ErrorRecord $_
                return
            }
        }

        # Get custom known names and patterns
        if ($KnownNameFilePath) {
            if (Test-Path -Path $KnownNameFilePath) {
                try {
                    $knownNames += Get-Content -Path $KnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse known types file" -ErrorRecord $_ -Target $KnownNameFilePath
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find known names file" -Target $KnownNameFilePath
            }
        }

        if ($PatternFilePath ) {
            if (Test-Path -Path $PatternFilePath ) {
                try {
                    $patterns += Get-Content -Path $PatternFilePath  -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse patterns file" -ErrorRecord $_ -Target $PatternFilePath
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find patterns file" -Target $PatternFilePath
            }
        }

        # Check if the Path is accessible
        if (-not (Test-Path -Path $Path)) {
            try {
                $null = New-Item -Path $Path -ItemType Directory -Force:$Force
            } catch {
                Stop-Function -Message "Could not create Path directory" -ErrorRecord $_ -Target $Path
            }
        } else {
            if ((Get-Item $path) -isnot [System.IO.DirectoryInfo]) {
                Stop-Function -Message "$Path is not a directory"
            }
        }

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

        $maskingconfig = @()
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($InputObject) {
            $searchArray = @()
            $searchArray += $InputObject | Select-Object ComputerName, InstanceName, SqlInstance, Database, Schema, Table, Column
        }

        if ($SqlInstance) {
            $databases += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $databases) {
            $server = $db.Parent
            $tables = @()

            # Get the tables
            if ($Table) {
                $tablecollection = $db.Tables | Where-Object Name -in $Table
            } else {
                $tablecollection = $db.Tables
            }

            if ($tablecollection.Count -lt 1) {
                Stop-Function -Message "The database does not contain any tables" -Target $db -Continue
            }

            # Loop through the tables
            foreach ($tableobject in $tablecollection) {
                Write-Message -Message "Processing table [$($tableobject.Schema)].[$($tableobject.Name)]" -Level Verbose

                $hasUniqueIndex = $false

                if ($tableobject.Indexes.IsUnique) {
                    $hasUniqueIndex = $true
                }

                $columns = @()

                # Get the columns
                if ($Column) {
                    [array]$columncollection = $tableobject.Columns | Where-Object Name -in $Column
                } else {
                    [array]$columncollection = $tableobject.Columns
                }

                foreach ($columnobject in $columncollection) {
                    $result = $minValue = $maxValue = $null

                    # Skip incompatible columns
                    if ($columnobject.Identity) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is an identity column"
                        continue
                    }

                    if ($columnobject.IsForeignKey) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a foreign key"
                        continue
                    }

                    if ($columnobject.Computed) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a computed column"
                        continue
                    }

                    if ($server.VersionMajor -ge 13 -and $columnobject.GeneratedAlwaysType -ne 'None') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a computed column for temporal tables"
                        continue
                    }

                    if ($columnobject.DataType.Name -notin $supportedDataTypes) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is not a supported data type"
                        continue
                    }

                    if ($columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -eq 'xml') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a xml column"
                        continue
                    }

                    $searchObject = [pscustomobject]@{
                        ComputerName = $db.Parent.ComputerName
                        InstanceName = $db.Parent.ServiceName
                        SqlInstance  = $db.Parent.DomainInstanceName
                        Database     = $db.Name
                        Schema       = $tableobject.Schema
                        Table        = $tableobject.Name
                        Column       = $columnobject.Name
                    }

                    if ($columnobject.Datatype.Name -in 'date', 'datetime', 'datetime2', 'smalldatetime', 'time') {
                        $columnLength = $columnobject.Datatype.NumericScale
                    } else {
                        $columnLength = $columnobject.Datatype.MaximumLength
                    }

                    $columnType = $columnobject.DataType.Name

                    switch ($columnType) {
                        "bigint" {
                            $minValue = 1
                            $maxValue = 9223372036854775807
                        }
                        { $_ -in "char", "nchar", "nvarchar", "varchar" } {
                            if ($columnLength -eq -1) {
                                if ($_ -in "char", "varchar") {
                                    $minValue = 1
                                    $maxValue = 8000
                                } elseif ($_ -in "nchar", "nvarchar") {
                                    $minValue = 1
                                    $maxValue = 4000
                                }
                            } else {
                                $minValue = [int]($columnLength / 2)
                                $maxValue = $columnLength
                            }
                        }
                        "date" { $maxValue = $null }
                        "datetime" { $maxValue = $null }
                        "datetime2" { $maxValue = $null }
                        "decimal" {
                            $minValue = 1.1
                            $maxValue = $null
                        }
                        "float" {
                            $minValue = 1.1
                            $maxValue = $null
                        }
                        "int" {
                            $minValue = 1
                            $maxValue = 2147483647
                        }
                        "money" {
                            $minValue = 1.0
                            $maxValue = 922337203685477.5807
                        }
                        "smallint" {
                            $minValue = 1
                            $maxValue = 32767
                        }
                        "smalldatetime" {
                            $maxValue = $null
                        }
                        "text" {
                            $minValue = 10
                            $maxValue = 2147483647
                        }
                        "time" {
                            $maxValue = $null
                        }
                        "tinyint" {
                            $minValue = 1
                            $maxValue = 255
                        }
                        "varbinary" {
                            $maxValue = $columnLength
                        }
                        "userdefineddatatype" {
                            if ($columnLength -eq 1) {
                                $maxValue = $columnLength
                            } else {
                                $minValue = [int]($columnLength / 2)
                                $maxValue = $columnLength
                            }
                        }
                        default {
                            $minValue = [int]($columnLength / 2)
                            $maxValue = $columnLength
                        }
                    }

                    if ($searchArray -contains $searchObject) {
                        $result = $InputObject | Where-Object { $_.Database -eq $searchObject.Name -and $_.Schema -eq $searchObject.Schema -and $_.Table -eq $searchObject.Name -and $_.Column -eq $searchObject.Name }
                    } else {

                        if ($columnobject.InPrimaryKey -and $columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -notmatch 'date') {
                            $minValue = 2
                        }

                        if ($columnobject.DataType.Name -eq "geography") {
                            # Add the results
                            $result = [pscustomobject]@{
                                ComputerName   = $db.Parent.ComputerName
                                InstanceName   = $db.Parent.ServiceName
                                SqlInstance    = $db.Parent.DomainInstanceName
                                Database       = $db.Name
                                Schema         = $tableobject.Schema
                                Table          = $tableobject.Name
                                Column         = $columnobject.Name
                                "PII-Category" = "Location"
                                "PII-Name"     = "Geography"
                                FoundWith      = "DataType"
                                MaskingType    = "Random"
                                MaskingSubType = "Decimal"
                            }
                        } else {
                            if ($knownNames.Count -ge 1) {
                                # Go through the first check to see if any column is found with a known name
                                foreach ($knownName in $knownNames) {
                                    foreach ($pattern in $knownName.Pattern) {
                                        if ($null -eq $result -and $columnobject.Name -match $pattern ) {
                                            # Add the results
                                            $result = [pscustomobject]@{
                                                ComputerName   = $db.Parent.ComputerName
                                                InstanceName   = $db.Parent.ServiceName
                                                SqlInstance    = $db.Parent.DomainInstanceName
                                                Database       = $db.Name
                                                Schema         = $tableobject.Schema
                                                Table          = $tableobject.Name
                                                Column         = $columnobject.Name
                                                "PII-Category" = $knownName.Category
                                                "PII-Name"     = $knownName.Name
                                                FoundWith      = "KnownName"
                                                MaskingType    = $knownName.MaskingType
                                                MaskingSubType = $knownName.MaskingSubType
                                            }
                                        }
                                    }
                                }
                                $knownName = $null
                            } else {
                                Write-Message -Level Verbose -Message "No known names found to perform check on"
                            }

                            # Go through the second check to see if any column is found with a known type
                            if ($patterns.Count -ge 1) {
                                if ($null -eq $result) {
                                    # Setup the query
                                    $query = "SELECT TOP($SampleCount) [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"

                                    # Get the data
                                    $dataset = @()

                                    try {
                                        $dataset += Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query -EnableException
                                    } catch {
                                        $errormessage = $_.Exception.Message.ToString()
                                        Stop-Function -Message "Error executing query [$($tableobject.Schema)].[$($tableobject.Name)]: $errormessage" -Target $updatequery -Continue -ErrorRecord $_
                                    }

                                    # Check if there is any data
                                    if ($dataset.Count -ge 1) {

                                        # Loop through the patterns
                                        foreach ($patternobject in $patterns) {

                                            # If there is a result from the match
                                            if ($null -eq $result -and $dataset.$($columnobject.Name) -match $patternobject.Pattern) {
                                                # Add the results
                                                $result = [pscustomobject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $db.Name
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $patternobject.Category
                                                    "PII-Name"     = $patternobject.Name
                                                    FoundWith      = "Pattern"
                                                    MaskingType    = $patternobject.MaskingType
                                                    MaskingSubType = $patternobject.MaskingSubType
                                                }
                                            }
                                            $patternobject = $null
                                        }
                                    } else {
                                        Write-Message -Message "Table $($tableobject.Name) does not contain any rows" -Level Verbose
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No patterns found to perform check on"
                            }
                        }
                    }

                    if ($result) {
                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $( if ($result.MaskingType -in "String", "String2") { $CharacterString } else { $null } )
                            MinValue        = $minValue
                            MaxValue        = $maxValue
                            MaskingType     = $result.MaskingType
                            SubType         = $result.MaskingSubType
                            Format          = $null
                            Separator       = $null
                            Deterministic   = $false
                            Nullable        = $columnobject.Nullable
                            KeepNull        = $true
                            Composite       = $null
                            Action          = $null
                            StaticValue     = $null
                        }
                    } else {
                        $type = "Random"

                        switch ($columnType) {
                            { $_ -in "bit", "bool" } { $subType = "Bool" }
                            "bigint" { $subType = "Number" }
                            { $_ -in "char", "nchar", "nvarchar", "varchar" } { $subType = "String2" }
                            "date" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "datetime" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "datetime2" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "decimal" { $subType = "Decimal" }
                            "float" { $subType = "Float" }
                            "int" { $subType = "Number" }
                            "money" {
                                $type = "Commerce"
                                $subType = "Price"
                            }
                            "smallint" { $subType = "Number" }
                            "smalldatetime" { $subType = "Date" }
                            "text" { $subType = "String" }
                            "time" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "tinyint" { $subType = "Number" }
                            "varbinary" { $subType = "Byte" }
                            "userdefineddatatype" {
                                if ($columnLength -eq 1) {
                                    $subType = "Bool"
                                } else {
                                    $subType = "String2"
                                }
                            }
                            "uniqueidentifier" {
                                $subType = "Guid"
                            }
                            default {
                                $subType = "String2"
                            }
                        }

                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $( if ($subType -in "String", "String2") { $CharacterString } else { $null } )
                            MinValue        = $minValue
                            MaxValue        = $maxValue
                            MaskingType     = $type
                            SubType         = $subType
                            Format          = $null
                            Separator       = $null
                            Deterministic   = $false
                            Nullable        = $columnobject.Nullable
                            KeepNull        = $true
                            Composite       = $null
                            Action          = $null
                            StaticValue     = $null
                        }
                    }
                }

                # Check if something needs to be generated
                if ($columns) {
                    $tables += [PSCustomObject]@{
                        Name           = $tableobject.Name
                        Schema         = $tableobject.Schema
                        Columns        = $columns
                        HasUniqueIndex = $hasUniqueIndex
                        FilterQuery    = $null
                    }
                } else {
                    Write-Message -Message "No columns match for masking in table $($tableobject.Name)" -Level Verbose
                }
            }

            # Check if something needs to be generated
            if ($tables) {
                $maskingconfig += [PSCustomObject]@{
                    Name   = $db.Name
                    Type   = "DataMaskingConfiguration"
                    Tables = $tables
                }
            } else {
                Write-Message -Message "No columns match for masking in table $($tableobject.Name)" -Level Verbose
            }

            # Write the data to the Path
            if ($maskingconfig) {
                Write-Message -Message "Writing masking config" -Level Verbose
                try {
                    $filenamepart = $server.Name.Replace('\', '$').Replace('TCP:', '').Replace(',', '.')

                    if ($Table) {
                        $temppath = Join-Path -Path $Path -ChildPath "$($filenamepart).$($db.Name).$($Table -join '-').DataMaskingConfig.json"
                    } else {
                        $temppath = Join-Path -Path $Path -ChildPath "$($filenamepart).$($db.Name).DataMaskingConfig.json"
                    }

                    if (-not $script:isWindows) {
                        $temppath = $temppath.Replace("\", "/")
                    }

                    Set-Content -Path $temppath -Value ($maskingconfig | ConvertTo-Json -Depth 5)
                    Get-ChildItem -Path $temppath
                } catch {
                    Stop-Function -Message "Something went wrong writing the results to the '$Path'" -Target $Path -Continue -ErrorRecord $_
                }
            } else {
                Write-Message -Message "No tables to save for database $($db.Name) on $($server.Name)" -Level Verbose
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWAnnG7JOJUPPllV4BhAAqD4o
# I4ugghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFCRqoYb7JqrdFnmIXPiNzUf+46KwMA0G
# CSqGSIb3DQEBAQUABIIBAA67QZ/u4cXhTaVzZkLSYOdsXuTrencc6dV9QwhPfMQm
# 8N6VqVWxo/MSdzTqQIWgn9d4HKMh2GhXl3NBBIjq330DdX5Fw22cDkGP/dCUL6WA
# Peo+686W0atFugh6J468qMpjzkC9GthTJG1/+Et214oaMjyYfgcPe4V+HDRF/dnj
# WC9g3s7xvYOTF2xteG2ZCCNXIycsGPEYOkECmqsi5ZsFJWO/ZOPUNzufgYf1xiqC
# 4f+EfWEc8p2nnIGlCZ63WKts+ENWo6W4IPC7jOMxhSEw5QaiH28B0l9BOcXABDKx
# 87L4f0gGhiqD19NNSXq0sys9iv9Y+M3eSAm09Pp+nGWhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDAyWjAvBgkqhkiG9w0BCQQxIgQggVqwbp6ljdPe0R2lXq6r
# ospOmL9DKVfxHFT2iF0pkr8wDQYJKoZIhvcNAQEBBQAEggIAe71qVe8aKWww+nxA
# tvuj6eQViZTjycztW4tgEenBxau14Xr6wXQ/JG+rJIVjVDZ1/qh1xWEiAzmXMbmf
# K+Tdy70iNLAUQwaTppmrLl76wu40jkOfsRIIWMxpuGYzB7KkXxAvTyxUhJAP1Cpi
# OHIYwO+lvTcrYAqHaxZqFf3d8TjcGLtBbfFYc7CF3YKDI5Odue6jByROrYD58jrm
# UbsT3SUmPJUJVGdcq1+Sf66zJDBY8LH8y8scRs8tDTep8se2n17zIxzGbnPG0sdH
# ChdXMLbhj7wqvDyLGEGsOv9hvFUsnWhMbVOpkU0WOcyeQVmVHAuUl1Tzd9a0MU0y
# Wg974qHv46bpyIWa58vIhWEWGsopY0He1vTJub8K6TLkXQL6m6nqek6P2tiGZkRe
# QFeF1cparpJonmMemYMk3hcndhw1k/0RIEac7Z7o1wbk1PCEGnyrNbtSE/ga/Lw8
# 0O98gqmRh3G2g9Ai2tAhrQ28IV3dAqf/J6/1lH/4cvvXNU25Cc9XnUVB3OwavNG0
# ZZbphREUFpVpMD7FWfKNKSJw0WWPxaGonVjQ92Oh+M1tV3a4YjE5JvC8ZdlxAZuJ
# QprkpskuGflVApxMmCnV5n//3CHkm0LuJqaqbTaUv83hPNnAyewtwvO61CZPbk1Y
# /QxivsTY05KOK0ojZv09+0U4Cqw=
# SIG # End signature block
