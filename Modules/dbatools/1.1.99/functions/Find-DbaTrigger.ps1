function Find-DbaTrigger {
    <#
    .SYNOPSIS
        Returns all triggers that contain a specific case-insensitive string or regex pattern.

    .DESCRIPTION
        This function search on Instance, Database and Object level.
        If you specify one or more databases, search on Server level will not be preformed.

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

    .PARAMETER Pattern
        String pattern that you want to search for in the trigger text body

    .PARAMETER TriggerLevel
        Allows specify the trigger level that you want to search. By default is All (Server, Database, Object).

    .PARAMETER IncludeSystemObjects
        By default, system triggers are ignored but you can include them within the search using this parameter.

        Warning - this will likely make it super slow if you run it on all databases.

    .PARAMETER IncludeSystemDatabases
        By default system databases are ignored but you can include them within the search using this parameter

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Trigger, Lookup
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaTrigger

    .EXAMPLE
        PS C:\> Find-DbaTrigger -SqlInstance DEV01 -Pattern whatever

        Searches all user databases triggers for "whatever" in the text body

    .EXAMPLE
        PS C:\> Find-DbaTrigger -SqlInstance sql2016 -Pattern '\w+@\w+\.\w+'

        Searches all databases for all triggers that contain a valid email pattern in the text body

    .EXAMPLE
        PS C:\> Find-DbaTrigger -SqlInstance DEV01 -Database MyDB -Pattern 'some string' -Verbose

        Searches in "mydb" database triggers for "some string" in the text body

    .EXAMPLE
        PS C:\> Find-DbaTrigger -SqlInstance sql2016 -Database MyDB -Pattern RUNTIME -IncludeSystemObjects

        Searches in "mydb" database triggers for "runtime" in the text body

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(Mandatory)]
        [string]$Pattern,
        [ValidateSet('All', 'Server', 'Database', 'Object')]
        [string]$TriggerLevel = 'All',
        [switch]$IncludeSystemObjects,
        [switch]$IncludeSystemDatabases,
        [switch]$EnableException
    )

    begin {
        $sqlDatabaseTriggers = "SELECT tr.name, m.definition as TextBody FROM sys.sql_modules m, sys.triggers tr WHERE m.object_id = tr.object_id AND tr.parent_class = 0"

        $sqlTableTriggers = "SELECT OBJECT_SCHEMA_NAME(tr.parent_id) TableSchema, OBJECT_NAME(tr.parent_id) AS TableName, tr.name, m.definition as TextBody FROM sys.sql_modules m, sys.triggers tr WHERE m.object_id = tr.object_id AND tr.parent_class = 1"
        if (!$IncludeSystemObjects) { $sqlTableTriggers = "$sqlTableTriggers AND tr.is_ms_shipped = 0" }

        $everyserverstcount = 0

        $eol = [System.Environment]::NewLine
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.versionMajor -lt 9) {
                Write-Message -Level Warning -Message "This command only supports SQL Server 2005 and above."
                Continue
            }

            #search at instance level. Only if no database was specified
            if ((-Not $Database) -and ($TriggerLevel -in @('All', 'Server'))) {
                foreach ($trigger in $server.Triggers) {
                    $everyserverstcount++; $triggercount++
                    Write-Message -Level Debug -Message "Looking in Trigger: $trigger TextBody for $pattern"
                    if ($trigger.TextBody -match $Pattern) {

                        $triggerText = $trigger.TextBody.split($eol)
                        $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                        [PSCustomObject]@{
                            ComputerName     = $server.ComputerName
                            SqlInstance      = $server.ServiceName
                            TriggerLevel     = "Server"
                            Database         = $null
                            Object           = $null
                            Name             = $trigger.Name
                            IsSystemObject   = $trigger.IsSystemObject
                            CreateDate       = $trigger.CreateDate
                            LastModified     = $trigger.DateLastModified
                            TriggerTextFound = $trTextFound -join "`n"
                            Trigger          = $trigger
                            TriggerFullText  = $trigger.TextBody
                        } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                    }
                }
                Write-Message -Level Verbose -Message "Evaluated $triggercount triggers in $server"
            }

            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" }
            } else {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            $totalcount = 0
            $dbcount = $dbs.count

            if ($TriggerLevel -in @('All', 'Database', 'Object')) {
                foreach ($db in $dbs) {

                    Write-Message -Level Verbose -Message "Searching on database $db"

                    # If system objects aren't needed, find trigger text using SQL
                    # This prevents SMO from having to enumerate

                    if (!$IncludeSystemObjects) {
                        if ($TriggerLevel -in @('All', 'Database')) {
                            #Get Database Level triggers (DDL)
                            Write-Message -Level Debug -Message $sqlDatabaseTriggers
                            $rows = $db.ExecuteWithResults($sqlDatabaseTriggers).Tables.Rows
                            $triggercount = 0

                            foreach ($row in $rows) {
                                $totalcount++; $triggercount++; $everyserverstcount++

                                $trigger = $row.name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern on database $db"
                                if ($row.TextBody -match $Pattern) {
                                    $tr = $db.Triggers | Where-Object name -eq $row.name

                                    $triggerText = $tr.TextBody.split($eol)
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Database"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }

                        if ($TriggerLevel -in @('All', 'Object')) {
                            #Get Object Level triggers (DML)
                            Write-Message -Level Debug -Message $sqlTableTriggers
                            $rows = $db.ExecuteWithResults($sqlTableTriggers).Tables.Rows
                            $triggercount = 0

                            foreach ($row in $rows) {
                                $totalcount++; $triggercount++; $everyserverstcount++

                                $trigger = $row.name
                                $triggerParentSchema = $row.TableSchema
                                $triggerParent = $row.TableName

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern in object $triggerParentSchema.$triggerParent at database $db"
                                if ($row.TextBody -match $Pattern) {

                                    $tr = ($db.Tables | Where-Object { $_.Name -eq $triggerParent -and $_.Schema -eq $triggerParentSchema }).Triggers | Where-Object name -eq $row.name
                                    if ($null -eq $tr) {
                                        Write-Message -Level Verbose -Message "Could not find table named $($row.Name). Will try to find on Views."
                                        $tr = ($db.Views | Where-Object { $_.Name -eq $triggerParent -and $_.Schema -eq $triggerParentSchema }).Triggers | Where-Object name -eq $row.name
                                    }

                                    $triggerText = $tr.TextBody.split($eol)
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Object"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }
                    } else {
                        if ($TriggerLevel -in @('All', 'Database')) {
                            #Get Database Level triggers (DDL)
                            $triggers = $db.Triggers

                            $triggercount = 0

                            foreach ($tr in $triggers) {
                                $totalcount++; $triggercount++; $everyserverstcount++
                                $trigger = $tr.Name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern on database $db"
                                if ($tr.TextBody -match $Pattern) {

                                    $triggerText = $tr.TextBody.split($eol)
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Database"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }

                        if ($TriggerLevel -in @('All', 'Object')) {
                            #Get Object Level triggers (DML)
                            $triggers = $db.Tables | ForEach-Object { $_.Triggers }
                            $triggers += $db.Views | ForEach-Object { $_.Triggers }

                            $triggercount = 0

                            foreach ($tr in $triggers) {
                                $totalcount++; $triggercount++; $everyserverstcount++
                                $trigger = $tr.Name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern in object $($tr.Parent) at database $db"
                                if ($tr.TextBody -match $Pattern) {

                                    $triggerText = $tr.TextBody.split($eol)
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Object"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }
                    }
                    Write-Message -Level Verbose -Message "Evaluated $triggercount triggers in $db"
                }
            }
            Write-Message -Level Verbose -Message "Evaluated $totalcount total triggers in $dbcount databases"
        }
    }
    end {
        Write-Message -Level Verbose -Message "Evaluated $everyserverstcount total triggers"
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUU9ha+2TUlQ5Db+bWeS8YKem1
# Vi+gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPlxJu4dl4/T0zDNLAFT6kQ7AvpiMA0G
# CSqGSIb3DQEBAQUABIIBALZ8CoMgb1b20QuKmbTXevIU5m8Qne/MLzPEYDEHfxBE
# jTndFYgkijNFxavNBn3uQwFfRKTsCFJex9V1HMfPaywyFQt89eysrUdG6g2dC1DO
# KMAXpO/Pim5QfQ6GR6L3Ec49kNg10pwYlVskOm0LviA4L9hKoRLxfXgFHvyy4eEL
# sGtb7BbD6oynRLW9sepseqPulftU3v+/BY5iYMRgSMM+/Lk80PiSOEfDPT2cUwIU
# EuIWcxhL9uvJWAtjtuHhI3hjT0SLAhPD7Rfe96FWGxk545flcMQsioJmcj9uUQ01
# XfCO154gKREkUYJAZOM5xCiGAcFZ6I7ATowu+1HbbaShggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzIxWjAvBgkqhkiG9w0BCQQxIgQgZa2/BFJcx+GrIy6usDiD
# LrJEv28ekHb3a51jjR//yvIwDQYJKoZIhvcNAQEBBQAEggIAfS1HKyB0AiWgAcBr
# cD+1kmFeeknLy++QPo3vV9ynvb+cwNg2JJDn6Xpfz+VzcC0Bn3he+k7HPySH2J3I
# nuk9+3CBjZRRpFEo058s8gIi3bxGXC/VhC9i7giNFnFu2anvXOxfBH2SKMn8jntx
# VSwZKjkbc0IW3c8OVxHK10pJLHD52SJylbw8/KJhQUlZzdlrjgHTDCVBVfrXV1S4
# X1/yVTXO+xfgoYvUS9TiCD3gH7093zGparJwv7Cppw4k+pN+T9KsBqKtSKemKxnc
# bnKqfpHVJ7aBjrklAgJfxk4ixlV62r5/SEccWcWBsQpMMIphSQtubWbI3ZnwCKLN
# qD52FSpT3fXQTop0oKDttKBQv0WMwZjAFcFbA0h+QpkidT0ehMUviceIuVijjdm6
# p6ZC4KgBsoVK9ieDyCNTEgY3GnpIUWUr0vY7DKt2xjbZS2l3cwnvVKCRqfoEpP2B
# jMCxZLAOm9zdmJZSXCTbDFFtRueLr9q8WTRuuGUgCJLf5LJfGPo9b6UIEbYepogC
# n1QYePnXwcqQwAzAlOjXTxbKn6g/rcOj4Mf+ndRBpsdHG8AkZ+uYUDev0d86gNBh
# qm7iNBfjiTjZ7+umJwDsAvA6YJO6dtFEAPlbHzYsHDelyak0JyzeS9BaL6/e9A0I
# zV1dnnRMGeYy5xO46kDRZ1OqLug=
# SIG # End signature block
