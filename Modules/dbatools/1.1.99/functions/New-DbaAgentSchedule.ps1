function New-DbaAgentSchedule {
    <#
    .SYNOPSIS
        New-DbaAgentSchedule creates a new schedule in the msdb database.

    .DESCRIPTION
        New-DbaAgentSchedule will help create a new schedule for a job.
        If the job parameter is not supplied the schedule will not be attached to a job.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job that has the schedule.

    .PARAMETER Schedule
        The name of the schedule.

    .PARAMETER Disabled
        Set the schedule to disabled. Default is enabled

    .PARAMETER FrequencyType
        A value indicating when a job is to be executed.

        Allowed values: 'Once', 'OneTime', 'Daily', 'Weekly', 'Monthly', 'MonthlyRelative', 'AgentStart', 'AutoStart', 'IdleComputer', 'OnIdle'

        The following synonyms provide flexibility to the allowed values for this function parameter:
        Once=OneTime
        AgentStart=AutoStart
        IdleComputer=OnIdle

        If force is used the default will be "Once".

    .PARAMETER FrequencyInterval
        The days that a job is executed

        Allowed values for FrequencyType 'Daily': EveryDay or a number between 1 and 365.
        Allowed values for FrequencyType 'Weekly': Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Weekdays, Weekend or EveryDay.
        Allowed values for FrequencyType 'Monthly': Numbers 1 to 31 for each day of the month.

        If "Weekdays", "Weekend" or "EveryDay" is used it over writes any other value that has been passed before.

        If force is used the default will be 1.

    .PARAMETER FrequencySubdayType
        Specifies the units for the subday FrequencyInterval.

        Allowed values: 'Once', 'Time', 'Seconds', 'Second', 'Minutes', 'Minute', 'Hours', 'Hour'

        The following synonyms provide flexibility to the allowed values for this function parameter:
        Once=Time
        Seconds=Second
        Minutes=Minute
        Hours=Hour

    .PARAMETER FrequencySubdayInterval
        The number of subday type periods to occur between each execution of a job.

    .PARAMETER FrequencyRelativeInterval
        A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

        Allowed values: First, Second, Third, Fourth or Last

    .PARAMETER FrequencyRecurrenceFactor
        The number of weeks or months between the scheduled execution of a job.

        FrequencyRecurrenceFactor is used only if FrequencyType is "Weekly", "Monthly" or "MonthlyRelative".

    .PARAMETER StartDate
        The date on which execution of a job can begin.

        If force is used the start date will be the current day

    .PARAMETER EndDate
        The date on which execution of a job can stop.

        If force is used the end date will be '9999-12-31'

    .PARAMETER StartTime
        The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

        If force is used the start time will be '00:00:00'

    .PARAMETER EndTime
        The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

        If force is used the start time will be '23:59:59'

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.
        It will also remove the any present schedules with the same name for the specific job.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job, JobStep
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAgentSchedule

    .EXAMPLE
        PS C:\> New-DbaAgentSchedule -SqlInstance sql01 -Schedule DailyAt6 -FrequencyType Daily -StartTime "060000" -Force

        Creates a schedule that runs jobs every day at 6 in the morning. It assumes default values for the start date, start time, end date and end time due to -Force.

    .EXAMPLE
        PS C:\> New-DbaAgentSchedule -SqlInstance localhost\SQL2016 -Schedule daily -FrequencyType Daily -FrequencyInterval Everyday -Force

        Creates a schedule with a daily frequency every day. It assumes default values for the start date, start time, end date and end time due to -Force.

    .EXAMPLE
        PS C:\> New-DbaAgentSchedule -SqlInstance sstad-pc -Schedule MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force

        Create a schedule with a monhtly frequency occuring every 10th of the month. It assumes default values for the start date, start time, end date and end time due to -Force.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [object]$Schedule,
        [switch]$Disabled,
        [ValidateSet('Once', 'OneTime', 'Daily', 'Weekly', 'Monthly', 'MonthlyRelative', 'AgentStart', 'AutoStart', 'IdleComputer', 'OnIdle')]
        [object]$FrequencyType,
        [object[]]$FrequencyInterval,
        [ValidateSet('Once', 'Time', 'Seconds', 'Second', 'Minutes', 'Minute', 'Hours', 'Hour')]
        [object]$FrequencySubdayType,
        [int]$FrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$FrequencyRelativeInterval,
        [int]$FrequencyRecurrenceFactor,
        [string]$StartDate,
        [string]$EndDate,
        [string]$StartTime,
        [string]$EndTime,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($FrequencyType -eq "Daily" -and -not $FrequencyInterval) {
            $FrequencyInterval = 1
        }

        # if a Schedule is not provided there is no much point
        if (-not $Schedule) {
            Stop-Function -Message "A schedule was not provided! Please provide a schedule name."
            return
        }

        [int]$interval = 0

        # Translate FrequencyType value from string to the integer value
        [int]$FrequencyType =
        switch ($FrequencyType) {
            "Once" { 1 }
            "OneTime" { 1 }
            "Daily" { 4 }
            "Weekly" { 8 }
            "Monthly" { 16 }
            "MonthlyRelative" { 32 }
            "AgentStart" { 64 }
            "AutoStart" { 64 }
            "IdleComputer" { 128 }
            "OnIdle" { 128 }
            default { 1 }
        }

        # Translate FrequencySubdayType value from string to the integer value
        [int]$FrequencySubdayType =
        switch ($FrequencySubdayType) {
            "Once" { 1 }
            "Time" { 1 }
            "Seconds" { 2 }
            "Second" { 2 }
            "Minutes" { 4 }
            "Minute" { 4 }
            "Hours" { 8 }
            "Hour" { 8 }
            default { 1 }
        }

        # Check if the relative FrequencyInterval value is of type string and set the integer value
        [int]$FrequencyRelativeInterval =
        switch ($FrequencyRelativeInterval) {
            "First" { 1 }
            "Second" { 2 }
            "Third" { 4 }
            "Fourth" { 8 }
            "Last" { 16 }
            "Unused" { 0 }
            default { 0 }
        }

        # Check if the interval for daily frequency is valid
        if (($FrequencyType -eq 4) -and ($FrequencyInterval -lt 1 -or $FrequencyInterval -ge 365) -and (-not ($FrequencyInterval -eq "EveryDay")) -and (-not $Force)) {
            Stop-Function -Message "The daily frequency type requires a frequency interval to be between 1 and 365 or 'EveryDay'." -Target $SqlInstance
            return
        }

        # Check if the recurrence factor is set for weekly or monthly interval
        if (($FrequencyType -in (16, 8)) -and $FrequencyRecurrenceFactor -lt 1) {
            if ($Force) {
                $FrequencyRecurrenceFactor = 1
                Write-Message -Message "Recurrence factor not set for weekly or monthly interval. Setting it to $FrequencyRecurrenceFactor." -Level Verbose
            } else {
                Stop-Function -Message "The recurrence factor $FrequencyRecurrenceFactor (parameter FrequencyRecurrenceFactor) needs to be at least one when using a weekly or monthly interval." -Target $SqlInstance
                return
            }
        }

        # Check the subday interval
        if (($FrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($FrequencySubdayInterval -ge 1 -or $FrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 59 when subday type is 'Seconds' or 'Minutes'" -Target $SqlInstance
            return
        } elseif (($FrequencySubdayType -eq 8, "Hours") -and (-not ($FrequencySubdayInterval -ge 1 -and $FrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 23 when subday type is 'Hours'" -Target $SqlInstance
            return
        }

        # If the FrequencyInterval is set for the daily FrequencyType
        if ($FrequencyType -eq 4) {
            # Create the interval to hold the value(s)
            [int]$interval = 1

            if ($FrequencyInterval -and $FrequencyInterval[0].GetType().Name -eq 'Int32') {
                $interval = $FrequencyInterval[0]
            }
        }

        # If the FrequencyInterval is set for the weekly FrequencyType
        if ($FrequencyType -in 8, 'Weekly') {
            # Create the interval to hold the value(s)
            [int]$interval = 0

            # Loop through the array
            foreach ($item in $FrequencyInterval) {

                switch ($item) {
                    "Sunday" { $interval += 1 }
                    "Monday" { $interval += 2 }
                    "Tuesday" { $interval += 4 }
                    "Wednesday" { $interval += 8 }
                    "Thursday" { $interval += 16 }
                    "Friday" { $interval += 32 }
                    "Saturday" { $interval += 64 }
                    "Weekdays" { $interval = 62 }
                    "Weekend" { $interval = 65 }
                    "EveryDay" { $interval = 127 }
                    1 { $interval += 1 }
                    2 { $interval += 2 }
                    4 { $interval += 4 }
                    8 { $interval += 8 }
                    16 { $interval += 16 }
                    32 { $interval += 32 }
                    64 { $interval += 64 }
                    62 { $interval = 62 }
                    65 { $interval = 65 }
                    127 { $interval = 127 }
                    default { $interval = 0 }
                }
            }
        }

        # If the FrequencyInterval is set for the monthly FrequencyInterval
        if ($FrequencyType -in 16, 'Monthly') {
            # Create the interval to hold the value(s)
            [int]$interval = 0

            # Loop through the array
            foreach ($item in $FrequencyInterval) {
                switch ($item) {
                    { [int]$_ -ge 1 -and [int]$_ -le 31 } { $interval = [int]$item }
                }
            }
        }

        # If the FrequencyInterval is set for the relative monthly FrequencyInterval
        if ($FrequencyType -eq 32) {
            # Create the interval to hold the value(s)
            [int]$interval = 0

            # Loop through the array
            foreach ($item in $FrequencyInterval) {
                switch ($item) {
                    "Sunday" { $interval += 1 }
                    "Monday" { $interval += 2 }
                    "Tuesday" { $interval += 3 }
                    "Wednesday" { $interval += 4 }
                    "Thursday" { $interval += 5 }
                    "Friday" { $interval += 6 }
                    "Saturday" { $interval += 7 }
                    "Day" { $interval += 8 }
                    "Weekday" { $interval += 9 }
                    "WeekendDay" { $interval += 10 }
                    1 { $interval += 1 }
                    2 { $interval += 2 }
                    3 { $interval += 3 }
                    4 { $interval += 4 }
                    5 { $interval += 5 }
                    6 { $interval += 6 }
                    7 { $interval += 7 }
                    8 { $interval += 8 }
                    9 { $interval += 9 }
                    10 { $interval += 10 }
                }
            }
        }

        # Check if the interval is valid for the frequency
        if ($FrequencyType -eq 0) {
            if ($Force) {
                Write-Message -Message "Parameter FrequencyType must be set to at least [Once]. Setting it to 'Once'." -Level Warning
                $FrequencyType = 1
            } else {
                Stop-Function -Message "Parameter FrequencyType must be set to at least [Once]" -Target $SqlInstance
                return
            }
        }

        # Check if the interval is valid for the frequency
        if (($FrequencyType -in 4, 8, 32) -and ($interval -lt 1)) {
            if ($Force) {
                Write-Message -Message "Parameter FrequencyInterval must be provided for a recurring schedule. Setting it to first day of the week." -Level Warning
                $interval = 1
            } else {
                Stop-Function -Message "Parameter FrequencyInterval must be provided for a recurring schedule." -Target $SqlInstance
                return
            }
        }

        # Setup the regex
        $RegexDate = '(?<!\d)(?:(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:(?:0[13578]|1[02])31)|(?:(?:0[1,3-9]|1[0-2])(?:29|30)))|(?:(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00)))0229)|(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:0?[1-9])|(?:1[0-2]))(?:0?[1-9]|1\d|2[0-8]))(?!\d)'
        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'

        # Check the start date
        if (-not $StartDate -and $Force) {
            $StartDate = Get-Date -Format 'yyyyMMdd'
            Write-Message -Message "Start date was not set. Force is being used. Setting it to $StartDate" -Level Verbose
        } elseif (-not $StartDate) {
            Stop-Function -Message "Please enter a start date or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($StartDate -notmatch $RegexDate) {
            Stop-Function -Message "Start date $StartDate needs to be a valid date with format yyyyMMdd" -Target $SqlInstance
            return
        }

        # Check the end date
        if (-not $EndDate -and $Force) {
            $EndDate = '99991231'
            Write-Message -Message "End date was not set. Force is being used. Setting it to $EndDate" -Level Verbose
        } elseif (-not $EndDate) {
            Stop-Function -Message "Please enter an end date or use -Force to use defaults." -Target $SqlInstance
            return
        }

        elseif ($EndDate -notmatch $RegexDate) {
            Stop-Function -Message "End date $EndDate needs to be a valid date with format yyyyMMdd" -Target $SqlInstance
            return
        } elseif ($EndDate -lt $StartDate) {
            Stop-Function -Message "End date $EndDate cannot be before start date $StartDate" -Target $SqlInstance
            return
        }

        # Check the start time
        if (-not $StartTime -and $Force) {
            $StartTime = '000000'
            Write-Message -Message "Start time was not set. Force is being used. Setting it to $StartTime" -Level Verbose
        } elseif (-not $StartTime) {
            Stop-Function -Message "Please enter a start time or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($StartTime -notmatch $RegexTime) {
            Stop-Function -Message "Start time $StartTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        # Check the end time
        if (-not $EndTime -and $Force) {
            $EndTime = '235959'
            Write-Message -Message "End time was not set. Force is being used. Setting it to $EndTime" -Level Verbose
        } elseif (-not $EndTime) {
            Stop-Function -Message "Please enter an end time or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($EndTime -notmatch $RegexTime) {
            Stop-Function -Message "End time $EndTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        #Format dates and times
        if ($StartDate) {
            $StartDate = $StartDate.Insert(6, '-').Insert(4, '-')
        }
        if ($EndDate) {
            $EndDate = $EndDate.Insert(6, '-').Insert(4, '-')
        }
        if ($StartTime) {
            $StartTime = $StartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($EndTime) {
            $EndTime = $EndTime.Insert(4, ':').Insert(2, ':')
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check if the jobs parameter is set
            if ($Job) {
                # Loop through each of the jobs
                foreach ($j in $Job) {

                    # Check if the job exists
                    if ($Server.JobServer.Jobs.Name -notcontains $j) {
                        Write-Message -Message "Job $j doesn't exists on $instance" -Level Warning
                    } else {
                        # Create the job schedule object
                        try {
                            # Get the job
                            $smoJob = $Server.JobServer.Jobs[$j]

                            # Check if schedule already exists with the same name
                            if ($Server.JobServer.JobSchedules.Name -contains $Schedule) {
                                # Check if force is set which will remove the other schedule
                                if ($Force) {
                                    if ($PSCmdlet.ShouldProcess($instance, "Removing the schedule $Schedule on $instance")) {
                                        # Removing schedule
                                        Remove-DbaAgentSchedule -SqlInstance $instance -SqlCredential $SqlCredential -Schedule $Schedule -Force:$Force -Confirm:$false
                                    }
                                } else {
                                    Stop-Function -Message "Schedule $Schedule already exists for job $j on instance $instance" -Target $instance -ErrorRecord $_ -Continue
                                }
                            }

                            # Create the job schedule
                            $JobSchedule = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobSchedule($smoJob, $Schedule)

                        } catch {
                            Stop-Function -Message "Something went wrong creating the job schedule $Schedule for job $j." -Target $instance -ErrorRecord $_ -Continue
                        }

                        #region job schedule options
                        if ($Disabled) {
                            Write-Message -Message "Setting job schedule to disabled" -Level Verbose
                            $JobSchedule.IsEnabled = $false
                        } else {
                            Write-Message -Message "Setting job schedule to enabled" -Level Verbose
                            $JobSchedule.IsEnabled = $true
                        }

                        if ($interval -ge 0) {
                            Write-Message -Message "Setting job schedule frequency interval to $interval" -Level Verbose
                            $JobSchedule.FrequencyInterval = $interval
                        }

                        if ($FrequencyType -ge 1) {
                            Write-Message -Message "Setting job schedule frequency to $FrequencyType" -Level Verbose
                            $JobSchedule.FrequencyTypes = $FrequencyType
                        }

                        if ($FrequencySubdayType -ge 1) {
                            Write-Message -Message "Setting job schedule frequency subday type to $FrequencySubdayType" -Level Verbose
                            $JobSchedule.FrequencySubDayTypes = $FrequencySubdayType
                        }

                        if ($FrequencySubdayInterval -ge 1) {
                            Write-Message -Message "Setting job schedule frequency subday interval to $FrequencySubdayInterval" -Level Verbose
                            $JobSchedule.FrequencySubDayInterval = $FrequencySubdayInterval
                        }

                        if (($FrequencyRelativeInterval -ge 1) -and ($FrequencyType -eq 32)) {
                            Write-Message -Message "Setting job schedule frequency relative interval to $FrequencyRelativeInterval" -Level Verbose
                            $JobSchedule.FrequencyRelativeIntervals = $FrequencyRelativeInterval
                        }

                        if (($FrequencyRecurrenceFactor -ge 1) -and ($FrequencyType -in 8, 16, 32)) {
                            Write-Message -Message "Setting job schedule frequency recurrence factor to $FrequencyRecurrenceFactor" -Level Verbose
                            $JobSchedule.FrequencyRecurrenceFactor = $FrequencyRecurrenceFactor
                        }

                        if ($StartDate) {
                            Write-Message -Message "Setting job schedule start date to $StartDate" -Level Verbose
                            $JobSchedule.ActiveStartDate = $StartDate
                        }

                        if ($EndDate) {
                            Write-Message -Message "Setting job schedule end date to $EndDate" -Level Verbose
                            $JobSchedule.ActiveEndDate = $EndDate
                        }

                        if ($StartTime) {
                            Write-Message -Message "Setting job schedule start time to $StartTime" -Level Verbose
                            $JobSchedule.ActiveStartTimeOfDay = $StartTime
                        }

                        if ($EndTime) {
                            Write-Message -Message "Setting job schedule end time to $EndTime" -Level Verbose
                            $JobSchedule.ActiveEndTimeOfDay = $EndTime
                        }
                        #endregion job schedule options

                        # Create the schedule
                        if ($PSCmdlet.ShouldProcess($SqlInstance, "Adding the schedule $Schedule to job $j on $instance")) {
                            try {
                                Write-Message -Message "Adding the schedule $Schedule to job $j" -Level Verbose
                                #$JobSchedule
                                $JobSchedule.Create()

                                Write-Message -Message "Job schedule created with UID $($JobSchedule.ScheduleUid)" -Level Verbose
                            } catch {
                                Stop-Function -Message "Something went wrong adding the schedule" -Target $instance -ErrorRecord $_ -Continue

                            }

                            Add-TeppCacheItem -SqlInstance $server -Type schedule -Name $Schedule

                            # Output the job schedule
                            Get-DbaAgentSchedule -SqlInstance $server -ScheduleUid $JobSchedule.ScheduleUid
                        }
                    }
                } # foreach object job
            } # end if job
            else {
                # Create the schedule
                $JobSchedule = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobSchedule($Server.JobServer, $Schedule)

                #region job schedule options
                if ($Disabled) {
                    Write-Message -Message "Setting job schedule to disabled" -Level Verbose
                    $JobSchedule.IsEnabled = $false
                } else {
                    Write-Message -Message "Setting job schedule to enabled" -Level Verbose
                    $JobSchedule.IsEnabled = $true
                }

                if ($interval -ge 1) {
                    Write-Message -Message "Setting job schedule frequency interval to $interval" -Level Verbose
                    $JobSchedule.FrequencyInterval = $interval
                }

                if ($FrequencyType -ge 1) {
                    Write-Message -Message "Setting job schedule frequency to $FrequencyType" -Level Verbose
                    $JobSchedule.FrequencyTypes = $FrequencyType
                }

                if ($FrequencySubdayType -ge 1) {
                    Write-Message -Message "Setting job schedule frequency subday type to $FrequencySubdayType" -Level Verbose
                    $JobSchedule.FrequencySubDayTypes = $FrequencySubdayType
                }

                if ($FrequencySubdayInterval -ge 1) {
                    Write-Message -Message "Setting job schedule frequency subday interval to $FrequencySubdayInterval" -Level Verbose
                    $JobSchedule.FrequencySubDayInterval = $FrequencySubdayInterval
                }

                if (($FrequencyRelativeInterval -ge 1) -and ($FrequencyType -eq 32)) {
                    Write-Message -Message "Setting job schedule frequency relative interval to $FrequencyRelativeInterval" -Level Verbose
                    $JobSchedule.FrequencyRelativeIntervals = $FrequencyRelativeInterval
                }

                if (($FrequencyRecurrenceFactor -ge 1) -and ($FrequencyType -in 8, 16, 32)) {
                    Write-Message -Message "Setting job schedule frequency recurrence factor to $FrequencyRecurrenceFactor" -Level Verbose
                    $JobSchedule.FrequencyRecurrenceFactor = $FrequencyRecurrenceFactor
                }

                if ($StartDate) {
                    Write-Message -Message "Setting job schedule start date to $StartDate" -Level Verbose
                    $JobSchedule.ActiveStartDate = $StartDate
                }

                if ($EndDate) {
                    Write-Message -Message "Setting job schedule end date to $EndDate" -Level Verbose
                    $JobSchedule.ActiveEndDate = $EndDate
                }

                if ($StartTime) {
                    Write-Message -Message "Setting job schedule start time to $StartTime" -Level Verbose
                    $JobSchedule.ActiveStartTimeOfDay = $StartTime
                }

                if ($EndTime) {
                    Write-Message -Message "Setting job schedule end time to $EndTime" -Level Verbose
                    $JobSchedule.ActiveEndTimeOfDay = $EndTime
                }

                # Create the schedule
                if ($PSCmdlet.ShouldProcess($SqlInstance, "Adding the schedule $schedule on $instance")) {
                    try {
                        Write-Message -Message "Adding the schedule $JobSchedule on instance $instance" -Level Verbose

                        $JobSchedule.Create()

                        Write-Message -Message "Job schedule created with UID $($JobSchedule.ScheduleUid)" -Level Verbose
                    } catch {
                        Stop-Function -Message "Something went wrong adding the schedule." -Target $instance -ErrorRecord $_ -Continue
                    }

                    Add-TeppCacheItem -SqlInstance $server -Type schedule -Name $Schedule

                    # Output the job schedule
                    Get-DbaAgentSchedule -SqlInstance $server -ScheduleUid $JobSchedule.ScheduleUid
                }
            }
        } # foreach object instance
    } #process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished creating job schedule(s)." -Level Verbose
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUR78fE+0YQrIGPcseJ3n06lJn
# y2SgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFIBidaxqJXm/0p75miPyqu8wWcYxMA0G
# CSqGSIb3DQEBAQUABIIBAH3dTMguWGiwRq+RKXkSvM79MNhZ9zIApcyAA3cxqdqS
# v7f+VqVlvQuG6RgGJhCKuEsCNbkvtFJT61ygLj4LCUoyvRp5ExR98gSo60Gx9+zH
# Y4q4lObgexV4A8ywYAJq+r2b95ibT1WJtEySkNJ7LOGISKJoTDubRYQIMvC4Oxlb
# sor1X6u1G92KixurvekEzkJRrY49ksVczsUMnvZMeAGxVPtDndlgJk8NTdg/0mpA
# 9YIwLCuYZIJu1U6GY6X/MSCBQBW/2vK0zEnAg2MW8dvW058pvylbE0DOhzQjn3Hp
# 9fQy6Gd0LXnt2lv3WIOAcvVhkdYSZ03teuGlwDMT3UShggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU5WjAvBgkqhkiG9w0BCQQxIgQgs9HF9rcMEmlBY+zqsD5+
# sCCx09nzdera1cY1ZqGrStYwDQYJKoZIhvcNAQEBBQAEggIAg4Tzmyiq/vwgiu1z
# 25w4RYniVL3O5nTV75fEQR+Dp6Mn0MnstbW4OnVpOMg3MrI5hyuvjLrOOgR3mr9R
# XJotVDUACrZcdE7UuV7QfHwtartWYncKHgNlS4TwW2MPIZVu/9qbyPLGOKLVFvuA
# cFFe0pVzvTpzXOKNPUaJkcgy+HIlO7l88iF2fi5yBplJ+d7s+W4fope+yNHuvb/p
# a70bTz4y2wF1NeHwVidSZxTxPo60Tcau55ApIAWhu5WD3lKGRv3pVUcZBs4BDxWa
# tiKLywju0Afuq/1qJGOSQqd4C6GKKLNJgk9yDWu0JyM/QZO7cdY8mU8r5rxjpy8+
# Zu3xJw4/jIyMwTVG4k02Vxee2rSlDU7yYUNwe0rLkeLvWSsGtzwX1toXnTkNe7VY
# obTjhST4Ia15akZKTBWe4SFazcX9409n/5teE18hWF+O9B6lwTzBCpyRGpk2WB6T
# 57irDNkaNV7o61L9gfC6EKFNAdR9treEF+DTWBIXtrTXr/0zauyHsKEwOq2QJl1T
# rXUdV0QqDsovgGvjSjRg0Xns2RxU5x7/5Lh6rRmu5i2NLuVSzjigDmvQtOTJG/k+
# MJOJc81GU3bICic99aqyK+Uq/HW4sBRjl0/2zGu0I9ipMdyArHe2x9vCGCgLxecF
# oSsjbMvh7zqJR/+CiJ52KkD/IdQ=
# SIG # End signature block
