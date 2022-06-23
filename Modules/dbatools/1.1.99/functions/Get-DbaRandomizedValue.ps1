function Get-DbaRandomizedValue {
    <#
    .SYNOPSIS
        This function will generate a random value for a specific data type or bogus type and subtype

    .DESCRIPTION
        Generates a random value based on the assigned sql data type or bogus type with sub type.
        It supports a wide range of sql data types and an entire dictionary of various random values.

    .PARAMETER DataType
        The target SQL Server instance or instances.

        Supported data types are bigint, bit, bool, char, date, datetime, datetime2, decimal, int, float, guid, money, numeric, nchar, ntext, nvarchar, real, smalldatetime, smallint, text, time, tinyint, uniqueidentifier, userdefineddatatype, varchar

    .PARAMETER RandomizerType
        Bogus type to use.

        Supported types are Address, Commerce, Company, Database, Date, Finance, Hacker, Hashids, Image, Internet, Lorem, Name, Person, Phone, Random, Rant, System

    .PARAMETER RandomizerSubType
        Subtype to use.

    .PARAMETER Min
        Minimum value used to generate certain lengths of values. Default is 0

    .PARAMETER Max
        Maximum value used to generate certain lengths of values. Default is 255

    .PARAMETER Precision
        Precision used for numeric sql data types like decimal, numeric, real and float

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER Format
        Use specilized formatting with certain randomizer types like phone number.

    .PARAMETER Symbol
        Use a symbol in front of the value i.e. $100,12

    .PARAMETER Separator
        Some masking types support separators

    .PARAMETER Value
        This is the value that needs to be used for several possible transformations.
        One example is the subtype "Shuffling" where the value will be shuffled.

    .PARAMETER Locale
        Set the local to enable certain settings in the masking. The default is 'en'

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataMasking, DataGeneration
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRandomizedValue

    .EXAMPLE
        Get-DbaRandomizedValue -DataType bit

        Will return either a 1 or 0

    .EXAMPLE
        Get-DbaRandomizedValue -DataType int

        Will generate a number between -2147483648 and 2147483647

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType Zipcode

        Generates a random zipcode

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType Zipcode -Format "#### ##"

        Generates a random zipcode like "1234 56"

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType PhoneNumber -Format "(###) #######"

        Generates a random phonenumber like "(123) 4567890"

    #>
    [CmdLetBinding()]
    param(
        [string]$DataType,
        [string]$RandomizerType,
        [string]$RandomizerSubType,
        [object]$Min,
        [object]$Max,
        [int]$Precision = 2,
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string]$Format,
        [string]$Symbol,
        [string]$Separator,
        [string]$Value,
        [string]$Locale = 'en',
        [switch]$EnableException
    )


    begin {
        # Create faker object
        if (-not $script:faker) {
            $script:faker = New-Object Bogus.Faker($Locale)
        }

        # Get all the random possibilities
        if (-not $script:randomizerTypes) {
            $script:randomizerTypes = Import-Csv (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\en.randomizertypes.csv") | Group-Object { $_.Type }
        }

        if (-not $script:uniquesubtypes) {
            $script:uniquesubtypes = $script:randomizerTypes.Group | Where-Object Subtype -eq $RandomizerSubType | Select-Object Type -ExpandProperty Type -First 1
        }

        if (-not $script:uniquerandomizertypes) {
            $script:uniquerandomizertypes = ($script:randomizerTypes.Group.Type | Select-Object -Unique)
        }

        if (-not $script:uniquerandomizersubtype) {
            $script:uniquerandomizersubtype = ($script:randomizerTypes.Group.SubType | Select-Object -Unique)
        }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        # Check the variables
        if (-not $DataType -and -not $RandomizerType -and -not $RandomizerSubType) {
            Stop-Function -Message "Please use one of the variables i.e. -DataType, -RandomizerType or -RandomizerSubType" -Continue
        } elseif ($DataType -and ($RandomizerType -or $RandomizerSubType)) {
            Stop-Function -Message "You cannot use -DataType with -RandomizerType or -RandomizerSubType" -Continue
        } elseif (-not $RandomizerSubType -and $RandomizerType) {
            Stop-Function -Message "Please enter a sub type" -Continue
        } elseif (-not $RandomizerType -and $RandomizerSubType) {
            $RandomizerType = $script:uniquesubtypes
        }

        if ($DataType -and $DataType.ToLowerInvariant() -notin $supportedDataTypes) {
            Stop-Function -Message "Unsupported sql data type" -Continue -Target $DataType
        }

        # Check the bogus type
        if ($RandomizerType) {
            if ($RandomizerType -notin $script:uniquerandomizertypes) {
                Stop-Function -Message "Invalid randomizer type" -Continue -Target $RandomizerType
            }
        }

        # Check the sub type
        if ($RandomizerSubType) {
            if ($RandomizerSubType -notin $script:uniquerandomizersubtype) {
                Stop-Function -Message "Invalid randomizer sub type" -Continue -Target $RandomizerSubType
            }

            if ($RandomizerSubType.ToLowerInvariant() -eq 'shuffle' -and $null -eq $Value) {
                Stop-Function -Message "Value cannot be empty when using sub type 'Shuffle'" -Continue -Target $RandomizerSubType
            }
        }

        if ($null -eq $Min) {
            if ($DataType.ToLower() -notlike "date*" -and $RandomizerType.ToLower() -notlike "date*") {
                $Min = 1
            }
        }

        if ($null -eq $Max) {
            if ($DataType.ToLower() -notlike "date*" -and $RandomizerType.ToLower() -notlike "date*") {
                $Max = 255
            }
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($DataType) {

            switch ($DataType.ToLowerInvariant()) {
                'bigint' {
                    if (-not $Min -or $Min -lt -9223372036854775808) {
                        $Min = -9223372036854775808
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 9223372036854775807) {
                        $Max = 9223372036854775807
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Long($Min, $Max)
                }

                { $psitem -in 'bit', 'bool' } {
                    if ($script:faker.Random.Bool()) {
                        1
                    } else {
                        0
                    }
                }
                'date' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'datetime' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'datetime2' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                { $psitem -in 'decimal', 'float', 'money', 'numeric', 'real' } {
                    $script:faker.Finance.Amount($Min, $Max, $Precision)
                }
                'int' {
                    if (-not $Min -or $Min -lt -2147483648) {
                        $Min = -2147483648
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 2147483647 -or $Max -lt $Min) {
                        $Max = 2147483647
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)

                }
                'smalldatetime' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'smallint' {
                    if (-not $Min -or $Min -lt -32768) {
                        $Min = 32768
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 32767 -or $Max -lt $Min) {
                        $Max = 32767
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                'time' {
                    ($script:faker.Date.Past()).ToString("HH:mm:ss.fffffff")
                }
                'tinyint' {
                    if (-not $Min -or $Min -lt 0) {
                        $Min = 0
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 255 -or $Max -lt $Min) {
                        $Max = 255
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                { $psitem -in 'uniqueidentifier', 'guid' } {
                    $script:faker.System.Random.Guid().Guid
                }
                'userdefineddatatype' {
                    if ($Max -eq 1) {
                        if ($script:faker.System.Random.Bool()) {
                            1
                        } else {
                            0
                        }
                    } else {
                        $null
                    }
                }
                { $psitem -in 'char', 'nchar', 'nvarchar', 'varchar' } {
                    $script:faker.Random.String2($Min, $Max, $CharacterString)
                }

            }

        } else {

            $randSubType = $RandomizerSubType.ToLowerInvariant()

            switch ($RandomizerType.ToLowerInvariant()) {
                'address' {

                    if ($randSubType -in 'latitude', 'longitude') {
                        $script:faker.Address.Latitude($Min, $Max)
                    } elseif ($randSubType -eq 'zipcode') {
                        if ($Format) {
                            $script:faker.Address.ZipCode("$($Format)")
                        } else {
                            $script:faker.Address.ZipCode()
                        }
                    } else {
                        $script:faker.Address.$RandomizerSubType()
                    }

                }
                'commerce' {
                    if ($randSubType -eq 'categories') {
                        $script:faker.Commerce.Categories($Max)
                    } elseif ($randSubType -eq 'departments') {
                        $script:faker.Commerce.Department($Max)
                    } elseif ($randSubType -eq 'price') {
                        $script:faker.Commerce.Price($min, $Max, $Precision, $Symbol)
                    } else {
                        $script:faker.Commerce.$RandomizerSubType()
                    }

                }
                'company' {
                    $script:faker.Company.$RandomizerSubType()
                }
                'database' {
                    $script:faker.Database.$RandomizerSubType()
                }
                'date' {
                    if ($randSubType -eq 'between') {

                        if (-not $Min) {
                            Stop-Function -Message "Please set the minimum value for the date" -Continue -Target $Min
                        }

                        if (-not $Max) {
                            Stop-Function -Message "Please set the maximum value for the date" -Continue -Target $Max
                        }

                        if ($Min -gt $Max) {
                            Stop-Function -Message "The minimum value for the date cannot be later than maximum value" -Continue -Target $Min
                        } else {
                            ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'past') {
                        if ($Max) {
                            if ($Min) {
                                $yearsToGoBack = [math]::round((([datetime]$Max - [datetime]$Min).Days / 365), 0)
                            } else {
                                $yearsToGoBack = 1
                            }

                            $script:faker.Date.Past($yearsToGoBack, $Max).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            $script:faker.Date.Past().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'future') {
                        if ($Min) {
                            if ($Max) {
                                $yearsToGoForward = [math]::round((([datetime]$Max - [datetime]$Min).Days / 365), 0)
                            } else {
                                $yearsToGoForward = 1
                            }

                            $script:faker.Date.Future($yearsToGoForward, $Min).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            $script:faker.Date.Future().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }

                    } elseif ($randSubType -eq 'recent') {
                        $script:faker.Date.Recent().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } elseif ($randSubType -eq 'random') {
                        if ($Min -or $Max) {
                            if (-not $Min) {
                                $Min = Get-Date
                            }

                            if (-not $Max) {
                                $Max = (Get-Date).AddYears(1)
                            }

                            ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } else {
                        $script:faker.Date.$RandomizerSubType()
                    }
                }
                'finance' {
                    if ($randSubType -eq 'account') {
                        $script:faker.Finance.Account($Max)
                    } elseif ($randSubType -eq 'amount') {
                        $script:faker.Finance.Amount($Min, $Max, $Precision)
                    } else {
                        $script:faker.Finance.$RandomizerSubType()
                    }
                }
                'hacker' {
                    $script:faker.Hacker.$RandomizerSubType()
                }
                'image' {
                    $script:faker.Image.$RandomizerSubType()
                }
                'internet' {
                    if ($randSubType -eq 'password') {
                        $script:faker.Internet.Password($Max)
                    } elseif ($randSubType -eq 'mac') {
                        if ($Separator) {
                            $script:faker.Internet.Mac($Separator)
                        } else {
                            if (-not $Format -or $Format -eq "##:##:##:##:##:##") {
                                $script:faker.Internet.Mac()
                            } elseif ($Format -eq "############") {
                                $script:faker.Internet.Mac("")
                            } else {
                                $newMacArray = $Format.ToCharArray()

                                $macAddress = $script:faker.Internet.Mac("")
                                $macArray = $macAddress.ToCharArray()

                                $macIndex = 0
                                for ($i = 0; $i -lt $formatArray.Count; $i++) {
                                    if ($newMacArray[$i] -eq "#") {
                                        $newMacArray[$i] = $macArray[$macIndex]
                                        $macIndex++
                                    }
                                }

                                $newMacArray -join ""
                            }
                        }
                    } else {
                        $script:faker.Internet.$RandomizerSubType()
                    }
                }
                'lorem' {
                    if ($randSubType -eq 'paragraph') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Paragraph($Min)

                    } elseif ($randSubType -eq 'paragraphs') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Paragraphs($Min)

                    } elseif ($randSubType -eq 'letter') {
                        $script:faker.Lorem.Letter($Max)
                    } elseif ($randSubType -eq 'lines') {
                        $script:faker.Lorem.Lines($Max)
                    } elseif ($randSubType -eq 'sentence') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Sentence($Min, $Max)

                    } elseif ($randSubType -eq 'sentences') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Sentences($Min, $Max)

                    } elseif ($randSubType -eq 'slug') {
                        $script:faker.Lorem.Slug($Max)
                    } elseif ($randSubType -eq 'words') {
                        $script:faker.Lorem.Words($Max)
                    } else {
                        $script:faker.Lorem.$RandomizerSubType()
                    }
                }
                'name' {
                    $script:faker.Name.$RandomizerSubType()
                }
                'person' {
                    if ($randSubType -eq "phone") {
                        if ($Format) {
                            $script:faker.Phone.PhoneNumber($Format)
                        } else {
                            $script:faker.Phone.PhoneNumber()
                        }
                    } else {
                        $script:faker.Person.$RandomizerSubType
                    }
                }
                'phone' {
                    if ($Format) {
                        $script:faker.Phone.PhoneNumber($Format)
                    } else {
                        $script:faker.Phone.PhoneNumber()
                    }
                }
                'random' {
                    if ($randSubType -in 'byte', 'char', 'decimal', 'double', 'even', 'float', 'int', 'long', 'number', 'odd', 'sbyte', 'short', 'uint', 'ulong', 'ushort') {
                        $script:faker.Random.$RandomizerSubType($Min, $Max)
                    } elseif ($randSubType -eq 'bytes') {
                        $script:faker.Random.Bytes($Max)
                    } elseif ($randSubType -in 'string', 'string2') {
                        $script:faker.Random.String2([int]$Min, [int]$Max, $CharacterString)
                    } elseif ($randSubType -eq 'shuffle') {
                        $commaIndex = $value.IndexOf(",")
                        $dotIndex = $value.IndexOf(".")

                        $Value = (($Value -replace ',', '') -replace '\.', '')

                        $newValue = ($script:faker.Random.Shuffle($Value) -join '')

                        if ($commaIndex -ne -1) {
                            $newValue = $newValue.Insert($commaIndex, ',')
                        }

                        if ($dotIndex -ne -1) {
                            $newValue = $newValue.Insert($dotIndex, '.')
                        }

                        $newValue
                    } else {
                        $script:faker.Random.$RandomizerSubType()
                    }
                }
                'rant' {
                    if ($randSubType -eq 'reviews') {
                        $script:faker.Rant.Review($script:faker.Commerce.Product())
                    } elseif ($randSubType -eq 'reviews') {
                        $script:faker.Rant.Reviews($script:faker.Commerce.Product(), $Max)
                    }
                }
                'system' {
                    $script:faker.System.$RandomizerSubType()
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUBaWLVymE5vggGic8VP9JQlxK
# 4d6gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFP9oOX+606EgFCmBz2x4b2szU4K7MA0G
# CSqGSIb3DQEBAQUABIIBAKhuDx6F9jJlvXMsECw76RdkfxYf1bnRVSeyZxALm46w
# 34UATlOiU9z0Zis9pQVvs+3MTTGiAALRu0f5VZLXstLUrsfMd0DCaqs4ujRIGN/D
# AgvJ5z+Pnz8viUmCGEYnTSeDdJOxEzLdBhC9hEb9/khXfL1jmF/mVJTvDQPn8kVu
# Ctmq/qBg3RiibKeuG3zXPj080DArsn+49plqs3ugPg97SMFNofvuEaaLBGUxXCgg
# r7ttyYvM6HoZuFQ/CuoBIzGIeB5xnWmnaEJhqPchRav3136Iv96TEDD9oiA6VqNT
# 74qTxTp2aO17GiquVkuSiuO0vUliYKNYGsoepiJKrjuhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzQ0WjAvBgkqhkiG9w0BCQQxIgQg0xHIwnZfTVjmzr1XKYws
# dIqfXzqaK5Hkr3XNeNwqYlswDQYJKoZIhvcNAQEBBQAEggIAS+c5m3BAiXYny1xJ
# S4pDihMrgdlUDL1XiKy6PMQBwUFC96BIcQgDxymeMsxU5z+hGlt417+gI3V1GcTK
# cWMmm8ymKCKzu7Vwi+epFtuL2b5xt8ccOMOBYVI+dT5m1V6cOXe0y+k/zGkS4Hpu
# Jn38UGev3EeVWQ8EHHcnsSe47eGTqL45pzsUhAYmzD61DqHhGpFNbAI8hF7j/LSK
# on4mQjcWmiMk2VbO89zkbNeO7C2Oil2uvO1uSawMHWKy7hqtHUukOqVPD5vE0LOn
# rUjNs4gUja3yGR/CA4JO4Fo65e17JWvg+CvZRRWlzO1rvzlJNGSP5j5wqcLRlX71
# +oaKwLuZJW0xR/+wi/q1+SVPQDWabJ+xw6G0g3G1S/UEWuGuHch8OCEbZxTG2W1i
# T6jT72+NrSfCzTPk3rIPLlaTG3fVC/ODHGP0/gEVWTMC2PoiNFv+MzBF4l06k9CJ
# gAw2BurED1pVJgPM3ua4g1Y0sHj9ThCbt6bPZnjNhlPaEl94Yq5T2EYgN/XSaXFw
# DM3s46h+H7Jfm3TpLq01xs3b4FyHHuvxqqAlmmnNEnA4bc+GC/+osC9R64zYDek1
# 0zorTzIN0ujSC7le1sjGp/aJw/RkUtYD5giqxKJ0qbMVSbtai6MUEIOO3hLKwIk/
# GuvfNxeptEE4Z5Kf5ewqLawxVkg=
# SIG # End signature block
