function Get-DbaAgentJobHistory {
    <#
    .SYNOPSIS
        Gets execution history of SQL Agent Job on instance(s) of SQL Server.

    .DESCRIPTION
        Get-DbaAgentJobHistory returns all information on the executions still available on each instance(s) of SQL Server submitted.
        The cleanup of SQL Agent history determines how many records are kept.

        https://msdn.microsoft.com/en-us/library/ms201680.aspx
        https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.agent.jobhistoryfilter(v=sql.120).aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job from which the history is wanted. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        The job(s) to exclude - this list is auto-populated from the server

    .PARAMETER StartDate
        The DateTime starting from which the history is wanted. If unspecified, all available records will be processed.

    .PARAMETER EndDate
        The DateTime before which the history is wanted. If unspecified, all available records will be processed.

    .PARAMETER OutcomeType
        The CompletionResult to filter the history for. Valid values are: Failed, Succeeded, Retry, Cancelled, InProgress, Unknown

    .PARAMETER ExcludeJobSteps
        Use this switch to discard all job steps, and return only the job totals

    .PARAMETER WithOutputFile
        Use this switch to retrieve the output file (only if you want step details). Bonus points, we handle the quirks
        of SQL Agent tokens to the best of our knowledge (https://technet.microsoft.com/it-it/library/ms175575(v=sql.110).aspx)

    .PARAMETER JobCollection
        An array of SMO jobs

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Klaas Vandenberghe (@PowerDbaKlaas) | Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentJobHistory

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance localhost

        Returns all SQL Agent Job execution results on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance localhost, sql2016

        Returns all SQL Agent Job execution results for the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> 'sql1','sql2\Inst2K17' | Get-DbaAgentJobHistory

        Returns all SQL Agent Job execution results for sql1 and sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 | Select-Object *

        Returns all properties for all SQl Agent Job execution results on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -Job 'Output File Cleanup'

        Returns all properties for all SQl Agent Job execution results of the 'Output File Cleanup' job on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -Job 'Output File Cleanup' -WithOutputFile

        Returns all properties for all SQl Agent Job execution results of the 'Output File Cleanup' job on sql2\Inst2K17,
        with additional properties that show the output filename path

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -ExcludeJobSteps

        Returns the SQL Agent Job execution results for the whole jobs on sql2\Inst2K17, leaving out job step execution results.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -StartDate '2017-05-22' -EndDate '2017-05-23 12:30:00'

        Returns the SQL Agent Job execution results between 2017/05/22 00:00:00 and 2017/05/23 12:30:00 on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 | Where-Object Name -Match backup | Get-DbaAgentJobHistory

        Gets all jobs with the name that match the regex pattern "backup" and then gets the job history from those. You can also use -Like *backup* in this example.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2016 -OutcomeType Failed

        Returns only the failed SQL Agent Job execution results for the sql2016 SQL Server instance.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Server")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [DateTime]$StartDate = "1900-01-01",
        [DateTime]$EndDate = $(Get-Date),
        [ValidateSet('Failed', 'Succeeded', 'Retry', 'Cancelled', 'InProgress', 'Unknown')]
        [Microsoft.SqlServer.Management.Smo.Agent.CompletionResult]$OutcomeType,
        [switch]$ExcludeJobSteps,
        [switch]$WithOutputFile,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Collection")]
        [Microsoft.SqlServer.Management.Smo.Agent.Job]$JobCollection,
        [switch]$EnableException
    )

    begin {
        $filter = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter
        $filter.StartRunDate = $StartDate
        $filter.EndRunDate = $EndDate

        if (Test-Bound OutcomeType) {
            $filter.OutcomeTypes = $OutcomeType
        }

        if ($ExcludeJobSteps -and $WithOutputFile) {
            Stop-Function -Message "You can't use -ExcludeJobSteps and -WithOutputFile together"
        }

        function Get-JobHistory {
            [CmdletBinding()]
            param (
                $Server,
                $Job,
                [switch]$WithOutputFile
            )
            $tokenrex = [regex]'\$\((?<method>[^()]+)\((?<tok>[^)]+)\)\)|\$\((?<tok>[^)]+)\)'
            $propmap = @{
                'INST'      = $Server.ServiceName
                'MACH'      = $Server.ComputerName
                'SQLDIR'    = $Server.InstallDataDirectory
                'SQLLOGDIR' = $Server.ErrorLogPath
                #'STEPCT' loop number ?
                'SRVR'      = $Server.DomainInstanceName
                # WMI( property ) impossible
            }


            $squote_rex = [regex]"(?<!')'(?!')"
            $dquote_rex = [regex]'(?<!")"(?!")'
            $rbrack_rex = [regex]'(?<!])](?!])'

            function Resolve-TokenEscape($method, $value) {
                if (!$method) {
                    return $value
                }
                $value = switch ($method) {
                    'ESCAPE_SQUOTE' { $squote_rex.Replace($value, "''") }
                    'ESCAPE_DQUOTE' { $dquote_rex.Replace($value, '""') }
                    'ESCAPE_RBRACKET' { $rbrack_rex.Replace($value, ']]') }
                    'ESCAPE_NONE' { $value }
                    default { $value }
                }
                return $value
            }

            #'STEPID' =  stepid
            #'STRTTM' job begin time
            #'STRTDT' job begin date
            #'JOBID' = JobId
            function Resolve-JobToken($exec, $outfile, $outcome) {
                $n = $tokenrex.Matches($outfile)
                foreach ($x in $n) {
                    $tok = $x.Groups['tok'].Value
                    $EscMethod = $x.Groups['method'].Value
                    if ($propmap.containskey($tok)) {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $propmap[$tok]
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STEPID') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $exec.StepID
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'JOBID') {
                        # convert(binary(16), ?)
                        $repl = @('0x') + @($exec.JobID.ToByteArray() | ForEach-Object -Process { $_.ToString('X2') }) -join ''
                        $repl = Resolve-TokenEscape -method $EscMethod -value $repl
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STRTDT') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $outcome.RunDate.toString('yyyyMMdd')
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STRTTM') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$outcome.RunDate.toString('HHmmss')).toString()
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'DATE') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $exec.RunDate.toString('yyyyMMdd')
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'TIME') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$exec.RunDate.toString('HHmmss')).toString()
                        $outfile = $outfile.Replace($x.Value, $repl)
                    }
                }
                return $outfile
            }
            try {
                Write-Message -Message "Attempting to get job history from $instance" -Level Verbose
                if ($Job) {
                    foreach ($currentjob in $Job) {
                        $filter.JobName = $currentjob
                        $executions += $server.JobServer.EnumJobHistory($filter)
                    }
                } else {
                    $executions = $server.JobServer.EnumJobHistory($filter)
                }
                if ($ExcludeJobSteps) {
                    $executions = $executions | Where-Object { $_.StepID -eq 0 }
                }

                if ($WithOutputFile) {
                    $outmap = @{ }
                    $outfiles = Get-DbaAgentJobOutputFile -SqlInstance $Server -SqlCredential $SqlCredential -Job $Job

                    foreach ($out in $outfiles) {
                        if (!$outmap.ContainsKey($out.Job)) {
                            $outmap[$out.Job] = @{ }
                        }
                        $outmap[$out.Job][$out.StepId] = $out.OutputFileName
                    }
                }
                $outcome = [pscustomobject]@{ }
                foreach ($execution in $executions) {
                    $status = switch ($execution.RunStatus) {
                        0 { "Failed" }
                        1 { "Succeeded" }
                        2 { "Retry" }
                        3 { "Canceled" }
                    }

                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    $DurationInSeconds = ($execution.RunDuration % 100) + [math]::floor( ($execution.RunDuration % 10000 ) / 100 ) * 60 + [math]::floor( ($execution.RunDuration % 1000000 ) / 10000 ) * 60 * 60
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name StartDate -value ([dbadatetime]$execution.RunDate)
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name EndDate -value ([dbadatetime]$execution.RunDate.AddSeconds($DurationInSeconds))
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name Duration -value ([prettytimespan](New-TimeSpan -Seconds $DurationInSeconds))
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name Status -value $status
                    if ($WithOutputFile) {
                        if ($execution.StepID -eq 0) {
                            $outcome = $execution
                        }
                        try {
                            $outname = $outmap[$execution.JobName][$execution.StepID]
                            $outname = Resolve-JobToken -exec $execution -outcome $outcome -outfile $outname
                            $outremote = Join-AdminUNC $Server.ComputerName $outname
                        } catch {
                            $outname = ''
                            $outremote = ''
                        }
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name OutputFileName -value $outname
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name RemoteOutputFileName -value $outremote
                        # Add this in for easier ConvertTo-DbaTimeline Support
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name TypeName -value AgentJobHistory
                        Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, StartDate, EndDate, Duration, Status, OperatorEmailed, Message, OutputFileName, RemoteOutputFileName -TypeName AgentJobHistory
                    } else {
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name TypeName -value AgentJobHistory
                        Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, StartDate, EndDate, Duration, Status, OperatorEmailed, Message -TypeName AgentJobHistory
                    }

                }
            } catch {
                Stop-Function -Message "Could not get Agent Job History from $instance" -Target $instance -Continue
            }
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($JobCollection) {
            foreach ($currentjob in $JobCollection) {
                Get-JobHistory -Server $currentjob.Parent.Parent -Job $currentjob.Name -WithOutputFile:$WithOutputFile
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($ExcludeJob) {
                $jobs = $server.JobServer.Jobs.Name | Where-Object { $_ -notin $ExcludeJob }
                foreach ($currentjob in $jobs) {
                    Get-JobHistory -Server $server -Job $currentjob -WithOutputFile:$WithOutputFile
                }
            } else {
                Get-JobHistory -Server $server -Job $Job -WithOutputFile:$WithOutputFile
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBRcgHoPcmJ44ZU
# mJ3Y4veEToWcTAGKlOaWPBCIyIYvSqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
# Y1+/3q4SBOdtMA0GCSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNV
# BAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcN
# MjAwNTEyMDAwMDAwWhcNMjMwNjA4MTIwMDAwWjBXMQswCQYDVQQGEwJVUzERMA8G
# A1UECBMIVmlyZ2luaWExDzANBgNVBAcTBlZpZW5uYTERMA8GA1UEChMIZGJhdG9v
# bHMxETAPBgNVBAMTCGRiYXRvb2xzMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
# CgKCAQEAvL9je6vjv74IAbaY5rXqHxaNeNJO9yV0ObDg+kC844Io2vrHKGD8U5hU
# iJp6rY32RVprnAFrA4jFVa6P+sho7F5iSVAO6A+QZTHQCn7oquOefGATo43NAadz
# W2OWRro3QprMPZah0QFYpej9WaQL9w/08lVaugIw7CWPsa0S/YjHPGKQ+bYgI/kr
# EUrk+asD7lvNwckR6pGieWAyf0fNmSoevQBTV6Cd8QiUfj+/qWvLW3UoEX9ucOGX
# 2D8vSJxL7JyEVWTHg447hr6q9PzGq+91CO/c9DWFvNMjf+1c5a71fEZ54h1mNom/
# XoWZYoKeWhKnVdv1xVT1eEimibPEfQIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAU
# WsS5eyoKo6XqcQPAYPkt9mV1DlgwHQYDVR0OBBYEFPDAoPu2A4BDTvsJ193ferHL
# 454iMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8E
# cDBuMDWgM6Axhi9odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVk
# LWNzLWcxLmNybDA1oDOgMYYvaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTIt
# YXNzdXJlZC1jcy1nMS5jcmwwTAYDVR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggr
# BgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEw
# gYQGCCsGAQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/
# BAIwADANBgkqhkiG9w0BAQsFAAOCAQEAj835cJUMH9Y2pBKspjznNJwcYmOxeBcH
# Ji+yK0y4bm+j44OGWH4gu/QJM+WjZajvkydJKoJZH5zrHI3ykM8w8HGbYS1WZfN4
# oMwi51jKPGZPw9neGS2PXrBcKjzb7rlQ6x74Iex+gyf8z1ZuRDitLJY09FEOh0BM
# LaLh+UvJ66ghmfIyjP/g3iZZvqwgBhn+01fObqrAJ+SagxJ/21xNQJchtUOWIlxR
# kuUn9KkuDYrMO70a2ekHODcAbcuHAGI8wzw4saK1iPPhVTlFijHS+7VfIt/d/18p
# MLHHArLQQqe1Z0mTfuL4M4xCUKpebkH8rI3Fva62/6osaXLD0ymERzCCBTAwggQY
# oAMCAQICEAQJGBtf1btmdVNDtW+VUAgwDQYJKoZIhvcNAQELBQAwZTELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4X
# DTEzMTAyMjEyMDAwMFoXDTI4MTAyMjEyMDAwMFowcjELMAkGA1UEBhMCVVMxFTAT
# BgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEx
# MC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAPjTsxx/DhGvZ3cH0wsx
# SRnP0PtFmbE620T1f+Wondsy13Hqdp0FLreP+pJDwKX5idQ3Gde2qvCchqXYJawO
# eSg6funRZ9PG+yknx9N7I5TkkSOWkHeC+aGEI2YSVDNQdLEoJrskacLCUvIUZ4qJ
# RdQtoaPpiCwgla4cSocI3wz14k1gGL6qxLKucDFmM3E+rHCiq85/6XzLkqHlOzEc
# z+ryCuRXu0q16XTmK/5sy350OTYNkO/ktU6kqepqCquE86xnTrXE94zRICUj6whk
# PlKWwfIPEvTFjg/BougsUfdzvL2FsWKDc0GCB+Q4i2pzINAPZHM8np+mM6n9Gd8l
# k9ECAwEAAaOCAc0wggHJMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQD
# AgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHkGCCsGAQUFBwEBBG0wazAkBggrBgEF
# BQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRw
# Oi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0Eu
# Y3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8vY3JsNC5kaWdpY2VydC5jb20v
# RGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsME8GA1UdIARI
# MEYwOAYKYIZIAYb9bAACBDAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdp
# Y2VydC5jb20vQ1BTMAoGCGCGSAGG/WwDMB0GA1UdDgQWBBRaxLl7KgqjpepxA8Bg
# +S32ZXUOWDAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzANBgkqhkiG
# 9w0BAQsFAAOCAQEAPuwNWiSz8yLRFcgsfCUpdqgdXRwtOhrE7zBh134LYP3DPQ/E
# r4v97yrfIFU3sOH20ZJ1D1G0bqWOWuJeJIFOEKTuP3GOYw4TS63XX0R58zYUBor3
# nEZOXP+QsRsHDpEV+7qvtVHCjSSuJMbHJyqhKSgaOnEoAjwukaPAJRHinBRHoXpo
# aK+bp1wgXNlxsQyPu6j4xRJon89Ay0BEpRPw5mQMJQhCMrI2iiQC/i9yfhzXSUWW
# 6Fkd6fp0ZGuy62ZD2rOwjNXpDd32ASDOmTFjPQgaGLOBm0/GkxAG/AeB+ova+YJJ
# 92JuoVP6EpQYhS6SkepobEQysmah5xikmmRR7zCCBbEwggSZoAMCAQICEAEkCvse
# OAuKFvFLcZ3008AwDQYJKoZIhvcNAQEMBQAwZTELMAkGA1UEBhMCVVMxFTATBgNV
# BAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIG
# A1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTIyMDYwOTAwMDAw
# MFoXDTMxMTEwOTIzNTk1OVowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGln
# aUNlcnQgVHJ1c3RlZCBSb290IEc0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAv+aQc2jeu+RdSjwwIjBpM+zCpyUuySE98orYWcLhKac9WKt2ms2uexuE
# DcQwH/MbpDgW61bGl20dq7J58soR0uRf1gU8Ug9SH8aeFaV+vp+pVxZZVXKvaJNw
# wrK6dZlqczKU0RBEEC7fgvMHhOZ0O21x4i0MG+4g1ckgHWMpLc7sXk7Ik/ghYZs0
# 6wXGXuxbGrzryc/NrDRAX7F6Zu53yEioZldXn1RYjgwrt0+nMNlW7sp7XeOtyU9e
# 5TXnMcvak17cjo+A2raRmECQecN4x7axxLVqGDgDEI3Y1DekLgV9iPWCPhCRcKtV
# gkEy19sEcypukQF8IUzUvK4bA3VdeGbZOjFEmjNAvwjXWkmkwuapoGfdpCe8oU85
# tRFYF/ckXEaPZPfBaYh2mHY9WV1CdoeJl2l6SPDgohIbZpp0yt5LHucOY67m1O+S
# kjqePdwA5EUlibaaRBkrfsCUtNJhbesz2cXfSwQAzH0clcOP9yGyshG3u3/y1Yxw
# LEFgqrFjGESVGnZifvaAsPvoZKYz0YkH4b235kOkGLimdwHhD5QMIR2yVCkliWzl
# DlJRR3S+Jqy2QXXeeqxfjT/JvNNBERJb5RBQ6zHFynIWIgnffEx1P2PsIV/EIFFr
# b7GrhotPwtZFX50g/KEexcCPorF+CiaZ9eRpL5gdLfXZqbId5RsCAwEAAaOCAV4w
# ggFaMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFOzX44LScV1kTN8uZz/nupiu
# HA9PMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA4GA1UdDwEB/wQE
# AwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB5BggrBgEFBQcBAQRtMGswJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQC
# MAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQwFAAOCAQEAmhYCpQHvgfsNtFiyeK2o
# IxnZczfaYJ5R18v4L0C5ox98QE4zPpA854kBdYXoYnsdVuBxut5exje8eVxiAE34
# SXpRTQYy88XSAConIOqJLhU54Cw++HV8LIJBYTUPI9DtNZXSiJUpQ8vgplgQfFOO
# n0XJIDcUwO0Zun53OdJUlsemEd80M/Z1UkJLHJ2NltWVbEcSFCRfJkH6Gka93rDl
# kUcDrBgIy8vbZol/K5xlv743Tr4t851Kw8zMR17IlZWt0cu7KgYg+T9y6jbrRXKS
# eil7FAM8+03WSHF6EBGKCHTNbBsEXNKKlQN2UVBT1i73SkbDrhAscUywh7YnN0Rg
# RDCCBq4wggSWoAMCAQICEAc2N7ckVHzYR6z9KGYqXlswDQYJKoZIhvcNAQELBQAw
# YjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQ
# d3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290
# IEc0MB4XDTIyMDMyMzAwMDAwMFoXDTM3MDMyMjIzNTk1OVowYzELMAkGA1UEBhMC
# VVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBU
# cnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAMaGNQZJs8E9cklRVcclA8TykTepl1Gh
# 1tKD0Z5Mom2gsMyD+Vr2EaFEFUJfpIjzaPp985yJC3+dH54PMx9QEwsmc5Zt+Feo
# An39Q7SE2hHxc7Gz7iuAhIoiGN/r2j3EF3+rGSs+QtxnjupRPfDWVtTnKC3r07G1
# decfBmWNlCnT2exp39mQh0YAe9tEQYncfGpXevA3eZ9drMvohGS0UvJ2R/dhgxnd
# X7RUCyFobjchu0CsX7LeSn3O9TkSZ+8OpWNs5KbFHc02DVzV5huowWR0QKfAcsW6
# Th+xtVhNef7Xj3OTrCw54qVI1vCwMROpVymWJy71h6aPTnYVVSZwmCZ/oBpHIEPj
# Q2OAe3VuJyWQmDo4EbP29p7mO1vsgd4iFNmCKseSv6De4z6ic/rnH1pslPJSlREr
# WHRAKKtzQ87fSqEcazjFKfPKqpZzQmiftkaznTqj1QPgv/CiPMpC3BhIfxQ0z9JM
# q++bPf4OuGQq+nUoJEHtQr8FnGZJUlD0UfM2SU2LINIsVzV5K6jzRWC8I41Y99xh
# 3pP+OcD5sjClTNfpmEpYPtMDiP6zj9NeS3YSUZPJjAw7W4oiqMEmCPkUEBIDfV8j
# u2TjY+Cm4T72wnSyPx4JduyrXUZ14mCjWAkBKAAOhFTuzuldyF4wEr1GnrXTdrnS
# DmuZDNIztM2xAgMBAAGjggFdMIIBWTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1Ud
# DgQWBBS6FtltTYUvcyl2mi91jGogj57IbzAfBgNVHSMEGDAWgBTs1+OC0nFdZEzf
# Lmc/57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# dwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2Vy
# dC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFRydXN0ZWRSb290RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6
# Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAG
# A1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOC
# AgEAfVmOwJO2b5ipRCIBfmbW2CFC4bAYLhBNE88wU86/GPvHUF3iSyn7cIoNqilp
# /GnBzx0H6T5gyNgL5Vxb122H+oQgJTQxZ822EpZvxFBMYh0MCIKoFr2pVs8Vc40B
# IiXOlWk/R3f7cnQU1/+rT4osequFzUNf7WC2qk+RZp4snuCKrOX9jLxkJodskr2d
# fNBwCnzvqLx1T7pa96kQsl3p/yhUifDVinF2ZdrM8HKjI/rAJ4JErpknG6skHibB
# t94q6/aesXmZgaNWhqsKRcnfxI2g55j7+6adcq/Ex8HBanHZxhOACcS2n82HhyS7
# T6NJuXdmkfFynOlLAlKnN36TU6w7HQhJD5TNOXrd/yVjmScsPT9rp/Fmw0HNT7ZA
# myEhQNC3EyTN3B14OuSereU0cZLXJmvkOHOrpgFPvT87eK1MrfvElXvtCl8zOYdB
# eHo46Zzh3SP9HSjTx/no8Zhf+yvYfvJGnXUsHicsJttvFXseGYs2uJPU5vIXmVnK
# cPA3v5gA3yAWTyf7YGcWoWa63VXAOimGsJigK+2VQbc61RWYMbRiCQ8KvYHZE/6/
# pNHzV9m8BPqC3jLfBInwAM1dwvnQI38AC+R2AibZ8GV2QqYphwlHK+Z/GqSFD/yY
# lvZVVCsfgPrA8g4r5db7qS9EFUrnEw4d2zc4GqEr9u3WfPwwggbGMIIErqADAgEC
# AhAKekqInsmZQpAGYzhNhpedMA0GCSqGSIb3DQEBCwUAMGMxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1
# c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMjIwMzI5
# MDAwMDAwWhcNMzMwMzE0MjM1OTU5WjBMMQswCQYDVQQGEwJVUzEXMBUGA1UEChMO
# RGlnaUNlcnQsIEluYy4xJDAiBgNVBAMTG0RpZ2lDZXJ0IFRpbWVzdGFtcCAyMDIy
# IC0gMjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALkqliOmXLxf1knw
# FYIY9DPuzFxs4+AlLtIx5DxArvurxON4XX5cNur1JY1Do4HrOGP5PIhp3jzSMFEN
# MQe6Rm7po0tI6IlBfw2y1vmE8Zg+C78KhBJxbKFiJgHTzsNs/aw7ftwqHKm9MMYW
# 2Nq867Lxg9GfzQnFuUFqRUIjQVr4YNNlLD5+Xr2Wp/D8sfT0KM9CeR87x5MHaGjl
# RDRSXw9Q3tRZLER0wDJHGVvimC6P0Mo//8ZnzzyTlU6E6XYYmJkRFMUrDKAz200k
# heiClOEvA+5/hQLJhuHVGBS3BEXz4Di9or16cZjsFef9LuzSmwCKrB2NO4Bo/tBZ
# mCbO4O2ufyguwp7gC0vICNEyu4P6IzzZ/9KMu/dDI9/nw1oFYn5wLOUrsj1j6siu
# gSBrQ4nIfl+wGt0ZvZ90QQqvuY4J03ShL7BUdsGQT5TshmH/2xEvkgMwzjC3iw9d
# RLNDHSNQzZHXL537/M2xwafEDsTvQD4ZOgLUMalpoEn5deGb6GjkagyP6+SxIXuG
# Z1h+fx/oK+QUshbWgaHK2jCQa+5vdcCwNiayCDv/vb5/bBMY38ZtpHlJrYt/YYcF
# aPfUcONCleieu5tLsuK2QT3nr6caKMmtYbCgQRgZTu1Hm2GV7T4LYVrqPnqYklHN
# P8lE54CLKUJy93my3YTqJ+7+fXprAgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMC
# B4AwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAE
# GTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3Mp
# dpovdYxqII+eyG8wHQYDVR0OBBYEFI1kt4kh/lZYRIRhp+pvHDaP3a8NMFoGA1Ud
# HwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRy
# dXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUF
# BwEBBIGDMIGAMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20w
# WAYIKwYBBQUHMAKGTGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZI
# hvcNAQELBQADggIBAA0tI3Sm0fX46kuZPwHk9gzkrxad2bOMl4IpnENvAS2rOLVw
# Eb+EGYs/XeWGT76TOt4qOVo5TtiEWaW8G5iq6Gzv0UhpGThbz4k5HXBw2U7fIyJs
# 1d/2WcuhwupMdsqh3KErlribVakaa33R9QIJT4LWpXOIxJiA3+5JlbezzMWn7g7h
# 7x44ip/vEckxSli23zh8y/pc9+RTv24KfH7X3pjVKWWJD6KcwGX0ASJlx+pedKZb
# NZJQfPQXpodkTz5GiRZjIGvL8nvQNeNKcEiptucdYL0EIhUlcAZyqUQ7aUcR0+7p
# x6A+TxC5MDbk86ppCaiLfmSiZZQR+24y8fW7OK3NwJMR1TJ4Sks3KkzzXNy2hcC7
# cDBVeNaY/lRtf3GpSBp43UZ3Lht6wDOK+EoojBKoc88t+dMj8p4Z4A2UKKDr2xpR
# oJWCjihrpM6ddt6pc6pIallDrl/q+A8GQp3fBmiW/iqgdFtjZt5rLLh4qk1wbfAs
# 8QcVfjW05rUMopml1xVrNQ6F1uAszOAMJLh8UgsemXzvyMjFjFhpr6s94c/MfRWu
# FL+Kcd/Kl7HYR+ocheBFThIcFClYzG/Tf8u+wQ5KbyCcrtlzMlkI5y2SoRoR/jKY
# pl0rl+CL05zMbbUNrkdjOEcXW28T2moQbh9Jt0RbtAgKh1pZBHYRoad3AhMcMYIF
# XTCCBVkCAQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQg
# U0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQAwW7hiGwoWNfv96uEgTn
# bTANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkG
# CSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDCksRg13SXJ6zHJpS1Yf6QDrgPRLubeh2C
# 4vgeXQpPfDANBgkqhkiG9w0BAQEFAASCAQAkfb+3S9qUfJsB8fmhxQP7dy56LG5E
# Pw70KMD6T8Le8qLYLlGGjn8nHOEA8Q9H2zBhKxs9SmTLd8Dv0HpNhZdanoAG52QV
# 2QvxrZKK2PSLZ5LGBjpB2Z1vmOOylF62Z8H2/7FcV5HWP9q2iCQbxNvout8S7Z4Y
# 4CJp7Wom+1fnkJwZ1ilLMi7DqdnDsBJlBGU6n1lYB2KmdUpmhJplWvttVi9NQ6JF
# o2YfQEMilG/fwtlzkFsgI5Oe/fM/cN+eMBSE8+AOMR3WOJDfIRW/zRIMViGqpJ+N
# NcwL7HPZPbDd/Tbk9YsNDIzXZKiGbm9qZC2ndNrsk6+PLANCDJ1CcxLEoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI0OVowLwYJKoZIhvcNAQkEMSIEIGujyg0X
# ta5h9cVxsLqqkqj6qRp4HWol5qBkaG8Qe1m/MA0GCSqGSIb3DQEBAQUABIICAABq
# zvEFZKULgTJAKMqkgJnKIAvRBY03C3nLFlOJAfrZz/1DDmypEMxlrxV4Z9+baFUV
# YKLBELTR8qgfbUPNmRLxUgmW4yo96n578rGvvwNaNhhV426v4u39OXxGGrAgXeo1
# QVYy3bhBQhtLpd6EzqFxsQ8/3R+QyGw6/3IykGZNCWJHrkWsq6rTuB/6VLI9EYz3
# FviH/cY436Alufz3wpg6EvX9qBhWIYtaDwBgSsuUAne5x+m7RazXerSsC34teJAG
# UfaKQzEaXZnokImC7WmK8K8ysCK7RFm3hDExBu0igMHdU+wZ2q7xBYT84pIkTmsx
# fh0W786AxxyF8DQMOiMHtBjAlS50yfTtk26SmsctEpEicm8p2WRx4g//gV3YQ3Jt
# Rof1hLhMovU79frGR/TjLmahWwNwFLl36asVLqizoP2mSMj6Amqxi/nzYHkCyLl4
# eZ6e/S2I2CITPQTQmarznAdoDobFqArmWOZGwk4Ume6gPtqowA1iyPqQX6bfykEV
# 29vpF7dCdhmKddeyKqp5zk/6fB9pTXKnfyononZJFYv5TDB1quqgDRddsd+8nZZk
# 9aMLtW/RNHBye1PBYLDKpkZQQCfoFSZ7iLCLLvJPyOOtYBRBwuEhUHo9RvInAjNj
# H1L8HT7eoo/QW4FkDiPhEty5aT4a8TAlk4X+yljt
# SIG # End signature block
