function Set-DbaAgentOperator {
    <#
    .SYNOPSIS
        Updates/modifies agent operators on an instance.

    .DESCRIPTION
        Updates/modifies agent operators on an instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Operator
        Name of the operator in SQL Agent.

    .PARAMETER Name
        The new name of the agent operator.

    .PARAMETER EmailAddress
        The email address the SQL Agent will use to email alerts to the operator.

    .PARAMETER NetSendAddress
        The net send address the SQL Agent will use for the operator to net send alerts.

    .PARAMETER PagerAddress
        The pager email address the SQL Agent will use to send alerts to the operator.

    .PARAMETER PagerDay
        Defines what days the pager portion of the operator will be used. The default is 'Everyday'. Valid parameters
        are 'EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', and
        'Saturday'.

    .PARAMETER SaturdayStartTime
        This a string that takes the Saturday Pager Start Time.

    .PARAMETER SaturdayEndTime
        This a string that takes the Saturday Pager End Time.

    .PARAMETER SundayStartTime
        This a string that takes the Sunday Pager Start Time.

    .PARAMETER SundayEndTime
        This a string that takes the Sunday Pager End Time.

    .PARAMETER WeekdayStartTime
        This a string that takes the Weekdays Pager Start Time.

    .PARAMETER WeekdayEndTime
        This a string that takes the Weekdays Pager End Time.

    .PARAMETER IsFailsafeOperator
        If this switch is enabled, this operator will be your failsafe operator and replace the one that existed before.

    .PARAMETER FailsafeNotificationMethod
        Defines the notification method(s) for the failsafe operator. The default is 'NotifyEmail'.
        Valid parameter values are 'None', 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll'.
        Values 'NotifyEmail', 'Pager', 'NetSend' can be specified in any combination.
        Values 'None' and 'NotifyAll' cannot be specified in conjunction with any other value.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        SMO Server Objects (pipeline input from Connect-DbaInstance)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Operator
        Author: Tracy Boggiano (@TracyBoggiano), databasesuperhero.com

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentOperator

    .EXAMPLE
        PS:\> Set-DbaAgentOperator -SqlInstance sql01 -Operator DBA -EmailAddress operator@operator.com -PagerDay Everyday

        This sets the operator named DBA with the above email address with default values to alerts everyday for all hours of the day.

    .EXAMPLE
        PS:\> Set-DbaAgentOperator -SqlInstance sql01 -Operator DBA -EmailAddress operator@operator.com -NetSendAddress dbauser1 -PagerAddress dbauser1@pager.dbatools.io -PagerDay Everyday -SaturdayStartTime 070000 -SaturdayEndTime 180000 -SundayStartTime 080000 -SundayEndTime 170000 -WeekdayStartTime 060000 -WeekdayEndTime 190000

        Creates a new operator named DBA on the sql01 instance with email address operator@operator.com, net send address of dbauser1, pager address of dbauser1@pager.dbatools.io, page day as every day, Saturday start time of 7am, Saturday end time of 6pm, Sunday start time of 8am, Sunday end time of 5pm, Weekday start time of 6am, and Weekday end time of 7pm.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Operator,
        [string]$Name,
        [string]$EmailAddress,
        [string]$NetSendAddress,
        [string]$PagerAddress,
        [ValidateSet('EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$PagerDay,
        [string]$SaturdayStartTime,
        [string]$SaturdayEndTime,
        [string]$SundayStartTime,
        [string]$SundayEndTime,
        [string]$WeekdayStartTime,
        [string]$WeekdayEndTime,
        [switch]$IsFailsafeOperator,
        [ValidateSet('None', 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll')]
        [string[]]$FailsafeNotificationMethod = 'NotifyEmail',
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Operator[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $PSBoundParameters.EmailAddress -and -not $PSBoundParameters.NetSendAddress -and -not $PSBoundParameters.PagerAddress) {
            Stop-Function -Message "You must specify either an EmailAddress, NetSendAddress, or a PagerAddress to be able to create an operator."
            return
        }

        if (-not $PSBoundParameters.InputObject -and -not $PSBoundParameters.Operator) {
            Stop-Function -Message "You must specify either operator or pipe in a list of operators"
            return
        }

        [int]$Interval = 0

        # Loop through the array
        foreach ($Item in $PagerDay) {
            switch ($Item) {
                "Sunday" { $Interval += 1 }
                "Monday" { $Interval += 2 }
                "Tuesday" { $Interval += 4 }
                "Wednesday" { $Interval += 8 }
                "Thursday" { $Interval += 16 }
                "Friday" { $Interval += 32 }
                "Saturday" { $Interval += 64 }
                "Weekdays" { $Interval = 62 }
                "Weekend" { $Interval = 65 }
                "EveryDay" { $Interval = 127 }
                1 { $Interval += 1 }
                2 { $Interval += 2 }
                4 { $Interval += 4 }
                8 { $Interval += 8 }
                16 { $Interval += 16 }
                32 { $Interval += 32 }
                64 { $Interval += 64 }
                62 { $Interval = 62 }
                65 { $Interval = 65 }
                127 { $Interval = 127 }
                default { $Interval = 0 }
            }
        }

        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'

        if ($PagerDay -in ('Everyday', 'Saturday', 'Weekends')) {
            # Check the start time
            if (-not $SaturdayStartTime) {
                $SaturdayStartTime = '000000'
                Write-Message -Message "Saturday Start time was not set. Setting it to $SaturdayStartTime" -Level Verbose
            } elseif ($SaturdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SaturdayStartTime needs to match between '000000' and '235959'"
                return
            }

            # Check the end time
            if (-not $SaturdayEndTime) {
                $SaturdayEndTime = '235959'
                Write-Message -Message "Saturday End time was not set. Setting it to $SaturdayEndTime" -Level Verbose
            } elseif ($SaturdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "End time $SaturdayEndTime needs to match between '000000' and '235959'"
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Sunday', 'Weekends')) {
            # Check the start time
            if (-not $SundayStartTime) {
                $SundayStartTime = '000000'
                Write-Message -Message "Sunday Start time was not set. Setting it to $SundayStartTime" -Level Verbose
            } elseif ($SundayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SundayStartTime needs to match between '000000' and '235959'"
                return
            }

            # Check the end time
            if (-not $SundayEndTime) {
                $SundayEndTime = '235959'
                Write-Message -Message "Sunday End time was not set. Setting it to $SundayEndTime" -Level Verbose
            } elseif ($SundayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Sunday End time $SundayEndTime needs to match between '000000' and '235959'"
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Weekdays', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) {
            # Check the start time
            if (-not $WeekdayStartTime) {
                $WeekdayStartTime = '000000'
                Write-Message -Message "Weekday Start time was not set. Setting it to $WeekdayStartTime" -Level Verbose
            } elseif ($WeekdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday Start time $WeekdayStartTime needs to match between '000000' and '235959'"
                return
            }

            # Check the end time
            if (-not $WeekdayEndTime) {
                $WeekdayEndTime = '235959'
                Write-Message -Message "Weekday End time was not set. Setting it to $WeekdayEndTime" -Level Verbose
            } elseif ($WeekdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday End time $WeekdayEndTime needs to match between '000000' and '235959'"
                return
            }
        }

        if ($IsFailsafeOperator -and ($FailsafeNotificationMethod.Count -gt 1 -and ($FailsafeNotificationMethod.Contains('None') -or $FailsafeNotificationMethod.Contains('NotifyAll')))) {
            Stop-Function -Message "The failsafe operator notification methods 'None' and 'NotifyAll' cannot be specified in conjunction with any other notification method."
            return
        } else {

            [int]$failsafeNotificationMethodEnumerated = 0

            if ($FailsafeNotificationMethod.Contains('NotifyAll')) {
                $failsafeNotificationMethodEnumerated += 7
            } else {

                if ($FailsafeNotificationMethod.Contains('NotifyEmail')) {
                    $failsafeNotificationMethodEnumerated += 1
                }

                if ($FailsafeNotificationMethod.Contains('Pager')) {
                    $failsafeNotificationMethodEnumerated += 2
                }

                if ($FailsafeNotificationMethod.Contains('NetSend')) {
                    $failsafeNotificationMethodEnumerated += 4
                }
            }

        }

        #Format times
        if ($SaturdayStartTime) {
            $SaturdayStartTime = $SaturdayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($SaturdayEndTime) {
            $SaturdayEndTime = $SaturdayEndTime.Insert(4, ':').Insert(2, ':')
        }

        if ($SundayStartTime) {
            $SundayStartTime = $SundayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($SundayEndTime) {
            $SundayEndTime = $SundayEndTime.Insert(4, ':').Insert(2, ':')
        }

        if ($WeekdayStartTime) {
            $WeekdayStartTime = $WeekdayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($WeekdayEndTime) {
            $WeekdayEndTime = $WeekdayEndTime.Insert(4, ':').Insert(2, ':')
        }

        if ($SqlInstance) {
            try {
                $InputObject += Get-DbaAgentOperator -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Operator $Operator -EnableException
            } catch {
                Stop-Function -Message "Failed" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }

        foreach ($op in $InputObject) {
            $server = $op | Get-ConnectionParent
            try {
                if ($Name) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) Name to $Name")) {
                        # instead of using .Rename(), we will execute a sql script to avoid enumeration problems when piping
                        $sql = "EXEC msdb.dbo.sp_update_operator @name=N'$($op.Name)', @new_name=N'$Name'"
                        try {
                            Invoke-DbaQuery -SqlInstance $server -Query "$sql" -EnableException
                        } catch {
                            Stop-Function -Message "Failed on $($server.name)" -ErrorRecord $_ -Target $server -Continue
                        }
                        $server.JobServer.Operators.Refresh()
                        $op = Get-DbaAgentOperator -SqlInstance $server -Operator $Name
                    }
                }

                if ($EmailAddress) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) EmailAddress to $EmailAddress")) {
                        $op.EmailAddress = $EmailAddress
                    }
                }

                if ($NetSendAddress) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) NetSendAddress to $NetSendAddress")) {
                        $op.NetSendAddress = $NetSendAddress
                    }
                }

                if ($PagerAddress) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) PagerAddress to $PagerAddress")) {
                        $op.PagerAddress = $PagerAddress
                    }
                }

                if ($Interval) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) PagerDays to $Interval")) {
                        $op.PagerDays = $Interval
                    }
                }

                if ($SaturdayStartTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SaturdayPagerStartTime to $SaturdayStartTime")) {
                        $op.SaturdayPagerStartTime = $SaturdayStartTime
                    }
                }

                if ($SaturdayEndTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SaturdayPagerEndTime to $SaturdayEndTime")) {
                        $op.SaturdayPagerEndTime = $SaturdayEndTime
                    }
                }

                if ($SundayStartTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SundayPagerStartTime to $SundayStartTime")) {
                        $op.SundayPagerStartTime = $SundayStartTime
                    }
                }

                if ($SundayEndTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SundayPagerEndTime to $SundayEndTime")) {
                        $op.SundayPagerEndTime = $SundayEndTime
                    }
                }

                if ($WeekdayStartTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) WeekdayPagerStartTime to $WeekdayStartTime")) {
                        $op.WeekdayPagerStartTime = $WeekdayStartTime
                    }
                }

                if ($WeekdayEndTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) WeekdayPagerEndTime to $WeekdayEndTime")) {
                        $op.WeekdayPagerEndTime = $WeekdayEndTime
                    }
                }

                if ($IsFailsafeOperator) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating FailSafe Operator to $operator")) {
                        $server.JobServer.AlertSystem.FailSafeOperator = $Operator
                        $server.JobServer.AlertSystem.NotificationMethod = $failsafeNotificationMethodEnumerated
                        $server.JobServer.AlertSystem.Alter()
                    }
                }

                if ($Pscmdlet.ShouldProcess($server, "Committing changes for Operator $($op.Name)")) {
                    $op.Alter()
                    $op
                }
            } catch {
                Stop-Function -Message "Issue creating operator." -Category InvalidOperation -ErrorRecord $_ -Target $server
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUDzZTUWBnY8Mr4C8xrbNxlQrG
# l0CgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFF8tUZhN1r6CB5ndG1IJ91xpg9l7MA0G
# CSqGSIb3DQEBAQUABIIBAFQ16TGcSuKusWY8xeW9sQ25JO4+h/SKdTjXPTA9KgKl
# jG1ISGs3AFIbzR1Icjm/Gowuh5tBKzIHpiT1xLQo7cKhiIy+Fd6ZaMmMcfa4lB1o
# E/r5CtKBPhbn1zmiHj2XD6DnPsh/kVbAUQ5BUUVHongVFYTbX/QSsA7QqwksQgzf
# A22NPQ6KmAc/jxC7quJVvB1s/KTeAG8R/jFFnTN7CrPad8vH8Id7WZA5YxaQ0wtm
# Bs1MiNboPa+iPH2/94tzxilebvRHI1Sp5MvdlR3LLoneoxgMVO8/2N4u6F2C5Y+8
# mN7uykQI0S3ZnLNof1YQJ7nsPP3nF06lYa14i8m+kiChggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDE4WjAvBgkqhkiG9w0BCQQxIgQgj5MVK0CVzywVS9dpuFnL
# NPuHOLOhNVyMyEKkGZoTomgwDQYJKoZIhvcNAQEBBQAEggIAiCkPkW7OaDC16CkZ
# i1WRB7Zxc20rEswg/KRnDY9vu1wxCU+PqAutYzspQ/scEXITiB0dc3cvsJKcFNem
# fv07rzMjobCIk6oAP7gKURzn4P3nKuu1wkkrI5/JmWhqMvGT+Bj8k5ge2HqtJaLc
# oAeL3zXIhcy+J97uUo2eOvcO56CTPww5SR/RzlSghlY+hm7cNELVltPF2rjTBdt8
# 17H+v0+jpA/SXYb4vHKYZj7Ia71Uw+YcERcoAo1I59sYeErEpzfyn8YRRQVDrBx2
# /G/MiH+x62myS0ZHfc1Fy0RrnA6z1b+Kcy675y0sdm1Yc0Jyzvm7r11SW6B9Ow0t
# sxHNko079PufE8w27RGAbIhQQGhTBLWYodXW98MsrsrMxJ+ZeT1pfRI0rXrxzW80
# PQiykXPnKiI2lCBbqTj9GMcKSnRkGThYq8CKoI292mng/HWVxXbk0d3043pTmKU+
# L/qxKKQ+uWzkIGFNIbX1Vhr7BtNA6yKrxZBVDB2jP7prAH1K3M5yrTxwIiATnm4Q
# uvSS4tqdo/gkMO8nwCkx+no5m0rzS1kdWEbxa617JXNxuXIWUxzQRjkyzDXy+ssJ
# ie6GqbqjSBndScus6D+/10dfa+jN2SGgGhTYok8pfI/gYajpPfosDqht8hlP1NUl
# 0tJhWjq/hBzOT+S0Sqw/DqZiNF8=
# SIG # End signature block
