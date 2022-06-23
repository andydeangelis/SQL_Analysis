function Invoke-DbaDbUpgrade {
    <#
    .SYNOPSIS
        Take a database and upgrades it to compatibility of the SQL Instance its hosted on and updates the target recovery time to the new default of 60 seconds. Based on https://thomaslarock.com/2014/06/upgrading-to-sql-server-2014-a-dozen-things-to-check/

    .DESCRIPTION
        Updates compatibility level and target recovery time, then runs CHECKDB with data_purity, DBCC updateusage, sp_updatestats and finally sp_refreshview against all user views.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database(s) to process - this list is autopopulated from the server. If unspecified, you have to use -ExcludeDatabase to exclude some user databases or -AllUserDatabases to process all user databases.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is autopopulated from the server

    .PARAMETER AllUserDatabases
        Run command against all user databases

    .PARAMETER Force
        Don't skip over databases that are already at the same level the instance is

    .PARAMETER NoCheckDb
        Skip checkdb

    .PARAMETER NoUpdateUsage
        Skip usage update

    .PARAMETER NoUpdateStats
        Skip stats update

    .PARAMETER NoRefreshView
        Skip view update

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase)

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Update database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Shrink, Database
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbUpgrade

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-MSD01 -Database Test

        Runs the below processes against the databases
        -- Puts compatibility of database to level of SQL Instance
        -- Changes the target recovery time to the new default of 60 seconds (for SQL Server 2016 and newer)
        -- Runs CHECKDB DATA_PURITY
        -- Runs DBCC UPDATESUSAGE
        -- Updates all users statistics
        -- Runs sp_refreshview against every view in the database

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-INT01 -Database Test -NoRefreshView

        Runs the upgrade command skipping the sp_refreshview update on all views

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-INT01 -Database Test -Force

        If database Test is already at the correct compatibility, runs every necessary step

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 | Out-GridView -Passthru | Invoke-DbaDbUpgrade

        Get only specific databases using GridView and pass those to Invoke-DbaDbUpgrade

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$NoCheckDb,
        [switch]$NoUpdateUsage,
        [switch]$NoUpdateStats,
        [switch]$NoRefreshView,
        [switch]$AllUserDatabases,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        if (Test-Bound -not 'SqlInstance', 'InputObject') {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or pipe a database collection"
            continue
        }

        if (Test-Bound -not 'Database', 'InputObject', 'ExcludeDatabase', 'AllUserDatabases') {
            Write-Message -Level Warning -Message "You must explicitly specify a database. Use -Database, -ExcludeDatabase, -AllUserDatabases or pipe a database collection"
            continue
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -StatementTimeout 0
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $InputObject += $server.Databases | Where-Object IsAccessible
        }

        $InputObject = $InputObject | Where-Object { $_.IsSystemObject -eq $false }
        if ($Database) {
            $InputObject = $InputObject | Where-Object Name -In $Database
        }
        if ($ExcludeDatabase) {
            $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            # create objects to use in updates
            $server = $db.Parent
            $serverVersion = $server.VersionMajor
            Write-Message -Level Verbose -Message "SQL Server is using Version: $serverVersion"

            $dbLevel = $db.CompatibilityLevel
            $serverLevel = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($serverVersion)0"
            $levelOk = $dbLevel -eq $serverLevel
            $timeOk = if ($serverVersion -ge 13 -and $db.TargetRecoveryTime -ne 60) { $false } else { $true }

            if (-not $Force) {
                # skip over databases at the correct level and correct target recovery time, unless -Force
                if ($levelOk -and $timeOk) {
                    Write-Message -Level VeryVerbose -Message "Skipping $db because compatibility is at the correct level and target recovery time is correct. Use -Force if you want to run all the additional steps."
                    continue
                }
            }

            Write-Message -Level Verbose -Message "Updating $db compatibility to SQL Instance level"
            if (-not $levelOk) {
                If ($Pscmdlet.ShouldProcess($server, "Updating $db compatibility on $server from $dbLevel to $serverLevel")) {
                    try {
                        $db.CompatibilityLevel = $serverLevel
                        $db.Alter()
                        $CompatibilityResult = $serverLevel.ToString().Replace('Version', '')
                    } catch {
                        Write-Message -Level Warning -Message "Failed run Compatibility Upgrade" -ErrorRecord $_ -Target $instance
                        $CompatibilityResult = "Fail"
                    }
                }
            } else {
                $CompatibilityResult = "No change"
            }

            Write-Message -Level Verbose -Message "Updating $db target recovery time to 60 seconds on SQL Server 2016 or newer"
            if (-not $timeOk) {
                If ($Pscmdlet.ShouldProcess($server, "Updating $db target recovery time on $server from $($db.TargetRecoveryTime) seconds to 60 seconds")) {
                    try {
                        $db.TargetRecoveryTime = 60
                        $db.Alter()
                        $targetRecoveryTimeResult = 60
                    } catch {
                        Write-Message -Level Warning -Message "Failed to change target recovery time" -ErrorRecord $_ -Target $instance
                        $targetRecoveryTimeResult = "Fail"
                    }
                }
            } else {
                $targetRecoveryTimeResult = "No change"
            }

            if (!($NoCheckDb)) {
                Write-Message -Level Verbose -Message "Updating $db with DBCC CHECKDB DATA_PURITY"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db with DBCC CHECKDB DATA_PURITY")) {
                    $tsqlCheckDB = "DBCC CHECKDB ('$($db.Name)') WITH DATA_PURITY, NO_INFOMSGS"
                    try {
                        $db.ExecuteNonQuery($tsqlCheckDB)
                        $DataPurityResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed run DBCC CHECKDB with DATA_PURITY on $db" -ErrorRecord $_ -Target $instance
                        $DataPurityResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignoring CHECKDB DATA_PURITY"
            }

            if (!($NoUpdateUsage)) {
                Write-Message -Level Verbose -Message "Updating $db with DBCC UPDATEUSAGE"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db with DBCC UPDATEUSAGE")) {
                    $tsqlUpdateUsage = "DBCC UPDATEUSAGE ($db) WITH NO_INFOMSGS;"
                    try {
                        $db.ExecuteNonQuery($tsqlUpdateUsage)
                        $UpdateUsageResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed to run DBCC UPDATEUSAGE on $db" -ErrorRecord $_ -Target $instance
                        $UpdateUsageResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignore DBCC UPDATEUSAGE"
                $UpdateUsageResult = "Skipped"
            }

            if (!($NoUpdatestats)) {
                Write-Message -Level Verbose -Message "Updating $db statistics"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db statistics")) {
                    $tsqlStats = "EXEC sp_updatestats;"
                    try {
                        $db.ExecuteNonQuery($tsqlStats)
                        $UpdateStatsResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed to run sp_updatestats on $db" -ErrorRecord $_ -Target $instance
                        $UpdateStatsResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignoring sp_updatestats"
                $UpdateStatsResult = "Skipped"
            }

            if (!($NoRefreshView)) {
                Write-Message -Level Verbose -Message "Refreshing $db Views"
                $dbViews = $db.Views | Where-Object IsSystemObject -eq $false
                $RefreshViewResult = "Success"
                foreach ($dbview in $dbviews) {
                    $viewName = $dbView.Name
                    $viewSchema = $dbView.Schema
                    $fullName = $viewSchema + "." + $viewName

                    $tsqlupdateView = "EXECUTE sp_refreshview N'$fullName';  "

                    If ($Pscmdlet.ShouldProcess($server, "Refreshing view $fullName on $db")) {
                        try {
                            $db.ExecuteNonQuery($tsqlupdateView)
                        } catch {
                            Write-Message -Level Warning -Message "Failed update view $fullName on $db" -ErrorRecord $_ -Target $instance
                            $RefreshViewResult = "Fail"
                        }
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignore View Refreshes"
                $RefreshViewResult = "Skipped"
            }

            If ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                $db.Refresh()

                [PSCustomObject]@{
                    ComputerName          = $server.ComputerName
                    InstanceName          = $server.ServiceName
                    SqlInstance           = $server.DomainInstanceName
                    Database              = $db.name
                    OriginalCompatibility = $dbLevel.ToString().Replace('Version', '')
                    CurrentCompatibility  = $db.CompatibilityLevel.ToString().Replace('Version', '')
                    Compatibility         = $CompatibilityResult
                    TargetRecoveryTime    = $targetRecoveryTimeResult
                    DataPurity            = $DataPurityResult
                    UpdateUsage           = $UpdateUsageResult
                    UpdateStats           = $UpdateStatsResult
                    RefreshViews          = $RefreshViewResult
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU/enN+z0Zj8mrl+cCeXYZbLoA
# ckagghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFD8cKA55V2WEkTBWUezC6Xw8hOivMA0G
# CSqGSIb3DQEBAQUABIIBADi1E8jzBsx51oopdyqOpRfX/C/Sb5LQ5kKRwcULello
# h8z3jzLdjHa4lHw+CjJpVtatG8U6GDS+yOKHFy5m8ali5ZgsEvIxAk3MKWbJkY33
# 5L2llUhilUlxo0LZImMOxMR8CX/zQTpA1twfrOwYgFtWNIs2SYSAcyZ8yFbZnLxe
# tqPWvGu0j8TSQVz9StYutClDBdb6V7J9d0YgaRWbXAG9t2bbFHNxEB3cuYNGfSqB
# oFE/N2vOSPvXQkGbbkRLLr/bQ9U/tfAu9wOlvesLI7h6Q1GaAgKo+WN4aPaeUakT
# Z1sWNLyRpwWjBj3XaJ34+ylQwdy4VTnv/s08rZQ4QeyhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU2WjAvBgkqhkiG9w0BCQQxIgQgByCrLsG+t4L69J+kTNth
# qzMTD51auL9bH3pwiDqLuBEwDQYJKoZIhvcNAQEBBQAEggIAd5fossvWkIkWe5OF
# DBqtSEiav9wgQgSggrpOS60xYMoy1iPVEgfVJbJM3qE/6RoAb1DFJE1UDFObjrZ9
# qFKDy+BqObZh5nAeD6WqjHH8iZiq54r5/XtZW/8YOI7EmZlYn8askgQ7wq6/d3nO
# 3SZrSasFt28KmtIwfctuZB3JIsoeQe5GntezDM4uJI0K0pb1YOBVceHadXVoUUMa
# ZKtSD0tG+O+kgTQzlSUW0uwL3TJ+tCFTdR6wpQFiy29b1ItOYsUCRdoR9R6vNwh/
# ovLWAqP8/CK39J4ahyfyVJssPkJ1C4/3YDCpLBoZyZBwBk7zkkRIFgnZcoZuwTub
# vP3z3CFtKKYP4ciaqsVQEpNKwlXoGMnJyeePfcTQ6tUaQYOfSujBVuF27o5egMl7
# PsHvyv+EIDWt8Jjn3wMaqw7NrELRQtEQJuP0Ox4ZeX1vkMM05gfgBF60aIdK44tH
# xDe6BhbS5OhPLIKXg4R3aRuEeYk7oGv9454IJjkOj54VdASEmnGiItoo0QmsQWFU
# K+dEwgWA+QExGP5moZHgcfb3FVSGd4BXEwjaNtabX3+MeugOaSlhmbjCWsIIQFVR
# a75tcfuYeG21cSS+8aUhd8AmY+/Wk+iu1k4lG705ZAsaaANdhxFpwDH5PWEUgfPz
# 5NSZZt0Exv17JkdH7i5BRLzxtg8=
# SIG # End signature block
