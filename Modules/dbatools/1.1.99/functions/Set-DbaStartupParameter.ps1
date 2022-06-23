function Set-DbaStartupParameter {
    <#
    .SYNOPSIS
        Sets the Startup Parameters for a SQL Server instance

    .DESCRIPTION
        Modifies the startup parameters for a specified SQL Server Instance

        For full details of what each parameter does, please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms190737(v=sql.105).aspx

    .PARAMETER SqlInstance
        The SQL Server instance to be modified

        If the Sql Instance is offline path parameters will be ignored as we cannot test the instance's access to the path. If you want to force this to work then please use the Force switch

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Windows Credential with permission to log on to the server running the SQL instance

    .PARAMETER MasterData
        Path to the data file for the Master database

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER MasterLog
        Path to the log file for the Master database

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER ErrorLog
        Path to the SQL Server error log file

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER TraceFlag
        A comma separated list of TraceFlags to be applied at SQL Server startup
        By default these will be appended to any existing trace flags set

    .PARAMETER CommandPromptStart
        Shortens startup time when starting SQL Server from the command prompt. Typically, the SQL Server Database Engine starts as a service by calling the Service Control Manager.
        Because the SQL Server Database Engine does not start as a service when starting from the command prompt

    .PARAMETER MinimalStart
        Starts an instance of SQL Server with minimal configuration. This is useful if the setting of a configuration value (for example, over-committing memory) has
        prevented the server from starting. Starting SQL Server in minimal configuration mode places SQL Server in single-user mode

    .PARAMETER MemoryToReserve
        Specifies an integer number of megabytes (MB) of memory that SQL Server will leave available for memory allocations within the SQL Server process,
        but outside the SQL Server memory pool. The memory outside of the memory pool is the area used by SQL Server for loading items such as extended procedure .dll files,
        the OLE DB providers referenced by distributed queries, and automation objects referenced in Transact-SQL statements. The default is 256 MB.

    .PARAMETER SingleUser
        Start Sql Server in single user mode

    .PARAMETER NoLoggingToWinEvents
        Don't use Windows Application events log

    .PARAMETER StartAsNamedInstance
        Allows you to start a named instance of SQL Server

    .PARAMETER DisableMonitoring
        Disables the following monitoring features:

        SQL Server performance monitor counters
        Keeping CPU time and cache-hit ratio statistics
        Collecting information for the DBCC SQLPERF command
        Collecting information for some dynamic management views
        Many extended-events event points

        ** Warning *\* When you use the -x startup option, the information that is available for you to diagnose performance and functional problems with SQL Server is greatly reduced.

    .PARAMETER SingleUserDetails
        The username for single user

    .PARAMETER IncreasedExtents
        Increases the number of extents that are allocated for each file in a file group.

    .PARAMETER TraceFlagOverride
        Overrides the default behaviour and replaces any existing trace flags. If not trace flags specified will just remove existing ones

    .PARAMETER StartupConfig
        Pass in a previously saved SQL Instance startup config
        using this parameter will set TraceFlagOverride to true, so existing Trace Flags will be overridden

    .PARAMETER Offline
        Setting this switch will try perform the requested actions without connect to the SQL Server Instance, this will speed things up if you know the Instance is offline.

        When working offline, path inputs (MasterData, MasterLog and ErrorLog) will be ignored, unless Force is specified

    .PARAMETER Force
        By default we test the values passed in via MasterData, MasterLog, ErrorLog

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Startup, Parameter, Configure
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaStartupParameter

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser

        Will configure the SQL Instance server1\instance1 to startup up in Single User mode at next startup

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -IncreasedExtents

        Will configure the SQL Instance sql2016 to IncreasedExtents = True (-E)

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016  -IncreasedExtents:$false -WhatIf

        Shows what would happen if you attempted to configure the SQL Instance sql2016 to IncreasedExtents = False (no -E)

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -TraceFlag 8032,8048

        This will append Trace Flags 8032 and 8048 to the startup parameters

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagOverride

        This will remove all trace flags and set SingleUser to false

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -TraceFlag 8032,8048 -TraceFlagOverride

        This will set Trace Flags 8032 and 8048 to the startup parameters, removing any existing Trace Flags

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagOverride -Offline

        This will remove all trace flags and set SingleUser to false from an offline instance

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -ErrorLog c:\Sql\ -Offline

        This will attempt to change the ErrorLog path to c:\sql\. However, with the offline switch this will not happen. To force it, use the -Force switch like so:

        Set-DbaStartupParameter -SqlInstance sql2016 -ErrorLog c:\Sql\ -Offline -Force

    .EXAMPLE
        PS C:\> $StartupConfig = Get-DbaStartupParameter -SqlInstance server1\instance1
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -NoLoggingToWinEvents
        PS C:\> #Restart your SQL instance with the tool of choice
        PS C:\> #Do Some work
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -StartupConfig $StartupConfig
        PS C:\> #Restart your SQL instance with the tool of choice and you're back to normal

        In this example we take a copy of the existing startup configuration of server1\instance1

        We then change the startup parameters ahead of some work

        After the work has been completed, we can push the original startup parameters back to server1\instance1 and resume normal operation
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param ([parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$MasterData,
        [string]$MasterLog,
        [string]$ErrorLog,
        [string[]]$TraceFlag,
        [switch]$CommandPromptStart,
        [switch]$MinimalStart,
        [int]$MemoryToReserve,
        [switch]$SingleUser,
        [string]$SingleUserDetails,
        [switch]$NoLoggingToWinEvents,
        [switch]$StartAsNamedInstance,
        [switch]$DisableMonitoring,
        [switch]$IncreasedExtents,
        [switch]$TraceFlagOverride,
        [object]$StartupConfig,
        [switch]$Offline,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
        $null = Test-ElevationRequirement -ComputerName $SqlInstance[0]
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if (-not $Offline) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Write-Message -Level Warning -Message "Failed to connect to $instance, will try to work with just WMI. Path options will be ignored unless Force was indicated"
                    $server = $instance
                    $Offline = $true
                }
            } else {
                Write-Message -Level Verbose -Message "Offline switch set, proceeding with just WMI"
                $server = $instance
            }

            # Get Current parameters (uses WMI) -- requires elevated session
            try {
                $currentStartup = Get-DbaStartupParameter -SqlInstance $instance -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Unable to gather current startup parameters" -Target $instance -ErrorRecord $_
                return
            }
            $originalParamString = $currentStartup.ParameterString
            $parameterString = $null

            Write-Message -Level Verbose -Message "Original startup parameter string: $originalParamString"

            if ('StartupConfig' -in $PSBoundParameters.Keys) {
                Write-Message -Level VeryVerbose -Message "startupObject passed in"
                $newStartup = $StartupConfig
                $TraceFlagOverride = $true
            } else {
                Write-Message -Level VeryVerbose -Message "Parameters passed in"
                $newStartup = $currentStartup.PSObject.Copy()
                foreach ($param in ($PSBoundParameters.Keys | Where-Object { $_ -in ($newStartup.PSObject.Properties.Name) })) {
                    if ($PSBoundParameters.Item($param) -ne $newStartup.$param) {
                        $newStartup.$param = $PSBoundParameters.Item($param)
                    }
                }
            }

            if (!($currentStartup.SingleUser)) {

                if ($newStartup.MasterData.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested MasterData path"
                        $parameterString += "-d$($currentStartup.MasterData);"

                    } else {
                        if ($Force) {
                            $parameterString += "-d$($newStartup.MasterData);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.MasterData -Parent)) {
                            $parameterString += "-d$($newStartup.MasterData);"
                        } else {
                            Stop-Function -Message "Specified folder for MasterData file is not reachable by instance $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "MasterData value must be provided"
                    return
                }

                if ($newStartup.ErrorLog.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested ErrorLog path"
                        $parameterString += "-e$($currentStartup.ErrorLog);"
                    } else {
                        if ($Force) {
                            $parameterString += "-e$($newStartup.ErrorLog);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.ErrorLog -Parent)) {
                            $parameterString += "-e$($newStartup.ErrorLog);"
                        } else {
                            Stop-Function -Message "Specified folder for ErrorLog  file is not reachable by $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "ErrorLog value must be provided"
                    return
                }

                if ($newStartup.MasterLog.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested MasterLog path"
                        $parameterString += "-l$($currentStartup.MasterLog);"
                    } else {
                        if ($Force) {
                            $parameterString += "-l$($newStartup.MasterLog);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.MasterLog -Parent)) {
                            $parameterString += "-l$($newStartup.MasterLog);"
                        } else {
                            Stop-Function -Message "Specified folder for MasterLog  file is not reachable by $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "MasterLog value must be provided."
                    return
                }
            } else {

                Write-Message -Level Verbose -Message "Instance is presently configured for single user, skipping path validation"
                if ($newStartup.MasterData.Length -gt 0) {
                    $parameterString += "-d$($newStartup.MasterData);"
                } else {
                    Stop-Function -Message "Must have a value for MasterData"
                    return
                }
                if ($newStartup.ErrorLog.Length -gt 0) {
                    $parameterString += "-e$($newStartup.ErrorLog);"
                } else {
                    Stop-Function -Message "Must have a value for Errorlog"
                    return
                }
                if ($newStartup.MasterLog.Length -gt 0) {
                    $parameterString += "-l$($newStartup.MasterLog);"
                } else {
                    Stop-Function -Message "Must have a value for MasterLog"
                    return
                }
            }

            if ($newStartup.CommandPromptStart) {
                $parameterString += "-c;"
            }
            if ($newStartup.MinimalStart) {
                $parameterString += "-f;"
            }
            if ($newStartup.MemoryToReserve -notin ($null, 0)) {
                $parameterString += "-g$($newStartup.MemoryToReserve)"
            }
            if ($newStartup.SingleUser) {
                if ($SingleUserDetails.Length -gt 0) {
                    if ($SingleUserDetails -match ' ') {
                        $SingleUserDetails = """$SingleUserDetails"""
                    }
                    $parameterString += "-m$SingleUserDetails;"
                } else {
                    $parameterString += "-m;"
                }
            }
            if ($newStartup.NoLoggingToWinEvents) {
                $parameterString += "-n;"
            }
            If ($newStartup.StartAsNamedInstance) {
                $parameterString += "-s;"
            }
            if ($newStartup.DisableMonitoring) {
                $parameterString += "-x;"
            }
            if ($newStartup.IncreasedExtents) {
                $parameterString += "-E;"
            }
            if ($newStartup.TraceFlags -eq 'None') {
                $newStartup.TraceFlags = ''
            }
            if ($TraceFlagOverride -and 'TraceFlag' -in $PSBoundParameters.Keys) {
                if ($null -ne $TraceFlag -and '' -ne $TraceFlag) {
                    $newStartup.TraceFlags = $TraceFlag -join ','
                    $parameterString += (($TraceFlag.Split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
                }
            } else {
                if ('TraceFlag' -in $PSBoundParameters.Keys) {
                    if ($null -eq $TraceFlag) { $TraceFlag = '' }
                    $oldFlags = @($currentStartup.TraceFlags) -split ',' | Where-Object { $_ -ne 'None' }
                    $newFlags = $TraceFlag
                    $newStartup.TraceFlags = (@($oldFlags) + @($newFlags) | Sort-Object -Unique) -join ','
                } elseif ($TraceFlagOverride) {
                    $newStartup.TraceFlags = ''
                } else {
                    $newStartup.TraceFlags = if ($currentStartup.TraceFlags -eq 'None') { }
                    else { $currentStartup.TraceFlags -join ',' }
                }
                If ($newStartup.TraceFlags.Length -ne 0) {
                    $parameterString += (($newStartup.TraceFlags.Split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
                }
            }

            $instanceName = $instance.InstanceName
            $displayName = "SQL Server ($instanceName)"

            $scriptBlock = {
                #Variable marked as unused by PSScriptAnalyzer
                #$instance = $args[0]
                $displayName = $args[1]
                $parameterString = $args[2]

                $wmiSvc = $wmi.Services | Where-Object { $_.DisplayName -eq $displayName }
                $wmiSvc.StartupParameters = $parameterString
                $wmiSvc.Alter()
                $wmiSvc.Refresh()
                if ($wmiSvc.StartupParameters -eq $parameterString) {
                    $true
                } else {
                    $false
                }
            }
            if ($PSCmdlet.ShouldProcess("Setting startup parameters on $instance to $parameterString")) {
                try {
                    if ($Credential) {
                        $null = Invoke-ManagedComputerCommand -ComputerName $server.ComputerName -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $server.ComputerName, $displayName, $parameterString -EnableException

                        $output = Get-DbaStartupParameter -SqlInstance $server -Credential $Credential -EnableException
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalParamString
                    } else {
                        $null = Invoke-ManagedComputerCommand -ComputerName $server.ComputerName -scriptBlock $scriptBlock -ArgumentList $server.ComputerName, $displayName, $parameterString -EnableException

                        $output = Get-DbaStartupParameter -SqlInstance $server -EnableException
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalParamString
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name Notes -Value "Startup parameters changed on $instance. You must restart SQL Server for changes to take effect."
                    }
                    $output
                } catch {
                    Stop-Function -Message "Startup parameter update failed on $instance. " -Target $instance -ErrorRecord $_
                    return
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUcPmShDWvnojQ0rDlYU740g5E
# /VKgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFCvx6H7Uki99G0IzUefo02EOaopBMA0G
# CSqGSIb3DQEBAQUABIIBABqOp+qyFyQ6IludcZPUJ8kwRVHYxEEaTiDUKaLq9riH
# T8O5NJKZBjd2ZwPTmC5EF0hXBBRNoRNI4eXg4SYeNUpdaHpEg0APhSj71K0gdw8b
# 4tMDOsgyZYk/mGiUGOC68gzVq9XcXfDcXhBWXv7xYr4Sns3dsh/2QUeW5R6iSdek
# G7WCDLWNXWWAIsKTclUj+YO3VpOgbL+kioTQvdJcSIYcPno1Hn7NSjGpqz9Lz7Go
# cuinyCVneOuZTQvsCEcfCRXU/amCtRs9nxgFSgsoA+mXFYElAlvo7w057Ez+n6zu
# kzWE8k7gykwmgw4vDu9jGas7c1ikTmzwIMofz4xTOT+hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDIzWjAvBgkqhkiG9w0BCQQxIgQgi9rKOUhm572k0CI3SEf0
# 4+QqyCJj4jWPPFDxYcZ71tkwDQYJKoZIhvcNAQEBBQAEggIAkic5nA6oNBBRoBoX
# Ed6xW7gRCNzPtUC+S+6SMdzdKSpN9icQOdYblLP0N1UcluRovnEiuTp9VK0G+fZJ
# uQXBzdOJESBfosejepNELTPwW1F5etocNxmIqJDQj+qoKhcSXTavWIVNPjUocSUW
# DcvDfUZ3FVODty6EB2k6AxechJqa6vOfV1mntSAbUU18s7Z01BRDjdM5HHiXwwfa
# EHm9CXJUpJW6rdTXK4+GXckMlOqBLwerNoEzU2UWZbmBOQT6E0DMFo60ZjYYA3Xu
# jcSt7Z+4E4TuiMYX6NA3Sjy8cva0TKGkAVIoTW0Mdx1zk3mv3witcJ9DFShjiFuy
# uHoKOw6EMKIpJV8sK0Y9lDPFhX41sSCy7aS/lwXm3nYDRCvuOdXw1QTFy6qnh0xk
# +nnHYAHSuUCxaUE+UVsNPCdS9mGpanIO0kHnMneMKKq4vIaSa4D7r6V2FRbpPNKP
# HAC2TPCA1iOzBKROvH4Uf5O6BYN40xsKcmLo+TGgDZAc4G9YEEIy3DGJXLxLMX7j
# c0ggs1hkG77E37oNLPzb1Zbq8d4aazR3E7cdAYIex0eQkIthjEgO6tb7m76BLo2e
# TbmdOttGmmSsIYyB1lBpjhunVGHCwRxMyFFwlzYWjDoYGeO4T3um8cHRm/n7DGFH
# XgIag6t3mdigUZTHTMulsPjUzHI=
# SIG # End signature block
