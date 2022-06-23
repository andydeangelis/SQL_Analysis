function Invoke-DbaPfRelog {
    <#
    .SYNOPSIS
        Pipeline-compatible wrapper for the relog command which is available on modern Windows platforms.

    .DESCRIPTION
        Pipeline-compatible wrapper for the relog command. Relog is useful for converting Windows Perfmon.

        Extracts performance counters from performance counter logs into other formats,
        such as text-TSV (for tab-delimited text), text-CSV (for comma-delimited text), binary-BIN, or SQL.

        `relog "C:\PerfLogs\Admin\System Correlation\WORKSTATIONX_20180112-000001\DataCollector01.blg" -o C:\temp\foo.csv -f tsv`

        If you find any input hangs, please send us the output so we can accommodate for it then use -Raw for an immediate solution.

    .PARAMETER Path
        Specifies the pathname of an existing performance counter log or performance counter path. You can specify multiple input files.

    .PARAMETER Destination
        Specifies the pathname of the output file or SQL database where the counters will be written. Defaults to the same directory as the source.

    .PARAMETER Type
        The output format. Defaults to tsv. Options include tsv, csv, bin, and sql.

        For a SQL database, the output file specifies the DSN!counter_log. You can specify the database location by using the ODBC manager to configure the DSN (Database System Name).

        For more information, read here: https://technet.microsoft.com/en-us/library/bb490958.aspx

    .PARAMETER Append
        If this switch is enabled, output will be appended to the specified file instead of overwriting. This option does not apply to SQL format where the default is always to append.

    .PARAMETER AllowClobber
        If this switch is enabled, the destination file will be overwritten if it exists.

    .PARAMETER PerformanceCounter
        Specifies the performance counter path to log.

    .PARAMETER PerformanceCounterPath
        Specifies the pathname of the text file that lists the performance counters to be included in a relog file. Use this option to list counter paths in an input file, one per line. Default setting is all counters in the original log file are relogged.

    .PARAMETER Interval
        Specifies sample intervals in "n" records. Includes every nth data point in the relog file. Default is every data point.

    .PARAMETER BeginTime
        This is is Get-Date object and we format it for you.

    .PARAMETER EndTime
        Specifies end time for copying last record from the input file. This is is Get-Date object and we format it for you.

    .PARAMETER ConfigPath
        Specifies the pathname of the settings file that contains command-line parameters.

    .PARAMETER Summary
        If this switch is enabled, the performance counters and time ranges of log files specified in the input file will be displayed.

    .PARAMETER Multithread
        If this switch is enabled, processing will be done in parallel. This may speed up large batches or large files.

    .PARAMETER AllTime
        If this switch is enabled and a datacollector or datacollectorset is passed in via the pipeline, collects all logs, not just the latest.

    .PARAMETER Raw
        If this switch is enabled, the results of the DOS command instead of Get-ChildItem will be displayed. This does not run in parallel.

    .PARAMETER InputObject
        Accepts the output of Get-DbaPfDataCollector and Get-DbaPfDataCollectorSet as input via the pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, DataCollector, PerfCounter, Relog
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaPfRelog

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg

        Creates C:\temp\perfmon.tsv from C:\temp\perfmon.blg.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c

        Creates the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg.

        Returns the newly created file as a file object.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -ComputerName sql2016 | Get-DbaPfDataCollector | Invoke-DbaPfRelog -Destination C:\temp\perf

        Creates C:\temp\perf if needed, then generates computername-datacollectorname.tsv (tab separated) from the latest logs of all data collector sets on sql2016. This destination format was chosen to avoid naming conflicts with piped input.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c -Raw
        >> [Invoke-DbaPfRelog][21:21:35] relog "C:\temp\perfmon.blg" -f csv -o C:\temp\a\b\c
        >> Input
        >> ----------------
        >> File(s):
        >> C:\temp\perfmon.blg (Binary)
        >> Begin:    1/13/2018 5:13:23
        >> End:      1/13/2018 14:29:55
        >> Samples:  2227
        >> 100.00%
        >> Output
        >> ----------------
        >> File:     C:\temp\a\b\c.csv
        >> Begin:    1/13/2018 5:13:23
        >> End:      1/13/2018 14:29:55
        >> Samples:  2227
        >> The command completed successfully.

        Creates the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg then outputs the raw results of the relog command.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path 'C:\temp\perflog with spaces.blg' -Destination C:\temp\a\b\c -Type csv -BeginTime ((Get-Date).AddDays(-30)) -EndTime ((Get-Date).AddDays(-1))

        Creates the temp, a, and b directories if needed, then generates c.csv (comma separated) from C:\temp\perflog with spaces.blg', starts 30 days ago and ends one day ago.

    .EXAMPLE
        PS C:\> $servers | Get-DbaPfDataCollectorSet | Get-DbaPfDataCollector | Invoke-DbaPfRelog -Multithread -AllowClobber

        Relogs latest data files from all collectors within the servers listed in $servers.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollector -Collector DataCollector01 | Invoke-DbaPfRelog -AllowClobber -AllTime

        Relogs all the log files from the DataCollector01 on the local computer and allows overwrite.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [string[]]$Path,
        [string]$Destination,
        [ValidateSet("tsv", "csv", "bin", "sql")]
        [string]$Type = "tsv",
        [switch]$Append,
        [switch]$AllowClobber,
        [string[]]$PerformanceCounter,
        [string]$PerformanceCounterPath,
        [int]$Interval,
        [datetime]$BeginTime,
        [datetime]$EndTime,
        [string]$ConfigPath,
        [switch]$Summary,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$Multithread,
        [switch]$AllTime,
        [switch]$Raw,
        [switch]$EnableException
    )
    begin {


        if (Test-Bound -ParameterName BeginTime) {
            $script:beginstring = ($BeginTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
        }
        if (Test-Bound -ParameterName EndTime) {
            $script:endstring = ($EndTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
        }

        $allpaths = @()
        $allpaths += $Path

        # to support multithreading
        if (Test-Bound -ParameterName Destination) {
            $script:destinationset = $true
            $originaldestination = $Destination
        } else {
            $script:destinationset = $false
        }
    }
    process {
        if ($Append -and $Type -ne "bin") {
            Stop-Function -Message "Append can only be used with -Type bin." -Target $Path
            return
        }

        if ($InputObject) {
            foreach ($object in $InputObject) {
                # DataCollectorSet
                if ($object.OutputLocation -and $object.RemoteOutputLocation) {
                    $instance = [dbainstance]$object.ComputerName

                    if (-not $AllTime) {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    } else {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.OutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    }


                    $script:perfmonobject = $true
                }
                # DataCollector
                if ($object.LatestOutputLocation -and $object.RemoteLatestOutputLocation) {
                    $instance = [dbainstance]$object.ComputerName

                    if (-not $AllTime) {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    } else {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path (Split-Path $object.LatestOutputLocation) -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path (Split-Path $object.RemoteLatestOutputLocation) -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    }
                    $script:perfmonobject = $true
                }
            }
        }
    }

    # Gotta collect all the paths first then process them otherwise there may be duplicates
    end {
        $allpaths = $allpaths | Where-Object { $_ -match '.blg' } | Select-Object -Unique

        if (-not $allpaths) {
            Stop-Function -Message "Could not find matching .blg files" -Target $file -Continue
            return
        }

        $scriptBlock = {
            if ($args) {
                $file = $args
            } else {
                $file = $psitem
            }
            $item = Get-ChildItem -Path $file -ErrorAction SilentlyContinue

            if ($null -eq $item) {
                Stop-Function -Message "$file does not exist." -Target $file -Continue
                return
            }

            if (-not $script:destinationset -and $file -match "C\:\\.*Admin.*") {
                $null = Test-ElevationRequirement -ComputerName $env:COMPUTERNAME -Continue
            }

            if ($script:destinationset -eq $false -and -not $Append) {
                $Destination = Join-Path (Split-Path $file) $item.BaseName
            }

            if ($Destination -and $Destination -notmatch "\." -and -not $Append -and $script:perfmonobject) {
                # if destination is set, then it needs a different name
                if ($script:destinationset -eq $true) {
                    if ($file -match "\:") {
                        $computer = $env:COMPUTERNAME
                    } else {
                        $computer = $file.Split("\")[2]
                    }
                    # Avoid naming conflicts
                    $timestamp = Get-Date -format yyyyMMddHHmmfff
                    $Destination = Join-Path $originaldestination "$computer - $($item.BaseName) - $timestamp"
                }
            }

            $params = @("`"$file`"")

            if ($Append) {
                $params += "-a"
            }

            if ($PerformanceCounter) {
                $parsedcounters = $PerformanceCounter -join " "
                $params += "-c `"$parsedcounters`""
            }

            if ($PerformanceCounterPath) {
                $params += "-cf `"$PerformanceCounterPath`""
            }

            $params += "-f $Type"

            if ($Interval) {
                $params += "-t $Interval"
            }

            if ($Destination) {
                $params += "-o `"$Destination`""
            }

            if ($script:beginstring) {
                $params += "-b $script:beginstring"
            }

            if ($script:endstring) {
                $params += "-e $script:endstring"
            }

            if ($ConfigPath) {
                $params += "-config $ConfigPath"
            }

            if ($Summary) {
                $params += "-q"
            }


            if (-not ($Destination.StartsWith("DSN"))) {
                $outputisfile = $true
            } else {
                $outputisfile = $false
            }

            if ($outputisfile) {
                if ($Destination) {
                    $dir = Split-Path $Destination
                    if (-not (Test-Path -Path $dir)) {
                        try {
                            $null = New-Item -ItemType Directory -Path $dir -ErrorAction Stop
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $Destination -Continue
                        }
                    }

                    if ((Test-Path $Destination) -and -not $Append -and ((Get-Item $Destination) -isnot [System.IO.DirectoryInfo])) {
                        if ($AllowClobber) {
                            try {
                                Remove-Item -Path "$Destination" -ErrorAction Stop
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                            }
                        } else {
                            if ($Type -eq "bin") {
                                Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite or -Append to append." -Continue
                            } else {
                                Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite." -Continue
                            }
                        }
                    }

                    if ((Test-Path "$Destination.$type") -and -not $Append) {
                        if ($AllowClobber) {
                            try {
                                Remove-Item -Path "$Destination.$type" -ErrorAction Stop
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                            }
                        } else {
                            if ($Type -eq "bin") {
                                Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite or -Append to append." -Continue
                            } else {
                                Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite." -Continue
                            }
                        }
                    }
                }
            }

            $arguments = ($params -join " ")

            try {
                if ($Raw) {
                    Write-Message -Level Output -Message "relog $arguments"
                    cmd /c "relog $arguments"
                } else {
                    Write-Message -Level Verbose -Message "relog $arguments"
                    $scriptBlock = {
                        $output = (cmd /c "relog $arguments" | Out-String).Trim()

                        if ($output -notmatch "Success") {
                            Stop-Function -Continue -Message $output.Trim("Input")
                        } else {
                            Write-Message -Level Verbose -Message "$output"
                            $array = $output -Split [environment]::NewLine
                            $files = $array | Select-String "File:"

                            foreach ($rawfile in $files) {
                                $rawfile = $rawfile.ToString().Replace("File:", "").Trim()
                                $gcierror = $null
                                Get-ChildItem $rawfile -ErrorAction SilentlyContinue -ErrorVariable gcierror | Add-Member -MemberType NoteProperty -Name RelogFile -Value $true -PassThru -ErrorAction Ignore
                                if ($gcierror) {
                                    Write-Message -Level Verbose -Message "$gcierror"
                                }
                            }
                        }
                    }
                    Invoke-Command -ScriptBlock $scriptBlock
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $path
            }
        }

        if ($Multithread) {
            $allpaths | Invoke-Parallel -ImportVariables -ImportModules -ScriptBlock $scriptBlock -ErrorAction SilentlyContinue -ErrorVariable parallelerror
            if ($parallelerror) {
                Write-Message -Level Verbose -Message "$parallelerror"
            }
        } else {
            foreach ($file in $allpaths) { Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $file }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUjDYi83kBJBsSyYFkQ7HL2xVD
# 7AugghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFKZmONxcfr54Mo4a5LOW5GObp/0ZMA0G
# CSqGSIb3DQEBAQUABIIBALhcuCOpM00K816IrqCthVBc5nr8ogOmu5PHWWIeSTLJ
# 45OwoFuHZMLQrmEFKO7s+V/2Lr5QGZi3RqaLmNFG3w/4X3kp0NeTmuT5/UTFYg/q
# 0mTwKR5WhpDVPu7jgBWaZh/6gUEDGL5IN0e08YQkHJ7Q1kK12gnYTTtHfQZgYaGW
# bNMePfT54tsgGiSeFkmNwCSXfQYSrDF7DfmxYi/wMTkHfSLZy1HvMcUr9l5ggZjM
# +rUujmP8ytiAlQCzWMp8VUjB1n7lxX5eXOiLLYhv5gbeLNOL2qHDYFhK/XaiFXPo
# VifPQ9JAur20neyP30/uuwGZ73I0OkvkhV3gg40EvfGhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzU3WjAvBgkqhkiG9w0BCQQxIgQgo+T+qzSZtrp1Sf92BrAh
# dxov7NygqNUfOyMAY/+YxYAwDQYJKoZIhvcNAQEBBQAEggIARE1cEVwD+C24quip
# yF3omNp4rf+HSTU3+rCgGzLGQNXxXmaySGoaLHjEPgDZV0LO4ghQf6osWagH6wlw
# xVifMRTlZ6BHxTsx5XwY/eLgqyBy1BaDr27gAojJOUc6h6175Na70qfBnPVHGYwA
# lLZNg0hXrgng9nuVtYJLxt67/E+lN/27oo33WFDMtWanCvMzUbd6ZZfSxyDuEfQI
# kmAmvqVpFhU4rvvg+zIDA2R7fg3Js0hkuaLBtXFlTh+3cpXo1xw9JikhHybFaDfw
# NPDmYVNT8gOCIbYvXEtrwhg2iAkyjYqbdaqaxMn2uZ0pXQZe3ECXwPpFulWHOSIG
# bzYEMOSGy5ItstJbJfCE+3VzFUaUtSgMWnvflO0HveNvi5fDgtvARmHNG0uO8BAz
# rE+GIVbvuj0DkaX9nW6jOAltYRJ9lWD0oIe3Mt91vgImyf7EmRH5Xib1nnO6Sd58
# /KOVnk1CzIfGA1yC10IZ4GaxnFMNZ+Brf8aU3sUqldYZs8r/jN2Jr0sSiKZ08DSO
# SuHkCxFD73jnA43KXpV2OWPTFPKhLqegmiNY1kgEDWPz26GWyE01FEZieU0pZORI
# rsMCDN3OehnJXvYCxieAAzQGRQKcN+pap+kQa+S3f6O1nKskpjBUy55cKN73Lzur
# zqSKS6LVHhfGfuf7oXVgGZjvzmg=
# SIG # End signature block
