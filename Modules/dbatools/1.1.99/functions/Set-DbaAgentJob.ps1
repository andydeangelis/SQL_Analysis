function Set-DbaAgentJob {
    <#
    .SYNOPSIS
        Set-DbaAgentJob updates a job.

    .DESCRIPTION
        Set-DbaAgentJob updates a job in the SQL Server Agent with parameters supplied.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job.

    .PARAMETER Schedule
        Schedule to attach to job. This can be more than one schedule.

    .PARAMETER ScheduleId
        Schedule ID to attach to job. This can be more than one schedule ID.

    .PARAMETER NewName
        The new name for the job.

    .PARAMETER Enabled
        Enabled the job.

    .PARAMETER Disabled
        Disabled the job

    .PARAMETER Description
        The description of the job.

    .PARAMETER StartStepId
        The identification number of the first step to execute for the job.

    .PARAMETER Category
        The category of the job.

    .PARAMETER OwnerLogin
        The name of the login that owns the job.

    .PARAMETER EventLogLevel
        Specifies when to place an entry in the Microsoft Windows application log for this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER EmailLevel
        Specifies when to send an e-mail upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER NetsendLevel
        Specifies when to send a network message upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER PageLevel
        Specifies when to send a page upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER EmailOperator
        The e-mail name of the operator to whom the e-mail is sent when EmailLevel is reached.

    .PARAMETER NetsendOperator
        The name of the operator to whom the network message is sent.

    .PARAMETER PageOperator
        The name of the operator to whom a page is sent.

    .PARAMETER DeleteLevel
        Specifies when to delete the job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .PARAMETER InputObject
        Enables piping job objects

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentJob

    .EXAMPLE
        PS C:\> Set-DbaAgentJob sql1 -Job Job1 -Disabled

        Changes the job to disabled

    .EXAMPLE
        PS C:\> Set-DbaAgentJob sql1 -Job Job1 -OwnerLogin user1

        Changes the owner of the job

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -EventLogLevel OnSuccess

        Changes the job and sets the notification to write to the Windows Application event log on success

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -EmailLevel OnFailure -EmailOperator dba

        Changes the job and sets the notification to send an e-mail to the e-mail operator

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1, Job2, Job3 -Enabled

        Changes multiple jobs to enabled

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job Job1, Job2, Job3 -Enabled

        Changes multiple jobs to enabled on multiple servers

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -Description 'Just another job' -Whatif

        Doesn't Change the job but shows what would happen.

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job 'Job One' -Description 'Job One'

        Changes a job with the name "Job1" on multiple servers to have another description

    .EXAMPLE
        PS C:\> sql1, sql2, sql3 | Set-DbaAgentJob -Job Job1 -Description 'Job One'

        Changes a job with the name "Job1" on multiple servers to have another description using pipe line

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [object[]]$Schedule,
        [int[]]$ScheduleId,
        [string]$NewName,
        [switch]$Enabled,
        [switch]$Disabled,
        [string]$Description,
        [int]$StartStepId,
        [string]$Category,
        [string]$OwnerLogin,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EventLogLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EmailLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$NetsendLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$PageLevel,
        [string]$EmailOperator,
        [string]$NetsendOperator,
        [string]$PageOperator,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$DeleteLevel,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check of the event log level is of type string and set the integer value
        if (($EventLogLevel -notin 0, 1, 2, 3) -and ($null -ne $EventLogLevel)) {
            $EventLogLevel = switch ($EventLogLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the email level is of type string and set the integer value
        if (($EmailLevel -notin 0, 1, 2, 3) -and ($null -ne $EmailLevel)) {
            $EmailLevel = switch ($EmailLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the net send level is of type string and set the integer value
        if (($NetsendLevel -notin 0, 1, 2, 3) -and ($null -ne $NetsendLevel)) {
            $NetsendLevel = switch ($NetsendLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the page level is of type string and set the integer value
        if (($PageLevel -notin 0, 1, 2, 3) -and ($null -ne $PageLevel)) {
            $PageLevel = switch ($PageLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the delete level is of type string and set the integer value
        if (($DeleteLevel -notin 0, 1, 2, 3) -and ($null -ne $DeleteLevel)) {
            $DeleteLevel = switch ($DeleteLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check the e-mail operator name
        if (($EmailLevel -ge 1) -and (-not $EmailOperator)) {
            Stop-Function -Message "Please set the e-mail operator when the e-mail level parameter is set." -Target $SqlInstance
            return
        }

        # Check the e-mail level parameter
        if ($EmailOperator -and ($null -eq $EmailLevel)) {
            Stop-Function -Message "Please set the e-mail level parameter when the e-mail level operator is set." -Target $SqlInstance
            return
        }

        # Check the net send operator name
        if (($NetsendLevel -ge 1) -and (-not $NetsendOperator)) {
            Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $SqlInstance
            return
        }

        # Check the net send level parameter
        if ($NetsendOperator -and ($null -eq $NetsendLevel)) {
            Stop-Function -Message "Please set the net send level parameter when the net send level operator is set." -Target $SqlInstance
            return
        }

        # Check the page operator name
        if (($PageLevel -ge 1) -and (-not $PageOperator)) {
            Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $SqlInstance
            return
        }

        # Check the page level parameter
        if ($PageOperator -and ($null -eq $PageLevel)) {
            Stop-Function -Message "Please set the page level parameter when the page level operator is set." -Target $SqlInstance
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $Job)) {
            Stop-Function -Message "You must specify a job name or pipe in results from another command" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($server.JobServer.Jobs.Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesn't exists on $instance" -Target $instance
                } else {
                    # Get the job
                    try {
                        $InputObject += $server.JobServer.Jobs[$j]

                        # Refresh the object
                        $InputObject.Refresh()
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the job" -Target $j -ErrorRecord $_ -Continue
                    }
                }
            }
        }

        foreach ($currentjob in $InputObject) {
            $server = $currentjob.Parent.Parent

            #region job options
            # Settings the options for the job
            if ($NewName) {
                if ($PSCmdlet.ShouldProcess($server, "Setting job name of $($currentjob.Name) to $NewName")) {
                    $currentjob.Rename($NewName)
                }
            }

            if ($Schedule) {
                # Loop through each of the schedules
                foreach ($s in $Schedule) {
                    if ($server.JobServer.SharedSchedules.Name -contains $s) {
                        # Get the schedule ID
                        $sID = $server.JobServer.SharedSchedules[$s].ID

                        # Add schedule to job
                        if ($PSCmdlet.ShouldProcess($server, "Adding schedule id $sID to job $($currentjob.Name)")) {
                            $currentjob.AddSharedSchedule($sID)
                        }
                    } else {
                        Stop-Function -Message "Schedule $s cannot be found on instance $instance" -Target $s -Continue
                    }

                }
            }

            if ($ScheduleId) {
                # Loop through each of the schedules IDs
                foreach ($sID in $ScheduleId) {
                    # Check if the schedule is
                    if ($server.JobServer.SharedSchedules.ID -contains $sID) {
                        # Add schedule to job
                        if ($PSCmdlet.ShouldProcess($server, "Adding schedule id $sID to job $($currentjob.Name)")) {
                            $currentjob.AddSharedSchedule($sID)
                        }
                    } else {
                        Stop-Function -Message "Schedule ID $sID cannot be found on instance $instance" -Target $sID -Continue
                    }
                }
            }

            if ($Enabled) {
                Write-Message -Message "Setting job to enabled" -Level Verbose
                $currentjob.IsEnabled = $true
            }

            if ($Disabled) {
                Write-Message -Message "Setting job to disabled" -Level Verbose
                $currentjob.IsEnabled = $false
            }

            if ($Description) {
                Write-Message -Message "Setting job description to $Description" -Level Verbose
                $currentjob.Description = $Description
            }

            if ($Category) {
                # Check if the job category exists
                if ($Category -notin $server.JobServer.JobCategories.Name) {
                    if ($Force) {
                        if ($PSCmdlet.ShouldProcess($instance, "Creating job category on $instance")) {
                            try {
                                # Create the category
                                New-DbaAgentJobCategory -SqlInstance $server -Category $Category

                                Write-Message -Message "Setting job category to $Category" -Level Verbose
                                $currentjob.Category = $Category
                            } catch {
                                Stop-Function -Message "Couldn't create job category $Category from $instance" -Target $instance -ErrorRecord $_
                            }
                        }
                    } else {
                        Stop-Function -Message "Job category $Category doesn't exist on $instance. Use -Force to create it." -Target $instance
                        return
                    }
                } else {
                    Write-Message -Message "Setting job category to $Category" -Level Verbose
                    $currentjob.Category = $Category
                }
            }

            if ($StartStepId) {
                # Get the job steps
                $currentjobSteps = $currentjob.JobSteps

                # Check if there are any job steps
                if ($currentjobSteps.Count -ge 1) {
                    # Check if the start step id value is one of the job steps in the job
                    if ($currentjobSteps.ID -contains $StartStepId) {
                        Write-Message -Message "Setting job start step id to $StartStepId" -Level Verbose
                        $currentjob.StartStepID = $StartStepId
                    } else {
                        Write-Message -Message "The step id is not present in job $j on instance $instance" -Warning
                    }

                } else {
                    Stop-Function -Message "There are no job steps present for job $j on instance $instance" -Target $instance -Continue
                }

            }

            if ($OwnerLogin) {
                # Check if the login name is present on the instance
                if ($server.Logins.Name -contains $OwnerLogin) {
                    Write-Message -Message "Setting job owner login name to $OwnerLogin" -Level Verbose
                    $currentjob.OwnerLoginName = $OwnerLogin
                } else {
                    Stop-Function -Message "The given owner log in name $OwnerLogin does not exist on instance $instance" -Target $instance -Continue
                }
            }

            if (Test-Bound -ParameterName EventLogLevel) {
                Write-Message -Message "Setting job event log level to $EventlogLevel" -Level Verbose
                $currentjob.EventLogLevel = $EventLogLevel
            }

            if (Test-Bound -ParameterName EmailLevel) {
                # Check if the notifiction needs to be removed
                if ($EmailLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToEmail = $null

                    # Remove the notification
                    $currentjob.EmailLevel = $EmailLevel
                } else {
                    # Check if either the operator e-mail parameter is set or the operator is set in the job
                    if ($EmailOperator -or $currentjob.OperatorToEmail) {
                        Write-Message -Message "Setting job e-mail level to $EmailLevel" -Level Verbose
                        $currentjob.EmailLevel = $EmailLevel
                    } else {
                        Stop-Function -Message "Cannot set e-mail level $EmailLevel without a valid e-mail operator name" -Target $instance -Continue
                    }
                }
            }

            if (Test-Bound -ParameterName NetsendLevel) {
                # Check if the notifiction needs to be removed
                if ($NetsendLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToNetSend = $null

                    # Remove the notification
                    $currentjob.NetSendLevel = $NetsendLevel
                } else {
                    # Check if either the operator netsend parameter is set or the operator is set in the job
                    if ($NetsendOperator -or $currentjob.OperatorToNetSend) {
                        Write-Message -Message "Setting job netsend level to $NetsendLevel" -Level Verbose
                        $currentjob.NetSendLevel = $NetsendLevel
                    } else {
                        Stop-Function -Message "Cannot set netsend level $NetsendLevel without a valid netsend operator name" -Target $instance -Continue
                    }
                }
            }

            if (Test-Bound -ParameterName PageLevel) {
                # Check if the notifiction needs to be removed
                if ($PageLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToPage = $null

                    # Remove the notification
                    $currentjob.PageLevel = $PageLevel
                } else {
                    # Check if either the operator pager parameter is set or the operator is set in the job
                    if ($PageOperator -or $currentjob.OperatorToPage) {
                        Write-Message -Message "Setting job pager level to $PageLevel" -Level Verbose
                        $currentjob.PageLevel = $PageLevel
                    } else {
                        Stop-Function -Message "Cannot set page level $PageLevel without a valid netsend operator name" -Target $instance -Continue
                    }
                }
            }

            # Check the current setting of the job's email level
            if ($EmailOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $EmailOperator) {
                    Write-Message -Message "Setting job e-mail operator to $EmailOperator" -Level Verbose
                    $currentjob.OperatorToEmail = $EmailOperator
                } else {
                    Stop-Function -Message "The e-mail operator name $EmailOperator does not exist on instance $instance. Exiting.." -Target $j -Continue
                }
            }

            if ($NetsendOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $NetsendOperator) {
                    Write-Message -Message "Setting job netsend operator to $NetsendOperator" -Level Verbose
                    $currentjob.OperatorToNetSend = $NetsendOperator
                } else {
                    Stop-Function -Message "The netsend operator name $NetsendOperator does not exist on instance $instance. Exiting.." -Target $j -Continue
                }
            }

            if ($PageOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $PageOperator) {
                    Write-Message -Message "Setting job pager operator to $PageOperator" -Level Verbose
                    $currentjob.OperatorToPage = $PageOperator
                } else {
                    Stop-Function -Message "The page operator name $PageOperator does not exist on instance $instance. Exiting.." -Target $instance -Continue
                }
            }

            if (Test-Bound -ParameterName DeleteLevel) {
                Write-Message -Message "Setting job delete level to $DeleteLevel" -Level Verbose
                $currentjob.DeleteLevel = $DeleteLevel
            }
            #endregion job options

            # Execute
            if ($PSCmdlet.ShouldProcess($SqlInstance, "Changing the job $j")) {
                try {
                    Write-Message -Message "Changing the job" -Level Verbose

                    # Change the job
                    $currentjob.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the job" -ErrorRecord $_ -Target $instance -Continue
                }

                # Refresh the SMO - another bug in SMO? As this should not be needed...
                $currentjob.Refresh()

                Get-DbaAgentJob -SqlInstance $server -Job $currentjob.Name
            }
        }
    }

    end {
        Write-Message -Message "Finished changing job(s)" -Level Verbose
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU/mwYY4XP//DG/bsPWRx/PnIn
# SwSgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFAZQQjBBvIL3FBjxRxeEK4nd5YEYMA0G
# CSqGSIb3DQEBAQUABIIBAFVuPLdEcHe9zqVP7aZV9KxderG8k3MGvEmZ/+KITFd/
# ArUhPpF53E8a8H9/MEHsLuVrjwpCIZVOBWY08eCn3wex6+JHp4UhvFtFudDoh3jH
# GJo4T9SA7Qayy8fsK1M6jGlEbgjRQqkU8bcbpAzgz8HZJE501XqZRWhCASYEQTgX
# TGJ5tDHxGiZlmabo8jYNqHe53ZpLmFHD9Xj8IBCs/GQIcU8lCOvumE3qG8StI1qi
# BoIe9ZJgjCksbSl3muQIzoyZREnhpw11zwAgw7r/RP5i4o1SSnbLUO1lCdZmVrGd
# 4GP7xLGC/HXrr6zSTicE/59H8VNUgRpC2txYf5tVZiWhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDE4WjAvBgkqhkiG9w0BCQQxIgQgrqKhab+a/iKwXs9VVSfz
# P2N9Cyj0Hkuem4N4lr8vJdIwDQYJKoZIhvcNAQEBBQAEggIAKmw9stPCIuvOIInN
# NZfAOPduDWI8nTV2/OI7pS1WUWmE8vzV0cIjpn5Ioo9ok8qBFXChOJuqYFntNfqw
# 92nz/3jL7CcD7yboiikBfuxs3t2v4iW/s517v1Ek0XG8rfsMzGOK+H3MJVaYyrNj
# LtYvchjKNlAsdWYz3O8HN8q3BwHJONsTXEDl2oljk1lGc9vaPDC92sk2jH2NaAmo
# 0JvaVY85ZJTAFudzryK/17UxgIKrZTiNBrKwtYorOoKwpAqG0zxDHbJmuu/kHEdd
# kOz7uiP8LrGpm8iPYvOICIKwDleBV6AnTnNr8APyqNm0oMs4NG/xPzUfEnwLzH5C
# PKFSwmqjTSveHgjwbBCCieAvEUMM4+vCPh/o2xDxWLi09jC7fgNh897RsRA5J+oq
# kg7Cyu//TRQ3727SN6XHQl4JShwyu5XW6tIGRy7ppXkqacdZN6L/fJ2U8WVS5zmL
# SrIH5B7ngD0yukcelO4WTkvSiWQSmRIklfK3kD3li4pLlXwExVB5vpjC2XNeFpJB
# n+yeBfMyU2TUoUMt9cv3P1oz9OYpsuX2v/X3SylnXg4zSKBAgCmDqcnJOiguIi2U
# o0eFgD20o9+ornaxBxreVnCx/zvB8IOTRFT+bsokClTFPGIjS/yus1aFJxIj3XJO
# 34F+0rORPY4wlJycnQgLcJYsPfQ=
# SIG # End signature block
