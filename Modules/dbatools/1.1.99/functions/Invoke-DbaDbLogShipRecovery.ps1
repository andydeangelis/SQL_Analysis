function Invoke-DbaDbLogShipRecovery {
    <#
    .SYNOPSIS
        Invoke-DbaDbLogShipRecovery recovers log shipped databases to a normal state to act upon a migration or disaster.

    .DESCRIPTION
        By default all the databases for a particular instance are recovered.
        If the database is in the right state, either standby or recovering, the process will try to recover the database.

        At first the function will check if the backup source directory can still be reached.
        If so it will look up the last transaction log backup for the database. If that backup file is not the last copied file the log shipping copy job will be started.
        If the directory cannot be reached for the function will continue to the restoring process.
        After the copy job check is performed the job is disabled to prevent the job to run.

        For the restore the log shipping status is checked in the msdb database.
        If the last restored file is not the same as the last file name found, the log shipping restore job will be executed.
        After the restore job check is performed the job is disabled to prevent the job to run

        The last part is to set the database online by restoring the databases with recovery

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        Database to perform the restore for. This value can also be piped enabling multiple databases to be recovered.
        If this value is not supplied all databases will be recovered.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER NoRecovery
        Allows you to choose to not restore the database to a functional state (Normal) in the final steps of the process.
        By default the database is restored to a functional state (Normal).

    .PARAMETER InputObject
        Allows piped input from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Use this parameter to force the function to continue and perform any adjusting actions to successfully execute

    .PARAMETER Delay
        Set the delay in seconds to wait for the copy and/or restore jobs.
        By default the delay is 5 seconds

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: LogShipping
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbLogShipRecovery

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -Force

        Recovers all the databases on the instance that are enabled for log shipping

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -SqlCredential $cred -Verbose -Force

        Recovers all the databases on the instance that are enabled for log shipping using a credential

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -database db_logship -Verbose

        Recovers the database "db_logship" to a normal status

    .EXAMPLE
        PS C:\> db1, db2, db3, db4 | Invoke-DbaDbLogShipRecovery -SqlInstance server1 -Verbose

        Recovers the database db1, db2, db3, db4 to a normal status

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -Force -WhatIf

        Shows what would happen if the command were executed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param
    (
        [DbaInstanceParameter[]]$SqlInstance,
        [string[]]$Database,
        [PSCredential]$SqlCredential,
        [switch]$NoRecovery,
        [switch]$EnableException,
        [switch]$Force,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [int]$Delay = 5
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $stepCounter = 0
    }
    process {
        foreach ($instance in $SqlInstance) {
            if (-not $Force -and -not $Database) {
                Stop-Function -Message "You must specify a -Database or -Force for all databases" -Target $server.name
                return
            }
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        # Loop through all the databases
        foreach ($db in $InputObject) {
            $stepCounter = 0
            $server = $db.Parent
            $instance = $server.Name
            $activity = "Performing log shipping recovery for $($db.Name) on $($server.Name)"
            # Try to get the agent service details
            try {
                # Get the service details
                $agentStatus = $server.Query("SELECT COUNT(*) as AgentCount FROM master.dbo.sysprocesses WITH (nolock) WHERE Program_Name LIKE 'SQLAgent%'")

                if ($agentStatus.AgentCount -lt 1) {
                    Stop-Function -Message "The agent service is not in a running state. Please start the service." -ErrorRecord $_ -Target $server.name
                    return
                }
            } catch {
                Stop-Function -Message "Unable to get SQL Server Agent Service status" -ErrorRecord $_ -Target $server.name
                return
            }
            # Query for retrieving the log shipping information
            $query = "SELECT lss.primary_server, lss.primary_database, lsd.secondary_database, lss.backup_source_directory,
                    lss.backup_destination_directory, lss.last_copied_file, lss.last_copied_date,
                    lsd.last_restored_file, sj1.name AS 'copyjob', sj2.name AS 'restorejob'
                FROM msdb.dbo.log_shipping_secondary AS lss
                    INNER JOIN msdb.dbo.log_shipping_secondary_databases AS lsd ON lsd.secondary_id = lss.secondary_id
                    INNER JOIN msdb.dbo.sysjobs AS sj1 ON sj1.job_id = lss.copy_job_id
                    INNER JOIN msdb.dbo.sysjobs AS sj2 ON sj2.job_id = lss.restore_job_id
                WHERE lsd.secondary_database = '$($db.Name)'"

            # Retrieve the log shipping information from the secondary instance
            try {
                Write-Message -Message "Retrieving log shipping information from the secondary instance" -Level Verbose
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Retrieving log shipping information from the secondary instance"
                $logshipping_details = $server.Query($query)
            } catch {
                Stop-Function -Message "Error retrieving the log shipping details: $($_.Exception.Message)" -ErrorRecord $_ -Target $server.name
                return
            }

            # Check if there are any databases to recover
            if ($null -eq $logshipping_details) {
                Stop-Function -Message "The database $db is not configured as a secondary database for log shipping." -Continue
            } else {
                # Loop through each of the log shipped databases
                foreach ($ls in $logshipping_details) {
                    $secondarydb = $ls.secondary_database

                    $recoverResult = "Success"
                    $comment = ""
                    $jobOutputs = @()

                    # Check if the database is in the right state
                    if ($server.Databases[$secondarydb].Status -notin ('Normal, Standby', 'Standby', 'Restoring')) {
                        Stop-Function -Message "The database $db doesn't have the right status to be recovered" -Continue
                    } else {
                        Write-Message -Message "Started Recovery for $secondarydb" -Level Verbose

                        # Start the job to get the latest files
                        if ($PSCmdlet.ShouldProcess($server.name, ("Starting copy job $($ls.copyjob)"))) {
                            Write-Message -Message "Starting copy job $($ls.copyjob)" -Level Verbose

                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Starting copy job"
                            try {
                                $null = Start-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob
                            } catch {
                                $recoverResult = "Failed"
                                $comment = "Something went wrong starting the copy job $($ls.copyjob)"
                                Stop-Function -Message "Something went wrong starting the copy job.`n$($_)" -ErrorRecord $_ -Target $server.name
                            }

                            if ($recoverResult -ne 'Failed') {
                                Write-Message -Message "Copying files to $($ls.backup_destination_directory)" -Level Verbose

                                Write-Message -Message "Waiting for the copy action to complete.." -Level Verbose

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob

                                while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Get the job status
                                    $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob
                                }

                                # Check the lat outcome of the job
                                if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                    $recoverResult = "Failed"
                                    $comment = "The copy job for database $db failed. Please check the error log."
                                    Stop-Function -Message "The copy job for database $db failed. Please check the error log."
                                }

                                $jobOutputs += $jobStatus

                                Write-Message -Message "Copying of backup files finished" -Level Verbose
                            }
                        } # if should process

                        # Disable the log shipping copy job on the secondary instance
                        if ($recoverResult -ne 'Failed') {
                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Disabling copy job"

                            if ($PSCmdlet.ShouldProcess($server.name, "Disabling copy job $($ls.copyjob)")) {
                                try {
                                    Write-Message -Message "Disabling copy job $($ls.copyjob)" -Level Verbose
                                    $null = Set-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob -Disabled
                                } catch {
                                    $recoverResult = "Failed"
                                    $comment = "Something went wrong disabling the copy job."
                                    Stop-Function -Message "Something went wrong disabling the copy job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Start the restore job
                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Starting restore job"

                            if ($PSCmdlet.ShouldProcess($server.name, ("Starting restore job " + $ls.restorejob))) {
                                Write-Message -Message "Starting restore job $($ls.restorejob)" -Level Verbose
                                try {
                                    $null = Start-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob
                                } catch {
                                    $comment = "Something went wrong starting the restore job."
                                    Stop-Function -Message "Something went wrong starting the restore job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }

                                Write-Message -Message "Waiting for the restore action to complete.." -Level Verbose

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob

                                while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Get the job status
                                    $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob
                                }

                                # Check the lat outcome of the job
                                if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                    $recoverResult = "Failed"
                                    $comment = "The restore job for database $db failed. Please check the error log."
                                    Stop-Function -Message "The restore job for database $db failed. Please check the error log."
                                }

                                $jobOutputs += $jobStatus
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Disable the log shipping restore job on the secondary instance
                            if ($PSCmdlet.ShouldProcess($server.name, "Disabling restore job $($ls.restorejob)")) {
                                try {
                                    Write-Message -Message ("Disabling restore job " + $ls.restorejob) -Level Verbose
                                    $null = Set-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob -Disabled
                                } catch {
                                    $recoverResult = "Failed"
                                    $comment = "Something went wrong disabling the restore job."
                                    Stop-Function -Message "Something went wrong disabling the restore job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Check if the database needs to recovered to its normal state
                            if ($NoRecovery -eq $false) {
                                if ($PSCmdlet.ShouldProcess($secondarydb, "Restoring database with recovery")) {
                                    Write-Message -Message "Restoring the database to it's normal state" -Level Verbose
                                    try {
                                        $query = "RESTORE DATABASE [$secondarydb] WITH RECOVERY"
                                        $server.Query($query)

                                    } catch {
                                        $recoverResult = "Failed"
                                        $comment = "Something went wrong restoring the database to a normal state."
                                        Stop-Function -Message "Something went wrong restoring the database to a normal state.`n$($_)" -ErrorRecord $_ -Target $secondarydb
                                    }
                                }
                            } else {
                                $comment = "Skipping restore with recovery."
                                Write-Message -Message "Skipping restore with recovery" -Level Verbose
                            }

                            Write-Message -Message ("Finished Recovery for $secondarydb") -Level Verbose
                        }

                        # Reset the log ship details
                        $logshipping_details = $null

                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.InstanceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $secondarydb
                            RecoverResult = $recoverResult
                            Comment       = $comment
                        }

                    }
                }
            }
            Write-Progress -Activity $activity -Completed
            $stepCounter = 0
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUDGeR4sl8qrJPwa2/wPElo3hh
# J76gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFOOdXYWUXiH1/o4u8IXfz4XvPDHsMA0G
# CSqGSIb3DQEBAQUABIIBAETSXclX9HI+MFwmr3iNfjJN6ThTbV80uvFC2vjH0iRu
# mY+VeHlwUjnm3CLYJEPvGUiUtQ80uM+JcLDYfeWW2JFrInMisyhgn+tq3VQxFNgO
# Mfiw6KLzJQYo9hi3//c7asLQAILN7/hsJ2tk5vFvVT0xFzGQD8IFjcXVT+b+l9ZC
# SAuN80ZjJ3DrIxFdb+72Mg59bmwLxVo+WpMddfZ+5jtIOFCFj1971kmV2ayz+AmI
# BHjkQHMOzK9+MeouuzLFlqYNgr5GH7h6yAWzgOUQTYWPhcp5+c6kq/y1axe/UXeJ
# iiVAN5gtQnkZVP1+HwAQ7bJ4JSwQrGuWrEwZx/fSfTmhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU2WjAvBgkqhkiG9w0BCQQxIgQg3JSVCNX9xQbMOhvPrMIA
# +PFPLVdFN1xq/M7GhAL07rgwDQYJKoZIhvcNAQEBBQAEggIAAPKHeAUd2wz7jvze
# 2fa6sG4B1dS+UdacE66P9SvTyAvGbT9tKzVj32lrwXeotlIawMhEnROBPDaAYaDM
# p5NxIoBl0vOhm3mjDm+EkkjgC94gEMlsHF1ei8DGWOa44+8j9TvuZHEwn08QCMoI
# cMS9yzL3TemNUoBTgcsTH0oyj+SoMUftrxvINn95RlgF39pYibKus+8Q6O1uus9Y
# KRcygFyyR89jskmj7FnM2UTDzBiKHRAiHFrf23j1GoXJAaZDq3f/3b+5WD331csp
# 3qQZgZ8VHbH3uG+FHQMNpatWpflaG7vSHsbj4dmh0O6O//i03lXCOXDIDWN7f2fb
# AwrZ0f72aBUHnk5eHxjevfMW80g2MMqCWSNM7BHkXNfSr3aB/Wv2rC9ZI17pn0Hc
# ksvd4hPbc3ZOtVXNhW+GqpH/2tcUCyR8FptE8bR2j/obSc/UGlgJO/JaKHPGrTkc
# KvwRMm26gGPRiMs0GnhsnvPXm0NzfbJ1a6prvN1uggEspgM0QkLD3CQ6kMh60KAk
# rOwEHsmWZAE0wnsXAHcU750N13Si1j2+SP5DK59v50m3M69qyz2ApsohtvBmMoit
# XUJ20hsoh4K3UhRJS2fh5zGfXp8rQiNOZmPe4XTiZI94+P8o/QShpDxiWS3zIOnC
# CKAAhj+ZejKdlB/jjh7tv/hvNPM=
# SIG # End signature block
