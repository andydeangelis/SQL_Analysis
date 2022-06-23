function Set-DbaDbQueryStoreOption {
    <#
    .SYNOPSIS
        Configure Query Store settings for a specific or multiple databases.

    .DESCRIPTION
        Configure Query Store settings for a specific or multiple databases.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AllDatabases
        Run command against all user databases

    .PARAMETER State
        Set the state of the Query Store. Valid options are "ReadWrite", "ReadOnly" and "Off".

    .PARAMETER FlushInterval
        Set the flush to disk interval of the Query Store in seconds.

    .PARAMETER CollectionInterval
        Set the runtime statistics collection interval of the Query Store in minutes.

    .PARAMETER MaxSize
        Set the maximum size of the Query Store in MB.

    .PARAMETER CaptureMode
        Set the query capture mode of the Query Store. Valid options are "Auto" and "All".

    .PARAMETER CleanupMode
        Set the query cleanup mode policy. Valid options are "Auto" and "Off".

    .PARAMETER StaleQueryThreshold
        Set the stale query threshold in days.

    .PARAMETER MaxPlansPerQuery
        Set the max plans per query captured and kept.

    .PARAMETER WaitStatsCaptureMode
        Set wait stats capture on or off.

    .PARAMETER CustomCapturePolicyExecutionCount
        Set the custom capture policy execution count. Only available in SQL Server 2019 and above.

    .PARAMETER CustomCapturePolicyTotalCompileCPUTimeMS
        Set the custom capture policy total compile CPU time. Only available in SQL Server 2019 and above.

    .PARAMETER CustomCapturePolicyTotalExecutionCPUTimeMS
        Set the custom capture policy total execution CPU time. Only available in SQL Server 2019 and above.

    .PARAMETER CustomCapturePolicyStaleThresholdHours
        Set the custom capture policy stale threshold. Only available in SQL Server 2019 and above.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Changing Desired State" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: QueryStore
        Author: Enrico van de Laar (@evdlaar) | Tracy Boggiano ( @TracyBoggiano )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbQueryStoreOption

    .EXAMPLE
        PS C:\> Set-DbaDbQueryStoreOption -SqlInstance ServerA\SQL -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode All -CleanupMode Auto -StaleQueryThreshold 100 -AllDatabases

        Configure the Query Store settings for all user databases in the ServerA\SQL Instance.

    .EXAMPLE
        PS C:\> Set-DbaDbQueryStoreOption -SqlInstance ServerA\SQL -FlushInterval 600

        Only configure the FlushInterval setting for all Query Store databases in the ServerA\SQL Instance.

    .EXAMPLE
        PS C:\> Set-DbaDbQueryStoreOption -SqlInstance ServerA\SQL -Database AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

        Configure the Query Store settings for the AdventureWorks database in the ServerA\SQL Instance.

    .EXAMPLE
        PS C:\> Set-DbaDbQueryStoreOption -SqlInstance ServerA\SQL -Exclude AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

        Configure the Query Store settings for all user databases except the AdventureWorks database in the ServerA\SQL Instance.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [ValidateSet('ReadWrite', 'ReadOnly', 'Off')]
        [string[]]$State,
        [int64]$FlushInterval,
        [int64]$CollectionInterval,
        [int64]$MaxSize,
        [ValidateSet('Auto', 'All', 'None', 'Custom')]
        [string[]]$CaptureMode,
        [ValidateSet('Auto', 'Off')]
        [string[]]$CleanupMode,
        [int64]$StaleQueryThreshold,
        [int64]$MaxPlansPerQuery,
        [ValidateSet('On', 'Off')]
        [string[]]$WaitStatsCaptureMode,
        [int64]$CustomCapturePolicyExecutionCount,
        [int64]$CustomCapturePolicyTotalCompileCPUTimeMS,
        [int64]$CustomCapturePolicyTotalExecutionCPUTimeMS,
        [int64]$CustomCapturePolicyStaleThresholdHours,
        [switch]$EnableException
    )
    begin {
        $ExcludeDatabase += 'master', 'tempdb', "model"
    }

    process {
        if (-not $Database -and -not $ExcludeDatabase -and -not $AllDatabases) {
            Stop-Function -Message "You must specify a database(s) to execute against using either -Database, -ExcludeDatabase or -AllDatabases"
            return
        }

        if (-not $State -and -not $FlushInterval -and -not $CollectionInterval -and -not $MaxSize -and -not $CaptureMode -and -not $CleanupMode -and -not $StaleQueryThreshold -and -not $MaxPlansPerQuery -and -not $WaitStatsCaptureMode -and -not $CustomCapturePolicyExecutionCount -and -not $CustomCapturePolicyTotalCompileCPUTimeMS -and -not $CustomCapturePolicyTotalExecutionCPUTimeMS -and -not $CustomCapturePolicyStaleThresholdHours) {
            Stop-Function -Message "You must specify something to change."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 13
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($CaptureMode -contains "Custom" -and $server.VersionMajor -lt 15) {
                Stop-Function -Message "Custom capture mode can onlly be set in SQL Server 2019 and above" -Continue
            }

            if (($CustomCapturePolicyExecutionCount -or $CustomCapturePolicyTotalCompileCPUTimeMS -or $CustomCapturePolicyTotalExecutionCPUTimeMS -or $CustomCapturePolicyStaleThresholdHours) -and $server.VersionMajor -lt 15) {
                Write-Message -Level Warning -Message "Custom Capture Policies can only be set in SQL Server 2019 and above. These options will be skipped for $instance"
            }

            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $server -ExcludeDatabase $ExcludeDatabase -Database $Database | Where-Object IsAccessible

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.name) on $instance"

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db on server $instance is not accessible. Skipping database."
                    continue
                }

                if ($State) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing DesiredState to $state")) {
                        $db.QueryStoreOptions.DesiredState = $State
                        $db.QueryStoreOptions.Alter()
                        $db.QueryStoreOptions.Refresh()
                    }
                }

                if ($db.QueryStoreOptions.DesiredState -eq "Off" -and (Test-Bound -Parameter State -Not)) {
                    Write-Message -Level Warning -Message "State is set to Off; cannot change values. Please update State to ReadOnly or ReadWrite."
                    continue
                }

                if ($FlushInterval) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing DataFlushIntervalInSeconds to $FlushInterval")) {
                        $db.QueryStoreOptions.DataFlushIntervalInSeconds = $FlushInterval
                    }
                }

                if ($CollectionInterval) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing StatisticsCollectionIntervalInMinutes to $CollectionInterval")) {
                        $db.QueryStoreOptions.StatisticsCollectionIntervalInMinutes = $CollectionInterval
                    }
                }

                if ($MaxSize) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing MaxStorageSizeInMB to $MaxSize")) {
                        $db.QueryStoreOptions.MaxStorageSizeInMB = $MaxSize
                    }
                }

                if ($CaptureMode) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing QueryCaptureMode to $CaptureMode")) {
                        $db.QueryStoreOptions.QueryCaptureMode = $CaptureMode
                    }
                }

                if ($CleanupMode) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing SizeBasedCleanupMode to $CleanupMode")) {
                        $db.QueryStoreOptions.SizeBasedCleanupMode = $CleanupMode
                    }
                }

                if ($StaleQueryThreshold) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing StaleQueryThresholdInDays to $StaleQueryThreshold")) {
                        $db.QueryStoreOptions.StaleQueryThresholdInDays = $StaleQueryThreshold
                    }
                }

                $query = ""

                if ($server.VersionMajor -ge 14) {
                    if ($MaxPlansPerQuery) {
                        if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing MaxPlansPerQuery to $($MaxPlansPerQuery)")) {
                            $query += "ALTER DATABASE $db SET QUERY_STORE = ON (MAX_PLANS_PER_QUERY = $($MaxPlansPerQuery)); "
                        }
                    }

                    if ($WaitStatsCaptureMode) {
                        if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing WaitStatsCaptureMode to $($WaitStatsCaptureMode)")) {
                            if ($WaitStatsCaptureMode -eq "ON" -or $WaitStatsCaptureMode -eq "OFF") {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON (WAIT_STATS_CAPTURE_MODE = $($WaitStatsCaptureMode)); "
                            }
                        }
                    }
                }

                if ($server.VersionMajor -ge 15) {
                    if ($db.QueryStoreOptions.QueryCaptureMode -eq "CUSTOM") {
                        if ($CustomCapturePolicyStaleThresholdHours) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyStaleThresholdHours to $($CustomCapturePolicyStaleThresholdHours)")) {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON ( QUERY_CAPTURE_POLICY = ( STALE_CAPTURE_POLICY_THRESHOLD = $($CustomCapturePolicyStaleThresholdHours))); "
                            }
                        }

                        if ($CustomCapturePolicyExecutionCount) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyExecutionCount to $($CustomCapturePolicyExecutionCount)")) {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (EXECUTION_COUNT = $($CustomCapturePolicyExecutionCount))); "
                            }
                        }
                        if ($CustomCapturePolicyTotalCompileCPUTimeMS) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyTotalCompileCPUTimeMS to $($CustomCapturePolicyTotalCompileCPUTimeMS)")) {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (TOTAL_COMPILE_CPU_TIME_MS = $($CustomCapturePolicyTotalCompileCPUTimeMS))); "
                            }
                        }

                        if ($CustomCapturePolicyTotalExecutionCPUTimeMS) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyTotalExecutionCPUTimeMS to $($CustomCapturePolicyTotalExecutionCPUTimeMS)")) {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (TOTAL_EXECUTION_CPU_TIME_MS = $($CustomCapturePolicyTotalExecutionCPUTimeMS))); "
                            }
                        }
                    }
                }

                # Alter the Query Store Configuration
                if ($Pscmdlet.ShouldProcess("$db on $instance", "Altering Query Store configuration on database")) {
                    try {
                        $db.QueryStoreOptions.Alter()
                        $db.Alter()
                        $db.Refresh()

                        if ($query -ne "") {
                            $db.Query($query, $db.Name)
                        }
                    } catch {
                        Stop-Function -Message "Could not modify configuration." -Category InvalidOperation -InnerErrorRecord $_ -Target $db -Continue
                    }
                }

                if ($Pscmdlet.ShouldProcess("$db on $instance", "Getting results from Get-DbaDbQueryStoreOption")) {
                    Get-DbaDbQueryStoreOption -SqlInstance $server -Database $db.name -Verbose:$false
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQULFmN6MTIMOhZLevC1IoEl61L
# SpWgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFFlnSB2cwBhZNQcVR3zh5g2/n+MjMA0G
# CSqGSIb3DQEBAQUABIIBAHUCfoMpqBLDWo8/YAkS8rMFpufz27dWniJtVpzmA/4e
# 29YzXRSQBbpm9Nd85tAeBHbwHr79rjot8QuCCq5w5/Zwz3xD3Akt95I95Shn0dFT
# eB8vuZdejEDwqpncXigfO3tsJsfM8njAbuOzSY6PlU7yXalEwP7cwv/fD7UYfg/G
# XTzQJYhtrUSUvXOdeSUGlWN4BRXAORZIgZ13c0BqUud/sT2aCv3yCuyzzcRBrXHu
# YI06gEivu0Cc5lnhygeSANOxy2seKIfHnFfSAlAA5Q9k6OZjGR09TON57/gPWRsD
# vWqz0dI9ojTZHXA1z3ZC8/PceqY2YZa77Gmn/ix3zAGhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDIwWjAvBgkqhkiG9w0BCQQxIgQggp7TL+mbOUDRBUJA/Fba
# IPvygb3xYI3d8tqshgS9OAIwDQYJKoZIhvcNAQEBBQAEggIAXK+Ma/bO7LR0Hy2l
# NTcr7Zqq7Dc1A0pZ+NxuTvgPoHpNjYR9SlUeM6MZHamrFN6zF2k+WXHXuvoz95gH
# CIokVpJZuukMc/U/kbHLtrNAqQMwA27BsWvbZaisfy2w4ZggYYtof7Uv38xurjZh
# D/E+Bb4Ih/Sgzm7uIXyPHLOXRYPGtcD10li1L+61xvyN4NWAC4b3VSLMnHDYSUhu
# jW/9ZltUzf1hH+X7XEKnueDcUYvLEzaspNiIPV6zZkpft5I6WfA8IEIGPg1vBRW4
# fZcrYH0FGcNT0sAFGCUCzYupAl0ev+KD38uDXAr1dxgmhxRy0OIyZF0WjPHEwDa/
# DJ+/eYcabfMOnTM69J6Cdwm9sL7QH3ci+JtpcKE9NsUdAKeZpgnuYw3jNSHvTbcV
# 6D8HGzbO5jpT7ujdJ6pM6cTfDoJ2q8lbxXX/78AzqwlS+UcKrGW7ddcnAIOP9lk+
# 3MLHkcfFb72Umlara6q3crMMpqNa0D/5bGs5Zgh1khw68TDKOxRlC2K3Aw8tsQUP
# rRmPebaTgV6Foln6NlKSDFiEiZjILoDierfIRb5tsj7v65KXnknfz8HziQiPE2JI
# FSd5kiCOmTSwblumPolsMuEG2Cpf52P0pti76GLjKW8D/yjRra2BH0xXFeeRX152
# RqFXkLHIKgOnLGCZuDIyxckPsFk=
# SIG # End signature block
