function Test-DbaDbDataMaskingConfig {
    <#
    .SYNOPSIS
        Checks the masking configuration if it's valid

    .DESCRIPTION
        When you're dealing with large masking configurations, things can get complicated and messy.
        This function will test for a range of rules and returns all the tables and columns that contain errors.

    .PARAMETER FilePath
        Path to the file to test

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing objects on Destination with matching names from Source will be dropped.

    .NOTES
        Tags: Masking, DataMasking
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Test-DbaDbDataMaskingConfig

    .EXAMPLE
        Test-DbaDbDataMaskingConfig -FilePath C:\temp\_datamasking\db1.json

        Test the configuration file
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]$FilePath,
        [switch]$EnableException
    )
    begin {
        if (-not (Test-Path -Path $FilePath)) {
            Stop-Function -Message "Could not find masking config file $FilePath" -Target $FilePath
            return
        }

        # Get all the items that should be processed
        try {
            $json = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath
        }

        if (-not $json.Type) {
            Stop-Function -Message "Configuration file does not contain a type. This is either an older configuration or an invalid one. Please make sure that the json file contains '`"Type`": `"DataMaskingConfiguration`", '" -Target $json.Type
            return
        }

        if ($json.Type -ne "DataMaskingConfiguration") {
            Stop-Function -Message "Configuration file is not a valid masking configuration. Type found '$($json.Type)'" -Target $json.Type
            return
        }

        $supportedDataTypes = @('bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'float', 'int', 'money', 'nchar', 'ntext', 'nvarchar', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar')

        $randomizerTypes = Get-DbaRandomizedType

        $requiredColumnProperties = @('Action', 'CharacterString', 'ColumnType', 'Composite', 'Deterministic', 'Format', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'KeepNull', 'SubType')
        $allowedColumnProperties = @('Action', 'CharacterString', 'ColumnType', 'Composite', 'Deterministic', 'Format', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'KeepNull', 'Separator', 'SubType', 'StaticValue')

        $allowedActionCategories = @('datetime', 'number', 'column')
        $allowedActionSubCategories = @('year', 'quarter', 'month', 'dayofyear', 'day', 'week', 'weekday', 'hour', 'minute', 'second', 'millisecond', 'microsecond', 'nanosecond')
        $allowedActionTypes = @('Add', 'Divide', 'Multiply', 'Nullify', 'Set', 'Subtract')

        $allowedDateTimeTypes = @('date', 'datetime', 'datetime2', 'smalldatetime', 'time')
        $allowedNumberTypes = @('bigint', 'bit', 'decimal', 'float', 'int', 'money', 'numeric', 'smallint')

        $requiredDateTimeActionProperties = @('Category', 'Subcategory', 'Type', 'Value')
        $requiredNumberActionProperties = @('Category', 'Type', 'Value')
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($table in $json.Tables) {

            foreach ($column in $table.Columns) {

                # Test the column properties
                $columnProperties = $column | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object Name -ExpandProperty Name
                $compareResultRequired = Compare-Object -ReferenceObject $requiredColumnProperties -DifferenceObject $columnProperties
                $compareResultAllowed = Compare-Object -ReferenceObject $allowedColumnProperties -DifferenceObject $columnProperties

                if ($null -ne $compareResultRequired) {
                    if ($compareResultRequired.SideIndicator -contains "<=") {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = ($compareResultRequired | Where-Object SideIndicator -eq "<=").InputObject -join ","
                            Error  = "The column does not contain all the required properties. Please check the column "
                        }
                    }
                }

                if ($null -ne $compareResultAllowed) {
                    if ($compareResultAllowed.SideIndicator -contains "=>") {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = ($compareResultAllowed | Where-Object SideIndicator -eq "=>").InputObject -join ","
                            Error  = "The column contains a property that is not in the allowed properties. Please check the column"
                        }
                    }
                }

                # Test column type
                if ($column.ColumnType -notin $supportedDataTypes) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.ColumnType
                        Error  = "ColumnType is not a supported data type "
                    }
                }

                # Test masking type
                if ($column.MaskingType -notin $randomizerTypes.Type) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.MaskingType
                        Error  = "MaskingType is not valid"
                    }
                }

                # Test masking sub type
                if ($null -ne $column.SubType -and $column.SubType -notin $randomizerTypes.SubType) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.SubType
                        Error  = "SubType is not valid"
                    }
                }

                # Test date types
                if ($column.ColumnType.ToLower() -eq 'date') {

                    if ($column.MaskingType -ne 'Date' -and ($column.SubType -ne 'DateOfBirth' -and $null -ne $column.Subtype)) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.MaskingType
                            Error  = "MaskingType should be date when ColumnType is 'date'"
                        }
                    }

                    if ($null -ne $Column.SubType -and $Column.SubType.ToLower() -eq 'between') {

                        if (-not ($null -eq $column.MinValue) -and -not ([datetime]::TryParse($column.MinValue, [ref]"2002-12-31"))) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.MinValue
                                Error  = "The value for MinValue is not a valid date"
                            }
                        }

                        if (-not ($null -eq $column.MaxValue) -and -not ([datetime]::TryParse($column.MaxValue, [ref]"2002-12-31"))) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.MaxValue
                                Error  = "The value for MaxValue is not a valid date"
                            }
                        }

                        if ($null -eq $column.MinValue) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = 'null'
                                Error  = "The value for MinValue cannot be 'null' when using sub type 'Between'"
                            }
                        }

                        if ($null -eq $column.MaxValue) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = 'null'
                                Error  = "The value for MaxValue cannot be 'null' when using sub type 'Between'"
                            }
                        }
                    }
                }

                # Test actions
                if ($column.Action) {
                    # General checks

                    if ($null -ne $column.Action.Category -and $column.Action.Category -notin $allowedActionCategories) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action category '$($column.Action.Category)' is not allowed"
                        }
                    }

                    if ($null -ne $column.Action.Category -and $column.Action.Type -notin $allowedActionTypes) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action type '$($column.Action.Type)' is not allowed"
                        }
                    }

                    if ($column.Action.Category -ne 'Column' -and $column.Action.Type -ne 'Nullify' -and $null -eq $column.Action.Value -and $column.Action.Type -in $allowedActionTypes) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action value cannot be empty"
                        }
                    }

                    if (-not $null -eq $column.Action.SubCategory -and $column.Action.SubCategory -notin $allowedActionSubCategories) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action subcategory cannot be empty"
                        }
                    }

                    $actionProperties = $column.Action | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object Name -ExpandProperty Name

                    # Date checks
                    if ($column.Action.Category -eq 'datetime' ) {

                        $compareResult = Compare-Object -ReferenceObject $requiredDateTimeActionProperties -DifferenceObject $actionProperties

                        if ($null -ne $compareResult) {
                            if ($compareResult.SideIndicator -contains "<=") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "<=").InputObject -join ","
                                    Error  = "The action does not contain all the required properties. Please check the action "
                                }
                            }

                            if ($compareResult.SideIndicator -contains "=>") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "=>").InputObject -join ","
                                    Error  = "The action contains a property that is not in the required properties. Please check the column"
                                }
                            }
                        }

                        if ($column.ColumnType -notin $allowedDateTimeTypes) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.Action.Category
                                Error  = "The category is not valid with data type $($column.ColumnType)"
                            }
                        }
                    }

                    # Number checks
                    if ($column.Action.Category -eq 'number' ) {
                        $compareResult = Compare-Object -ReferenceObject $requiredNumberActionProperties -DifferenceObject $actionProperties

                        if ($null -ne $compareResult) {
                            if ($compareResult.SideIndicator -contains "<=") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "<=").InputObject -join ","
                                    Error  = "The action does not contain all the required properties. Please check the action "
                                }
                            }
                        }

                        if ($column.ColumnType -notin $allowedNumberTypes) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.Action.Category
                                Error  = "The category is not valid with data type $($column.ColumnType)"
                            }
                        }
                    }
                } # End column action
            } # End for each column
        } # End for each table
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUJbZiPyYIfTsT/5S8+yKcdBjj
# UBagghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFA5RLF9RGmBgStGkqvSwGMVbmbmSMA0G
# CSqGSIb3DQEBAQUABIIBAI7MXwFpC/NV34iyGkIWlMjviu6JspkjL22HY117C9Sn
# QFRDfNI4uaDiEVVAad7uBff5ECs4eaB/6lWZ7Wsg7ZKJMxAJzLY6JkIPL2Eh/1TL
# GtTt1EaiN+4NSltrYa9k2ypoLKpl+ho3qUehbCkQ9hyh5g6jhreo0Z32wRnOzu7T
# Ob5DoNRJAx16ZXQ47R88YLMzsSDxQRmRCf8ZB+kjC0AfQ4tNefP1OqTzJcW3Sc47
# 3oCk+zlNLj5xDvest3rk7WKFmyEgaJwJfFnl0u20D6aYQeKj6p1SovZR5Cid/OJh
# 8awHP92LEVcC3GNSsvCmcyDMF+J1KyUelkYjPoXvbvuhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDI4WjAvBgkqhkiG9w0BCQQxIgQgZg+5zPSIkROEYINKYGN/
# z5IpelSwDhaJSa8ofI0TkDYwDQYJKoZIhvcNAQEBBQAEggIAcyNOPe53aXeX0PHM
# qUnQGJFCmDV2loK1IhVHnF3BaagYLUznZU5qEZAXmk3KhKS8o1EOyBy2M6aaLAh6
# +KkCt9H0/hEPBza57R0YiqGjNsHeAVQ4HQciI4TrOcW9xlWSO7fes5rwpYDQAWn4
# QUnjAXRuZUtCcpXJEGYQoYTRu+SKDGUvcO3qhCTkqgTS9aG2VGCkBjI/LBUoCGuh
# T2t9wM56DjHJl9+X03h/PTg3SJoCD+hM4P0UmL8AcquUrQ6xft2zMopf3HqQ+8gS
# mR9qVTT1V5F4fVvRDIV89L0QKKGfQn725XWAZ01wc/vd9ezPjZQqdVlTK1/oaUHU
# aLe7rxloqyNs2r/MuGjm/0T608SwMKpkgWbyMiBxJDBJe4b04vLKhHBUWS+3WCVL
# nI5avonoePr1+wkz96Yq5tis2Gq4gKwAW+61hdWNS+QAVsWJyYOYiLEzrUmAUlr6
# AwLLOPh/eOkrEcJRLUa8Jf0FtZuc69Ti9KJS6Qa+bBxchaed98D4UNkZgJMczQCR
# 9HkXNaPs0a8tckDZ9XNGQOwoBPDXDw8gF3p5yK+aFkpcYw9VkgisfRBCJcmVlLfR
# Uf51ERKRQEkTqyxX/m/P7rhBWS3Y7cU1HZgOcPxVbaKS5u+9CVEUgScqq0m1S7Km
# DKLtKfm/oL8oyc7l3UhH1mA1Faw=
# SIG # End signature block
