function Get-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Returns all SQL Agent Shared Schedules on a SQL Server Agent.

    .DESCRIPTION
        This function returns SQL Agent Shared Schedules.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Schedule
        Parameter to filter the schedules returned

    .PARAMETER ScheduleUid
        The unique identifier of the schedule

    .PARAMETER Id
        Parameter to filter the schedules returned

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Schedule
        Author: Chris McKeown (@devopsfu), http://www.devopsfu.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentSchedule

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost

        Returns all SQL Agent Shared Schedules on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016

        Returns all SQL Agent Shared Schedules for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016 -Id 3

        Returns the SQL Agent Shared Schedules with the Id of 3

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016 -ScheduleUid 'bf57fa7e-7720-4936-85a0-87d279db7eb7'

        Returns the SQL Agent Shared Schedules with the UID

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance sql2016 -Schedule "Maintenance10min","Maintenance60min"

        Returns the "Maintenance10min" & "Maintenance60min" schedules from the sql2016 SQL Server instance
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Schedule,
        [string[]]$ScheduleUid,
        [int[]]$Id,
        [switch]$EnableException
    )

    begin {
        function Get-ScheduleDescription {
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [object]$currentschedule

            )

            # Get the culture to make sure the right date and time format is displayed
            $datetimeFormat = (Get-Culture).DateTimeFormat

            # Set the intial description
            $description = ""

            # Get the date and time values
            $startDate = Get-Date $currentschedule.ActiveStartDate -format $datetimeFormat.ShortDatePattern
            $startTime = Get-Date ($currentschedule.ActiveStartTimeOfDay.ToString()) -format $datetimeFormat.LongTimePattern
            $endDate = Get-Date $currentschedule.ActiveEndDate -format $datetimeFormat.ShortDatePattern
            $endTime = Get-Date ($currentschedule.ActiveEndTimeOfDay.ToString()) -format $datetimeFormat.LongTimePattern

            # Start setting the description based on the frequency type
            switch ($currentschedule.FrequencyTypes) {
                { ($_ -eq 1) -or ($_ -eq "Once") } { $description += "Occurs on $startDate at $startTime" }
                { ($_ -in 4, 8, 16, 32) -or ($_ -in "Daily", "Weekly", "Monthly") } { $description += "Occurs every " }
                { ($_ -eq 64) -or ($_ -eq "AutoStart") } { $description += "Start automatically when SQL Server Agent starts " }
                { ($_ -eq 128) -or ($_ -eq "OnIdle") } { $description += "Start whenever the CPUs become idle" }
            }

            # Check the frequency types for daily or weekly i.e.
            switch ($currentschedule.FrequencyTypes) {
                # Daily
                { $_ -in 4, "Daily" } {
                    if ($currentschedule.FrequencyInterval -eq 1) {
                        $description += "day "
                    } elseif ($currentschedule.FrequencyInterval -gt 1) {
                        $description += "$($currentschedule.FrequencyInterval) day(s) "
                    }
                }

                # Weekly
                { $_ -in 8, "Weekly" } {
                    # Check if it's for one or more weeks
                    if ($currentschedule.FrequencyRecurrenceFactor -eq 1) {
                        $description += "week on "
                    } elseif ($currentschedule.FrequencyRecurrenceFactor -gt 1) {
                        $description += "$($currentschedule.FrequencyRecurrenceFactor) week(s) on "
                    }

                    # Save the interval for the loop
                    $frequencyInterval = $currentschedule.FrequencyInterval

                    # Create the array to hold the days
                    $days = ($false, $false, $false, $false, $false, $false, $false)

                    # Loop through the days
                    while ($frequencyInterval -gt 0) {

                        switch ($FrequenctInterval) {
                            { ($frequencyInterval - 64) -ge 0 } {
                                $days[5] = "Saturday"
                                $frequencyInterval -= 64
                            }
                            { ($frequencyInterval - 32) -ge 0 } {
                                $days[4] = "Friday"
                                $frequencyInterval -= 32
                            }
                            { ($frequencyInterval - 16) -ge 0 } {
                                $days[3] = "Thursday"
                                $frequencyInterval -= 16
                            }
                            { ($frequencyInterval - 8) -ge 0 } {
                                $days[2] = "Wednesday"
                                $frequencyInterval -= 8
                            }
                            { ($frequencyInterval - 4) -ge 0 } {
                                $days[1] = "Tuesday"
                                $frequencyInterval -= 4
                            }
                            { ($frequencyInterval - 2) -ge 0 } {
                                $days[0] = "Monday"
                                $frequencyInterval -= 2
                            }
                            { ($frequencyInterval - 1) -ge 0 } {
                                $days[6] = "Sunday"
                                $frequencyInterval -= 1
                            }
                        }

                    }

                    # Add the days to the description by selecting the days and exploding the array
                    $description += ($days | Where-Object { $_ -ne $false }) -join ", "
                    $description += " "

                }

                # Monthly
                { $_ -in 16, "Monthly" } {
                    # Check if it's for one or more months
                    if ($currentschedule.FrequencyRecurrenceFactor -eq 1) {
                        $description += "month "
                    } elseif ($currentschedule.FrequencyRecurrenceFactor -gt 1) {
                        $description += "$($currentschedule.FrequencyRecurrenceFactor) month(s) "
                    }

                    # Add the interval
                    $description += "on day $($currentschedule.FrequencyInterval) of that month "
                }

                # Monthly relative
                { $_ -in 32, "MonthlyRelative" } {
                    # Check for the relative day
                    switch ($currentschedule.FrequencyRelativeIntervals) {
                        { $_ -in 1, "First" } { $description += "first " }
                        { $_ -in 2, "Second" } { $description += "second " }
                        { $_ -in 4, "Third" } { $description += "third " }
                        { $_ -in 8, "Fourth" } { $description += "fourth " }
                        { $_ -in 16, "Last" } { $description += "last " }
                    }

                    # Get the relative day of the week
                    switch ($currentschedule.FrequencyInterval) {
                        1 { $description += "Sunday " }
                        2 { $description += "Monday " }
                        3 { $description += "Tuesday " }
                        4 { $description += "Wednesday " }
                        5 { $description += "Thursday " }
                        6 { $description += "Friday " }
                        7 { $description += "Saturday " }
                        8 { $description += "Day " }
                        9 { $description += "Weekday " }
                        10 { $description += "Weekend day " }
                    }

                    $description += "of every $($currentschedule.FrequencyRecurrenceFactor) month(s) "

                }
            }

            # Check the frequency type
            if ($currentschedule.FrequencyTypes -notin 64, 128) {

                # Check the subday types for minutes or hours i.e.
                if ($currentschedule.FrequencySubDayInterval -in 0, 1) {
                    $description += "at $startTime. "
                } else {

                    switch ($currentschedule.FrequencySubDayTypes) {
                        { $_ -in 2, "Seconds" } { $description += "every $($currentschedule.FrequencySubDayInterval) second(s) " }
                        { $_ -in 4, "Minutes" } { $description += "every $($currentschedule.FrequencySubDayInterval) minute(s) " }
                        { $_ -in 8, "Hours" } { $description += "every $($currentschedule.FrequencySubDayInterval) hour(s) " }
                    }

                    $description += "between $startTime and $endTime. "
                }

                # Check if an end date has been given
                if ($currentschedule.ActiveEndDate.Year -eq 9999) {
                    $description += "Schedule will be used starting on $startDate."
                } else {
                    $description += "Schedule will used between $startDate and $endDate."
                }
            }

            return $description
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "$($server.Edition) does not support SQL Server Agent. Skipping $server." -Continue
            }

            $scheduleCollection = @()

            if ($Schedule -or $ScheduleUid -or $Id) {
                if ($Schedule) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.Name -in $Schedule }
                }

                if ($ScheduleUid) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.ScheduleUid -in $ScheduleUid }
                }

                if ($Id) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.Id -in $Id }
                }
            } else {
                $scheduleCollection = $server.JobServer.SharedSchedules
            }

            $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name as ScheduleName", "ActiveEndDate", "ActiveEndTimeOfDay", "ActiveStartDate", "ActiveStartTimeOfDay", "DateCreated", "FrequencyInterval", "FrequencyRecurrenceFactor", "FrequencyRelativeIntervals", "FrequencySubDayInterval", "FrequencySubDayTypes", "FrequencyTypes", "IsEnabled", "JobCount", "Description", "ScheduleUid"

            foreach ($currentschedule in $scheduleCollection) {
                $description = Get-ScheduleDescription -CurrentSchedule $currentschedule

                $currentschedule | Add-Member -Type NoteProperty -Name ComputerName -Value $server.ComputerName -Force
                $currentschedule | Add-Member -Type NoteProperty -Name InstanceName -Value $server.ServiceName -Force
                $currentschedule | Add-Member -Type NoteProperty -Name SqlInstance -Value $server.DomainInstanceName -Force
                $currentschedule | Add-Member -Type NoteProperty -Name Description -Value $description -Force

                Select-DefaultView -InputObject $currentschedule -Property $defaults
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUAet8rKprGykbqFDID5ofqU8l
# zHagghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPiTv7PW4F+9gqopKDtqeEdLxrZbMA0G
# CSqGSIb3DQEBAQUABIIBAHvfyH7UFcAy7XLSntpz5hoIhLYLeI9uwXw4VDikjebR
# IRUoxFzTJi2tfZDNWMbSL5UX1Owfx+252JUg7vAfaQP0X7MC+JMszBNOKuqaetsZ
# 3Ho4JdD5J74Qag2lJ4w22/oOx5zYp0OIYK1iEGfmoynSgnSu9266672NKTRGkaRI
# yvm7oGF50gamX4J4AAwoRp2fzbU7ejXSzZvCN3bl+bKogQ7QreCt65vo/RLD0SOv
# X8h3lGrEwHsIQzqPZwW/GWsFl+bkl285EYpq4QDjbr2cphmkJyBU02w69qb4A0oV
# oUo7eGfPy+uVhr1jrj/YlochU8ZQMoJUm9lPzBMZDZ+hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzI0WjAvBgkqhkiG9w0BCQQxIgQgnhHUEP128P3m9mI979XH
# eL6vc4BZRhbEgz1kGKmnxj0wDQYJKoZIhvcNAQEBBQAEggIARbjIdHSWur19iuXG
# 75CDwWVPaBZP62AQom7K0wnCCgeQKWu2pytJ3LQpgGA6ZYVkcVAMTYChiJ2GU87s
# v1p6jRdhuO/73/NSOxpIyk2NXaSqku6Q1HKj1bilb5r2GEyfnOKNGMiZAZDjh4z0
# ASZfsjkC/63ysnP49AIx1ydVpd7GAnvQR+FAXnf4TrU5bCmKsd79Y0Ww7UKQdWqS
# BvL1TRAezgV4tzW2RfvqpDFkqo/BLlnW1gHwD0znQ3WOTBGsGQuF0eEZ1zUjZr9X
# Z4XbQra6gTeKHlMnqZ6Uvum105Hwkjsv038mmYBYb64XFcUioqRzT+9po6/b7mca
# w3dKicDj2cMIqW/3DgDoF9Ipu76XS+NfAcRsrKzk9wDqju6DzSV1ELxyHnMpurkr
# zFSODTAAzARNkmmY5NAvRUU6ncgXPpYfYkfKa+yflhJsuQQtW/a6kYAT6ftPy8UQ
# +EaNmVXQ/YVlxXAEJpa/8g89iHL+quTcHtce/mXtBAwtEakecR9JxxXUuhFvzBNC
# eL5ALYwym3wwN8PYfadrg5MAVVwywfXYF+3s6lOCHkyfcdmr4kQqby7hRom9dp1a
# ZgqeGe/I6+8pnzpjyboReB7HCCw7HaH5U9HxL2GJmrsNWZGCtlbxe+svP1euDT1l
# FVG16E6OA+v3pOPnPaaiB5Qb3bo=
# SIG # End signature block
