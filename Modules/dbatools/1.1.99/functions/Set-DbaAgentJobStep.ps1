function Set-DbaAgentJobStep {
    <#
    .SYNOPSIS
        Set-DbaAgentJobStep updates a job step.

    .DESCRIPTION
        Set-DbaAgentJobStep updates a job step in the SQL Server Agent with parameters supplied.

        Note: ActiveScripting (ActiveX scripting) was discontinued in SQL Server 2016: https://docs.microsoft.com/en-us/sql/database-engine/discontinued-database-engine-functionality-in-sql-server

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job or the job object itself.

    .PARAMETER StepName
        The name of the step.

    .PARAMETER NewName
        The new name for the step in case it needs to be renamed.

    .PARAMETER SubSystem
        The subsystem used by the SQL Server Agent service to execute command.
        Allowed values 'ActiveScripting','AnalysisCommand','AnalysisQuery','CmdExec','Distribution','LogReader','Merge','PowerShell','QueueReader','Snapshot','Ssis','TransactSql'

    .PARAMETER SubSystemServer
        The subsystems AnalysisScripting, AnalysisCommand, AnalysisQuery require a server.

    .PARAMETER Command
        The commands to be executed by the SQLServerAgent service through the subsystem.

    .PARAMETER CmdExecSuccessCode
        The value returned by a CmdExec subsystem command to indicate that command executed successfully.

    .PARAMETER OnSuccessAction
        The action to perform if the step succeeds.
        Allowed values  "QuitWithSuccess" (default), "QuitWithFailure", "GoToNextStep", "GoToStep".
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER OnSuccessStepId
        The ID of the step in this job to execute if the step succeeds and OnSuccessAction is "GoToNextStep".

    .PARAMETER OnFailAction
        The action to perform if the step fails.
        Allowed values  "QuitWithFailure" (default), "QuitWithSuccess", "GoToNextStep", "GoToStep".
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER OnFailStepId
        The ID of the step in this job to execute if the step fails and OnFailAction is "GoToNextStep".

    .PARAMETER Database
        The name of the database in which to execute a Transact-SQL step.

    .PARAMETER DatabaseUser
        The name of the user account to use when executing a Transact-SQL step.

    .PARAMETER RetryAttempts
        The number of retry attempts to use if this step fails.

    .PARAMETER RetryInterval
        The amount of time in minutes between retry attempts.

    .PARAMETER OutputFileName
        The name of the file in which the output of this step is saved.

    .PARAMETER Flag
        Sets the flag(s) for the job step.

        Flag                                    Description
        ----------------------------------------------------------------------------
        AppendAllCmdExecOutputToJobHistory      Job history, including command output, is appended to the job history file.
        AppendToJobHistory                      Job history is appended to the job history file.
        AppendToLogFile                         Job history is appended to the SQL Server log file.
        AppendToTableLog                        Job history is appended to a log table.
        LogToTableWithOverwrite                 Job history is written to a log table, overwriting previous contents.
        None                                    Job history is not appended to a file.
        ProvideStopProcessEvent                 Job processing is stopped.

    .PARAMETER ProxyName
        The name of the proxy that the job step runs as.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        Allows pipeline input from Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .NOTES
        Tags: Agent, Job, JobStep
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentJobStep

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1 -NewName Step2

        Changes the name of the step in "Job1" with the name Step1 to Step2

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1 -Database msdb

        Changes the database of the step in "Job1" with the name Step1 to msdb

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1 -Job Job1, Job2 -StepName Step1 -Database msdb

        Changes job steps in multiple jobs with the name Step1 to msdb

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1, Job2 -StepName Step1 -Database msdb

        Changes job steps in multiple jobs on multiple servers with the name Step1 to msdb

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1 -StepName Step1 -Database msdb

        Changes the database of the step in "Job1" with the name Step1 to msdb for multiple servers

    .EXAMPLE
        PS C:\> sql1, sql2, sql3 | Set-DbaAgentJobStep -Job Job1 -StepName Step1 -Database msdb

        Changes the database of the step in "Job1" with the name Step1 to msdb for multiple servers using pipeline

    .EXAMPLE
        PS C:\> $jobStep = @{
                SqlInstance        = sqldev01
                Job                = dbatools1
                StepName           = "Step 2"
                Subsystem          = "CmdExec"
                Command            = "enter command text here"
                CmdExecSuccessCode = 0
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 1
                OnFailAction       = "GoToStep"
                OnFailStepId       = 1
                Database           = TestDB
                RetryAttempts      = 2
                RetryInterval      = 5
                OutputFileName     = "logCmdExec.txt"
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendAllCmdExecOutputToJobHistory
                ProxyName          = "dbatoolsci_proxy_1"
                Force              = $true
            }

        PS C:\>$newJobStep = Set-DbaAgentJobStep @jobStep

        Updates or creates a new job step named Step 2 in the dbatools1 job on the sqldev01 instance. The subsystem is set to CmdExec and uses a proxy.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [string]$StepName,
        [string]$NewName,
        [ValidateSet('ActiveScripting', 'AnalysisCommand', 'AnalysisQuery', 'CmdExec', 'Distribution', 'LogReader', 'Merge', 'PowerShell', 'QueueReader', 'Snapshot', 'Ssis', 'TransactSql')]
        [string]$Subsystem,
        [string]$SubsystemServer,
        [string]$Command,
        [int]$CmdExecSuccessCode,
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnSuccessAction,
        [int]$OnSuccessStepId,
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnFailAction,
        [int]$OnFailStepId,
        [string]$Database,
        [string]$DatabaseUser,
        [int]$RetryAttempts,
        [int]$RetryInterval,
        [string]$OutputFileName,
        [ValidateSet('AppendAllCmdExecOutputToJobHistory', 'AppendToJobHistory', 'AppendToLogFile', 'AppendToTableLog', 'LogToTableWithOverwrite', 'None', 'ProvideStopProcessEvent')]
        [string[]]$Flag,
        [string]$ProxyName,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject,
        [switch]$EnableException,
        [switch]$Force
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check the parameter on success step id
        if (($OnSuccessAction -ne 'GoToStep') -and ($OnSuccessStepId -ge 1)) {
            Stop-Function -Message "Parameter OnSuccessStepId can only be used with OnSuccessAction 'GoToStep'." -Target $SqlInstance
            return
        }

        # Check the parameter on fail step id
        if (($OnFailAction -ne 'GoToStep') -and ($OnFailStepId -ge 1)) {
            Stop-Function -Message "Parameter OnFailStepId can only be used with OnFailAction 'GoToStep'." -Target $SqlInstance
            return
        }

        if ($Subsystem -in 'AnalysisScripting', 'AnalysisCommand', 'AnalysisQuery') {
            if (-not $SubsystemServer) {
                Stop-Function -Message "Please enter the server value using -SubSystemServer for subsystem $Subsystem." -Target $Subsystem
                return
            }
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        # gather the SqlInstance(s) and pipeline of connected instances
        foreach ($instance in $SqlInstance) {
            try {
                $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }

        foreach ($server in $InputObject) {

            if ($Subsystem -eq "ActiveScripting" -and $server.VersionMajor -ge 13) {
                Stop-Function -Message "ActiveScripting (ActiveX script) is not supported in SQL Server 2016 or higher" -Target $server -Continue
            }

            foreach ($j in $Job) {
                try {
                    $currentJob = $server.JobServer.Jobs[$j]

                    if (-not $currentJob) {
                        Stop-Function -Message "Job '$j' doesn't exist on $server" -Target $server -Continue
                    }

                    $currentJobStep = $currentJob.JobSteps | Where-Object Name -eq $StepName

                    if (-not $Force -and (-not $currentJobStep)) {
                        Stop-Function -Message "Step '$StepName' doesn't exist for job $j on $server. If you would like to add a new job step use -Force" -Target $server -Continue
                    } elseif ($Force -and (-not $currentJobStep)) {
                        Write-Message -Message "Adding job step $StepName to $($currentJob.Name) on $server" -Level Verbose

                        try {
                            # create the job step as a placeholder here and then the other fields will be updated below depending on what the caller specified
                            $jobStep = New-DbaAgentJobStep -SqlInstance $server -Job $currentJob -StepName $StepName -EnableException
                        } catch {
                            Stop-Function -Message "Something went wrong creating the job step" -Target $server -ErrorRecord $_ -Continue
                        }

                    } else {
                        $jobStep = $currentJobStep
                    }

                    Write-Message -Message "Modifying job '$j' on $server" -Level Verbose

                    #region job step options
                    # Setting the options for the job step
                    if ($NewName) {
                        if ($Pscmdlet.ShouldProcess($server, "Setting job step name to $NewName for $StepName")) {
                            $jobStep.Rename($NewName)
                        }
                    }

                    if ($Subsystem) {
                        Write-Message -Message "Setting job step subsystem to $Subsystem" -Level Verbose
                        $jobStep.Subsystem = $Subsystem
                    }

                    if ($SubsystemServer) {
                        Write-Message -Message "Setting job step subsystem server to $SubsystemServer" -Level Verbose
                        $jobStep.Server = $SubsystemServer
                    }

                    if ($Command) {
                        Write-Message -Message "Setting job step command to $Command" -Level Verbose
                        $jobStep.Command = $Command
                    }

                    if ($CmdExecSuccessCode) {
                        Write-Message -Message "Setting job step command exec success code to $CmdExecSuccessCode" -Level Verbose
                        $jobStep.CommandExecutionSuccessCode = $CmdExecSuccessCode
                    }

                    if ($OnSuccessAction) {
                        Write-Message -Message "Setting job step success action to $OnSuccessAction" -Level Verbose
                        $jobStep.OnSuccessAction = $OnSuccessAction
                    }

                    if ($OnSuccessStepId) {
                        Write-Message -Message "Setting job step success step id to $OnSuccessStepId" -Level Verbose
                        $jobStep.OnSuccessStep = $OnSuccessStepId
                    }

                    if ($OnFailAction) {
                        Write-Message -Message "Setting job step fail action to $OnFailAction" -Level Verbose
                        $jobStep.OnFailAction = $OnFailAction
                    }

                    if ($OnFailStepId) {
                        Write-Message -Message "Setting job step fail step id to $OnFailStepId" -Level Verbose
                        $jobStep.OnFailStep = $OnFailStepId
                    }

                    if ($Database) {
                        # Check if the database is present on the server
                        if ($server.Databases.Name -contains $Database) {
                            Write-Message -Message "Setting job step database name to $Database" -Level Verbose
                            $jobStep.DatabaseName = $Database
                        } else {
                            Stop-Function -Message "The database $Database is not present on $server." -Target $server -Continue
                        }
                    }

                    if (($DatabaseUser) -and ($Database)) {
                        # Check if the username is present in the database
                        if ($Server.Databases[$jobStep.DatabaseName].Users.Name -contains $DatabaseUser) {
                            Write-Message -Message "Setting job step database username to $DatabaseUser" -Level Verbose
                            $jobStep.DatabaseUserName = $DatabaseUser
                        } else {
                            Stop-Function -Message "The database user '$DatabaseUser' is not present in the database $($jobStep.DatabaseName) on $server." -Target $server -Continue
                        }
                    }

                    if ($RetryAttempts) {
                        Write-Message -Message "Setting job step retry attempts to $RetryAttempts" -Level Verbose
                        $jobStep.RetryAttempts = $RetryAttempts
                    }

                    if ($RetryInterval) {
                        Write-Message -Message "Setting job step retry interval to $RetryInterval" -Level Verbose
                        $jobStep.RetryInterval = $RetryInterval
                    }

                    if ($OutputFileName) {
                        Write-Message -Message "Setting job step output file name to $OutputFileName" -Level Verbose
                        $jobStep.OutputFileName = $OutputFileName
                    }

                    if ($ProxyName) {
                        # Check if the proxy exists
                        if ($Server.JobServer.ProxyAccounts.Name -contains $ProxyName) {
                            Write-Message -Message "Setting job step proxy name to $ProxyName" -Level Verbose
                            $jobStep.ProxyName = $ProxyName
                        } else {
                            Stop-Function -Message "The proxy name $ProxyName doesn't exist on instance $server." -Target $server -Continue
                        }
                    }

                    if ($Flag.Count -ge 1) {
                        Write-Message -Message "Setting job step flag(s) to $($Flags -join ',')" -Level Verbose
                        $jobStep.JobStepFlags = $Flag
                    }
                    #region job step options

                    # Execute
                    if ($PSCmdlet.ShouldProcess($server, "Committing changes for job step '$StepName' for job '$j'")) {
                        try {
                            Write-Message -Message "Committing changes for '$StepName' for job '$j' on $server" -Level Verbose

                            # Change the job step
                            $jobStep.Alter()

                            # Return the job step
                            $jobStep
                        } catch {
                            Stop-Function -Message "Something went wrong changing the job step" -ErrorRecord $_ -Target $server -Continue
                        }
                    }

                } catch {
                    Stop-Function -Message "Something went wrong" -Target $j -ErrorRecord $_ -Continue
                }
            }
        }
    } # process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished changing job step(s)" -Level Verbose
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUIQv4CjbVEmpQ99q5z4a2bN/P
# u+SgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFFv1JSjyYUXDPggrmTnTtBDcp3apMA0G
# CSqGSIb3DQEBAQUABIIBAGSkfLkIOgP7WPijgDTJPOnBVJH5TEdocNOFhmK32qen
# ltjQFluvsAlidnIYvvjwKxocXFBguD3scfYA6+6uQikiom6TBkscIAxcyOvXR0ja
# wYTlYtkmqA+wwqZ1a8Q6+CZI1n3kXt6hcV46VGAcBpBmdfDLrUF0giH2iiGF5Zz6
# XNydXCcGPpwHdbpvYAiZSWK2HxQBaKtdlckOoH0UEeO9crOldeI4E6z3YNVEZU8F
# nlP9OCrpQM5Az8DF3WJ7c/Wv0YFNBq4uZTCNdbE3RreuzLRWXGxPzrMcJHOSGfvS
# Uwlmi2hhy3cg22bdrvjGAJeqgIboXYvvBGAyTbaTqOChggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDE4WjAvBgkqhkiG9w0BCQQxIgQgRv8G8wxoaWXTp+66O3gw
# wlkl7l8CY2gtJyGf4SAmcyMwDQYJKoZIhvcNAQEBBQAEggIAM9nooeuMb6hKnghT
# 2XG4EiHEoudSG4RdlutINBXVew8tzahs2QMS8I80tNWSljiAmKVYHfxW8usdiPG5
# Zx9+ze3H5KvMwNort9BOP1uNq8rVmJF9WyrVsD1f5qZGet2SOKG3/cXj19osl1Oj
# LBvLMMO4VXJVRLj7nxMeYTg6oZ8dKD+W0mI0VY8QuklahP/TrxuZp8VcmSI0ZK/E
# RI8LaUq/56xk1oYzjELk0OiE456ksU5RxGriUod8tXV895oqJYXJFPuynTZmsGEz
# 3rDwGSOcRAPQ+4VzSHeAxGpHdYPnlwQpwm4JpDtY8s5cb5ndd6HA6jzm8VWnHaP+
# Si7wZ7098WASZjGyzBHpNbIFdswfguBOTOvDnsydmBLaCr1iauafeMZ4F33x0Kbk
# L05+03Q8ogTuLY2c5k3Q0leYNLqs3tB438rCEgv/oZQ4POX7g3Lw53kefqAdqR7r
# GNXpn0rryZDoC4bFhImlPniPvWDhpwFVsrZys2OqfocEMMANZkglEwjPHlwBTg1d
# Ayh30BfFIMllTmFfwct1jhaqjjnvb4THOyDDS4kaG+UqdIZ0F2BsmszN501qqJIn
# 6EB5u9VGtryVaTo3RKaDc5M+LDGZGdZzX+FY4twx2veIb5Bka0JGDq4wGcgy6mco
# kuTFK+NT+Nvf3jyGzy1KWN+yZrg=
# SIG # End signature block
