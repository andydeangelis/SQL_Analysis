function Get-DbaWindowsLog {
    <#
    .SYNOPSIS
        Gets Windows Application events associated with an instance

    .DESCRIPTION
        Gets Windows Application events associated with an instance

    .PARAMETER SqlInstance
        The instance(s) to retrieve the event logs from

    .PARAMETER Start
        Default: 1970
        Retrieve all events starting from this timestamp.

    .PARAMETER End
        Default: Now
        Retrieve all events that happened before this timestamp

    .PARAMETER Credential
        Credential to be used to connect to the Server. Note this is a Windows credential, as this command requires we communicate with the computer and not with the SQL instance.

    .PARAMETER MaxThreads
        Default: Unlimited
        The maximum number of parallel threads used on the local computer.
        Given that those will mostly be waiting for the remote system, there is usually no need to limit this.

    .PARAMETER MaxRemoteThreads
        Default: 2
        The maximum number of parallel threads that are executed on the target sql server.
        These processes will cause considerable CPU load, so a low limit is advisable in most scenarios.
        Any value lower than 1 disables the limit

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Logging, OS
        Author: Drew Furgiuele | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWindowsLog

    .EXAMPLE
        PS C:\> $ErrorLogs = Get-DbaWindowsLog -SqlInstance sql01\sharepoint
        PS C:\> $ErrorLogs | Where-Object ErrorNumber -eq 18456

        Returns all lines in the errorlogs that have event number 18456 in them

    #>
    #This exists to ignore the Script Analyzer rule for Start-Runspace
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance = $env:COMPUTERNAME,

        [DateTime]
        $Start = "1/1/1970 00:00:00",

        [DateTime]
        $End = (Get-Date),


        [System.Management.Automation.PSCredential]
        $Credential,

        [int]
        $MaxThreads = 0,

        [int]
        $MaxRemoteThreads = 2,

        [switch]$EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        #region Helper Functions
        function Start-Runspace {
            $Powershell = [PowerShell]::Create().AddScript($scriptBlock_ParallelRemoting).AddParameter("SqlInstance", $instance).AddParameter("Start", $Start).AddParameter("End", $End).AddParameter("Credential", $Credential).AddParameter("MaxRemoteThreads", $MaxRemoteThreads).AddParameter("ScriptBlock", $scriptBlock_RemoteExecution)
            $Powershell.RunspacePool = $RunspacePool
            Write-Message -Level Verbose -Message "Launching remote runspace against <c='green'>$instance</c>" -Target $instance
            $null = $RunspaceCollection.Add((New-Object -TypeName PSObject -Property @{ Runspace = $PowerShell.BeginInvoke(); PowerShell = $PowerShell; Instance = $instance.FullSmoName }))
        }

        function Receive-Runspace {
            [Parameter()]
            param (
                [switch]
                $Wait
            )

            do {
                foreach ($Run in $RunspaceCollection.ToArray()) {
                    if ($Run.Runspace.IsCompleted) {
                        Write-Message -Level Verbose -Message "Receiving results from <c='green'>$($Run.Instance)</c>" -Target $Run.Instance
                        $Run.PowerShell.EndInvoke($Run.Runspace)
                        $Run.PowerShell.Dispose()
                        $RunspaceCollection.Remove($Run)
                    }
                }

                if ($Wait -and ($RunspaceCollection.Count -gt 0)) { Start-Sleep -Milliseconds 250 }
            }
            while ($Wait -and ($RunspaceCollection.Count -gt 0))
        }
        #endregion Helper Functions

        #region Scriptblocks
        $scriptBlock_RemoteExecution = {
            param (
                [System.DateTime]
                $Start,

                [System.DateTime]
                $End,

                [string]
                $InstanceName,

                [int]
                $Throttle
            )

            #region Helper function
            function Convert-ErrorRecord {
                param (
                    $Line
                )

                if (Get-Variable -Name codesAndStuff -Scope 1) {
                    $line2 = (Get-Variable -Name codesAndStuff -Scope 1).Value
                    Remove-Variable -Name codesAndStuff -Scope 1

                    $groups = [regex]::Matches($line2, '^([\d- :]+.\d\d) (\w+)[ ]+Error: (\d+), Severity: (\d+), State: (\d+)').Groups
                    $groups2 = [regex]::Matches($line, '^[\d- :]+.\d\d \w+[ ]+(.*)$').Groups

                    New-Object PSObject -Property @{
                        Timestamp   = [DateTime]::ParseExact($groups[1].Value, "yyyy-MM-dd HH:mm:ss.ff", $null)
                        Spid        = $groups[2].Value
                        Message     = $groups2[1].Value
                        ErrorNumber = [int]($groups[3].Value)
                        Severity    = [int]($groups[4].Value)
                        State       = [int]($groups[5].Value)
                    }
                }

                if ($Line -match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d[\w ]+((\w+): (\d+)[,\.]\s?){3}') {
                    Set-Variable -Name codesAndStuff -Value $Line -Scope 1
                }
            }
            #endregion Helper function

            #region Script that processes an individual file
            $scriptBlock = {
                param (
                    [System.IO.FileInfo]
                    $File
                )

                try {
                    $stream = New-Object System.IO.FileStream($File.FullName, "Open", "Read", "ReadWrite, Delete")
                    $reader = New-Object System.IO.StreamReader($stream)

                    while (-not $reader.EndOfStream) {
                        Convert-ErrorRecord -Line $reader.ReadLine()
                    }
                } catch {
                    # here to avoid an empty catch
                    $null = 1
                }
            }
            #endregion Script that processes an individual file

            #region Gather list of files to process
            $eventSource = "MSSQLSERVER"
            if ($InstanceName -notmatch "^DEFAULT$|^MSSQLSERVER$") {
                $eventSource = 'MSSQL$' + $InstanceName
            }

            $event = Get-WinEvent -FilterHashtable @{
                LogName      = "Application"
                ID           = 17111
                ProviderName = $eventSource
            } -MaxEvents 1 -ErrorAction SilentlyContinue

            if (-not $event) { return }

            $path = $event.Properties[0].Value
            $errorLogPath = Split-Path -Path $path
            $errorLogFileName = Split-Path -Path $path -Leaf
            $errorLogFiles = Get-ChildItem -Path $errorLogPath | Where-Object { ($_.Name -like "$errorLogFileName*") -and ($_.LastWriteTime -gt $Start) -and ($_.CreationTime -lt $End) }
            #endregion Gather list of files to process

            #region Prepare Runspaces
            [Collections.Arraylist]$RunspaceCollection = @()

            $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $Command = Get-Item function:Convert-ErrorRecord
            $InitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($command.Name, $command.Definition)))

            $RunspacePool = [RunspaceFactory]::CreateRunspacePool($InitialSessionState)
            $null = $RunspacePool.SetMinRunspaces(1)
            if ($Throttle -gt 0) { $null = $RunspacePool.SetMaxRunspaces($Throttle) }
            $RunspacePool.Open()
            #endregion Prepare Runspaces

            #region Process Error files
            $countDone = 0
            $countStarted = 0
            $countTotal = ($errorLogFiles | Measure-Object).Count

            while ($countDone -lt $countTotal) {
                while (($RunspacePool.GetAvailableRunspaces() -gt 0) -and ($countStarted -lt $countTotal)) {
                    $Powershell = [PowerShell]::Create().AddScript($scriptBlock).AddParameter("File", $errorLogFiles[$countStarted])
                    $Powershell.RunspacePool = $RunspacePool
                    $null = $RunspaceCollection.Add((New-Object -TypeName PSObject -Property @{ Runspace = $PowerShell.BeginInvoke(); PowerShell = $PowerShell }))
                    $countStarted++
                }

                foreach ($Run in $RunspaceCollection.ToArray()) {
                    if ($Run.Runspace.IsCompleted) {
                        $Run.PowerShell.EndInvoke($Run.Runspace) | Where-Object { ($_.Timestamp -gt $Start) -and ($_.Timestamp -lt $End) }
                        $Run.PowerShell.Dispose()
                        $RunspaceCollection.Remove($Run)
                        $countDone++
                    }
                }

                Start-Sleep -Milliseconds 250
            }
            $RunspacePool.Close()
            $RunspacePool.Dispose()
            #endregion Process Error files
        }

        $scriptBlock_ParallelRemoting = {
            param (
                [DbaInstanceParameter]
                $SqlInstance,

                [DateTime]
                $Start,

                [DateTime]
                $End,

                [PSCredential]
                $Credential,

                [int]
                $MaxRemoteThreads,

                [System.Management.Automation.ScriptBlock]
                $ScriptBlock
            )

            $params = @{
                ArgumentList = $Start, $End, $SqlInstance.InstanceName, $MaxRemoteThreads
                ScriptBlock  = $ScriptBlock
            }
            if (-not $SqlInstance.IsLocalhost) { $params["ComputerName"] = $SqlInstance.ComputerName }
            if ($Credential) { $params["Credential"] = $Credential }

            Invoke-Command @params | Select-Object @{ n = "InstanceName"; e = { $SqlInstance.FullSmoName } }, Timestamp, Spid, Severity, ErrorNumber, State, Message
        }
        #endregion Scriptblocks

        #region Setup Runspace
        [Collections.Arraylist]$RunspaceCollection = @()
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $defaultrunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
        $RunspacePool = [RunspaceFactory]::CreateRunspacePool($InitialSessionState)
        $RunspacePool.SetMinRunspaces(1) | Out-Null
        if ($MaxThreads -gt 0) { $null = $RunspacePool.SetMaxRunspaces($MaxThreads) }
        $RunspacePool.Open()

        $countStarted = 0
        #Variable marked as unused by PSScriptAnalyzer
        #$countReceived = 0
        #endregion Setup Runspace
    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level VeryVerbose -Message "Processing <c='green'>$instance</c>" -Target $instance
            Start-Runspace
            Receive-Runspace
        }
    }

    end {
        Receive-Runspace -Wait
        $RunspacePool.Close()
        $RunspacePool.Dispose()
        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $defaultrunspace
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU0rVFu2/pR65cM8ND8PITIION
# VVagghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFJ+ZogVdrOrLd9TKlD4NTlbVoOaWMA0G
# CSqGSIb3DQEBAQUABIIBAD00hIXIzjwUCaFS5AIbdK2Z27lkwinRXk6aeWDf03oM
# bEfkdeGovWGSpsBRukzfOvaG06SFlp+fMuGKAD+K8cA2+SpoSQSYJ7JTUD2rdFrL
# wfMvf1ycQAlzHRMS5cvUU3YJ3rMsCHR9b2JP+sTFA5rlC8XJuDXMxCbkci7+kzSJ
# swu8783/mY2/pRrtrkFPsQLwxsjvcP99EnH8spUGtktHWyE2Ja5OKjmjh5oJ2K2B
# fKA+bLF8RqJYE2Euud6np0wy4YY0zLEa2fB0j13OKJU/3SsSALYHaKZbLqWJL8AY
# +i7GYZde/H+5age0SMvcUP8klfcUjrLhoQfZu77vWwWhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzQ5WjAvBgkqhkiG9w0BCQQxIgQgXTBJpV6DvQlKDMEJO8np
# cB0Kg0+j1RLVgHP4uJlcVUUwDQYJKoZIhvcNAQEBBQAEggIAEEuFkZ6BhbYkYaaZ
# CYuVhL/FpsA9yp3kfKyJLScR651h4fkIZ1xaP7Xpl96x6b+CqIIJHdkb7Z1quJ1g
# 3EzglRqM9Vtz8PuMlyUdD+8oRkAvy3yZ8+ufDp7s1zQu+YXCoOohhdOVmZrYADPH
# WcUEuRGX/4ufnWzg/cNvIezKMrt/7pBQ/5YDRJD51MXynS4l3Af6g+uUfgWrzlbt
# zoVUUxh8yHyUZef4JKUAnRydMcyl9XoPJ6VsgzOVjZZpeFRJSSBoiAAMZGl3+Av4
# ncXZ6ILf+je6gzX75i1upXv5TAbXf6EBJzeemRtg0PjDsk3+8EpFuX56p4QCr2P0
# M2rCK8bo6yBgV3k3uPIf1G6LL2W+yOYpEcE9ht1NBH/xHsWHfNYPB21DzJ+GR9nI
# 44JIyUNazXqqPRBdWOSN3kkqCMxWwguhCeq6FP77GxhAUtCb4K9F6dUNq4drlqwF
# +8lvCxQGGnC/AhrZEs7aIkag20Jfnj1qhQfm2r485+z7aiDtx/moppfGRXiZf4pu
# uEU9Wyn6ZsTX+4UgGdEK5jK/ZQYd0sihVhvXyMt+dZk5rUZKRagw1t4e/Xxjec2P
# KattmYgATLw5YnG59Lqfmmr+KT9/7swsUVuMJUgBSxCUFgnRWs2pSGiQkp0m5rrG
# TiCQ9edJ9UYH1JUpSkXFxdf6vLA=
# SIG # End signature block
