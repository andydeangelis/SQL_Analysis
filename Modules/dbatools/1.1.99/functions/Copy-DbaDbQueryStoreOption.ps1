function Copy-DbaDbQueryStoreOption {
    <#
    .SYNOPSIS
        Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.

    .DESCRIPTION
        Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2016 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SourceDatabase
        Specifies the database to copy the Query Store configuration from.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2016 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationDatabase
        Specifies a list of databases that will receive a copy of the Query Store configuration of the SourceDatabase.

    .PARAMETER Exclude
        Specifies a list of databases which will NOT receive a copy of the Query Store configuration.

    .PARAMETER AllDatabases
        If this switch is enabled, the Query Store configuration will be copied to all databases on the destination instance.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: QueryStore
        Author: Enrico van de Laar (@evdlaar) | Tracy Boggiano ( @Tracy Boggiano)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaDbQueryStoreOption

    .EXAMPLE
        PS C:\> Copy-DbaDbQueryStoreOption -Source ServerA\SQL -SourceDatabase AdventureWorks -Destination ServerB\SQL -AllDatabases

        Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL instance and apply it on all user databases in the ServerB\SQL Instance.

    .EXAMPLE
        PS C:\> Copy-DbaDbQueryStoreOption -Source ServerA\SQL -SourceDatabase AdventureWorks -Destination ServerB\SQL -DestinationDatabase WorldWideTraders

        Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL instance and apply it to the WorldWideTraders database in the ServerB\SQL Instance.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory, ValueFromPipeline)]
        [object]$SourceDatabase,
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$DestinationDatabase,
        [object[]]$Exclude,
        [switch]$AllDatabases,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            # Grab the Query Store configuration from the SourceDatabase through the Get-DbaQueryStoreConfig function
            $SourceQSConfig = Get-DbaDbQueryStoreOption -SqlInstance $sourceServer -Database $SourceDatabase

            $db = Get-DbaDatabase -SqlInstance $sourceServer -Database $SourceDatabase

            if ($sourceServer.VersionMajor -eq 14) {
                $QueryStoreOptions = $db.Query("SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode FROM sys.database_query_store_options;", $db.Name)
            } elseif ($sourceServer.VersionMajor -ge 15) {
                $QueryStoreOptions = $db.Query("SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode, capture_policy_execution_count AS CustomCapturePolicyExecutionCount, capture_policy_stale_threshold_hours AS CustomCapturePolicyStaleThresholdHours, capture_policy_total_compile_cpu_time_ms AS CustomCapturePolicyTotalCompileCPUTimeMS, capture_policy_total_execution_cpu_time_ms AS CustomCapturePolicyTotalExecutionCPUTimeMS FROM sys.database_query_store_options;", $db.Name)
            }

            if (!$DestinationDatabase -and !$Exclude -and !$AllDatabases) {
                Stop-Function -Message "You must specify databases to execute against using either -DestinationDatabase, -Exclude or -AllDatabases." -Continue
            }

            foreach ($destinationServer in $destinstance) {

                try {
                    $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
                }

                # We have to exclude all the system databases since they cannot have the Query Store feature enabled
                $dbs = Get-DbaDatabase -SqlInstance $destServer -ExcludeSystem

                if ($DestinationDatabase.count -gt 0) {
                    $dbs = $dbs | Where-Object { $DestinationDatabase -contains $_.Name }
                }

                if ($Exclude.count -gt 0) {
                    $dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
                }

                if ($dbs.count -eq 0) {
                    Stop-Function -Message "No matching databases found. Check the spelling and try again." -Continue
                }

                foreach ($db in $dbs) {
                    # skipping the database if the source and destination are the same instance
                    if (($sourceServer.Name -eq $destinationServer) -and ($SourceDatabase -eq $db.Name)) {
                        continue
                    }
                    Write-Message -Message "Processing destination database: $db on $destinationServer." -Level Verbose
                    $copyQueryStoreStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.name
                        SourceDatabase    = $SourceDatabase
                        DestinationServer = $destinationServer
                        Name              = $db.name
                        Type              = "QueryStore Configuration"
                        Status            = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }

                    if ($db.IsAccessible -eq $false) {
                        $copyQueryStoreStatus.Status = "Skipped"
                        Stop-Function -Message "The database $db on server $destinationServer is not accessible. Skipping database." -Continue
                    }

                    Write-Message -Message "Executing Set-DbaQueryStoreConfig." -Level Verbose
                    # Set the Query Store configuration through the Set-DbaQueryStoreConfig function
                    if ($PSCmdlet.ShouldProcess("$db", "Copying QueryStoreConfig")) {
                        try {
                            if ($sourceServer.VersionMajor -eq 13) {
                                $setDbaDbQueryStoreOptionParameters = @{
                                    SqlInstance         = $destinationServer
                                    SqlCredential       = $DestinationSqlCredential
                                    Database            = $db.name
                                    State               = $SourceQSConfig.ActualState
                                    FlushInterval       = $SourceQSConfig.DataFlushIntervalInSeconds
                                    CollectionInterval  = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                                    MaxSize             = $SourceQSConfig.MaxStorageSizeInMB
                                    CaptureMode         = $SourceQSConfig.QueryCaptureMode
                                    CleanupMode         = $SourceQSConfig.SizeBasedCleanupMode
                                    StaleQueryThreshold = $SourceQSConfig.StaleQueryThresholdInDays
                                }
                            } elseif ($sourceServer.VersionMajor -eq 14) {
                                $setDbaDbQueryStoreOptionParameters = @{
                                    SqlInstance          = $destinationServer
                                    SqlCredential        = $DestinationSqlCredential
                                    Database             = $db.name
                                    State                = $SourceQSConfig.ActualState
                                    FlushInterval        = $SourceQSConfig.DataFlushIntervalInSeconds
                                    CollectionInterval   = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                                    MaxSize              = $SourceQSConfig.MaxStorageSizeInMB
                                    CaptureMode          = $SourceQSConfig.QueryCaptureMode
                                    CleanupMode          = $SourceQSConfig.SizeBasedCleanupMode
                                    StaleQueryThreshold  = $SourceQSConfig.StaleQueryThresholdInDays
                                    MaxPlansPerQuery     = $QueryStoreOptions.MaxPlansPerQuery
                                    WaitStatsCaptureMode = $QueryStoreOptions.WaitStatsCaptureMode
                                }
                            } elseif ($sourceServer.VersionMajor -ge 15) {
                                $setDbaDbQueryStoreOptionParameters = @{
                                    SqlInstance                                = $destinationServer
                                    SqlCredential                              = $DestinationSqlCredential
                                    Database                                   = $db.name
                                    State                                      = $SourceQSConfig.ActualState
                                    FlushInterval                              = $SourceQSConfig.DataFlushIntervalInSeconds
                                    CollectionInterval                         = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                                    MaxSize                                    = $SourceQSConfig.MaxStorageSizeInMB
                                    CaptureMode                                = $SourceQSConfig.QueryCaptureMode
                                    CleanupMode                                = $SourceQSConfig.SizeBasedCleanupMode
                                    StaleQueryThreshold                        = $SourceQSConfig.StaleQueryThresholdInDays
                                    MaxPlansPerQuery                           = $QueryStoreOptions.MaxPlansPerQuery
                                    WaitStatsCaptureMode                       = $QueryStoreOptions.WaitStatsCaptureMode
                                    CustomCapturePolicyExecutionCount          = $QueryStoreOptions.CustomCapturePolicyExecutionCount
                                    CustomCapturePolicyTotalCompileCPUTimeMS   = $QueryStoreOptions.CustomCapturePolicyTotalCompileCPUTimeMS
                                    CustomCapturePolicyTotalExecutionCPUTimeMS = $QueryStoreOptions.CustomCapturePolicyTotalExecutionCPUTimeMS
                                    CustomCapturePolicyStaleThresholdHours     = $QueryStoreOptions.CustomCapturePolicyStaleThresholdHours
                                }
                            }

                            $null = Set-DbaDbQueryStoreOption @setDbaDbQueryStoreOptionParameters
                            $copyQueryStoreStatus.Status = "Successful"
                        } catch {
                            $copyQueryStoreStatus.Status = "Failed"
                            Stop-Function -Message "Issue setting Query Store on $db." -Target $db -ErrorRecord $_ -Continue
                        }
                        $copyQueryStoreStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUDaYQSXf5l+JAgBwHwo9xwVXz
# K5ugghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPhAFOfwYEjfpGP/9G4/0UbNIYvuMA0G
# CSqGSIb3DQEBAQUABIIBAGuQmVGQYg/FRZ01GKwvgsO+uGYvRe+gigemy1dn1vnK
# Via9zsNQulHThBMXX6vVw1GUJ9vzarP8ym6w96zXaVwtdjNLdh480PCPw6ARFyP4
# VxNPwTdej8CabSniZaVS8lzbGmw16Vu1qPQ8hDP5k04qDN2nC285ijpO5Ov9VXQk
# 75k8YhgVAlnt9KrN9GuOnvIGT42M6vD9jeUoXNQm2I5yAgAVyYSBAsKCvCMEt7nQ
# QlKQ0EjKSwLpQ7ARA+UX9S1lMZgVmO+dNTLTU994xEVXgLC+UOytg747cZ2ostxJ
# NVbAOs4qKl0eBMBxHVAaOZjpqVSOsIGjveIpN1cSazihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzEzWjAvBgkqhkiG9w0BCQQxIgQg3UMqHiVsRLyJeebNsoM4
# nKVEajUddW+SpPdWgwSfgvowDQYJKoZIhvcNAQEBBQAEggIArrKvG9SrR13tjHDn
# 4ul8LuQrkEAgetzjsJ2w2K+nTttJwznYmOTxvhWBwEDPvI6gTreXU1s2S8tyRECo
# zshitHT0MP0ospA4EWK96nKQOiNV7RF1z9dWq7TtPAbnp0Urmg0+bt8cxyQR8ZoD
# x+iZiFuzfipmtMEAMdMTyoU7wcX24c+UvyV73Bu5BkxmvDZNdhwQ+g38sdVj4Qx4
# uioLWQq7gJPfrW2z9O12w0pJRtdQswvHmciy7tgP8duCIHpr4eRvuNVrkPYZsCaw
# kSBj+fJCwDTCeeBVqvdmzvDnOnxU20E2MQslmeUZmfUh3yidjn8X05UP99NalnRw
# wNaOXRlWzXKup2e+WfLlS57XJERjT2d1ZZddAJs4S1FR7wCZgpc7dHtnKn+33Xvg
# HR/aU1tXx88B2BKqCDYpeWvV8lFV64lMWnfP199o4fFgKta0CJ4u4YPAyKg2MIuT
# xM6+6HqLeMtWhUNLJb7/KGy0sAsAVOg+cb+Zu57+6FYE7eS3XhrQuhC9q/ZoC6Lw
# xby4JS2Ktkrh0mcbtxDAEgftPRzM2eyUVawn/74lGL1baw/oJ3u8P3eVSIclReCN
# JzPsvzs5elbeXIPKQSt7+F9AbUAgfMtyOpy8ZHaI0D52bHJYIOSwsZutqdDYhf5x
# B+ProoR0uToS02KhwZ4HA+bxQVI=
# SIG # End signature block
