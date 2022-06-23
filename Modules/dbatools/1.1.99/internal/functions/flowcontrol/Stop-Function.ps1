
function Stop-Function {
    <#
    .SYNOPSIS
        Function that interrupts a function.

    .DESCRIPTION
        Function that interrupts a function.

        This function is a utility function used by other functions to reduce error catching overhead.
        It is designed to allow gracefully terminating a function with a warning by default and also allow opt-in into terminating errors.
        It also allows simple integration into loops.

        Note:
        When calling this function with the intent to terminate the calling function in non-EnableException mode too, you need to add a return below the call.

    .PARAMETER Message
        A message to pass along, explaining just what the error was.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Category
        What category does this termination belong to?
        Mandatory so long as no inner exception is passed.

    .PARAMETER ErrorRecord
        An option to include an inner exception in the error record (and in the exception thrown, if one is thrown).
        Use this, whenever you call Stop-Function in a catch block.

        Note:
        Pass the full error record, not just the exception.

    .PARAMETER Tag
        Tags to add to the message written.
        This allows filtering and grouping by category of message, targeting specific messages.

    .PARAMETER FunctionName
        The name of the function to crash.
        This parameter is very optional, since it automatically selects the name of the calling function.
        The function name is used as part of the errorid.
        That in turn allows easily figuring out, which exception belonged to which function when checking out the $error variable.

    .PARAMETER File
        The file in which Stop-Function was called.
        Will be automatically set, but can be overridden when necessary.

    .PARAMETER Line
        The line on which Stop-Function was called.
        Will be automatically set, but can be overridden when necessary.

    .PARAMETER Target
        The object that was processed when the error was thrown.
        For example, if you were trying to process a Database Server object when the processing failed, add the object here.
        This object will be in the error record (which will be written, even in non-EnableException mode, just won't show it).
        If you specify such an object, it becomes simple to actually figure out, just where things failed at.

    .PARAMETER Exception
        Allows specifying an inner exception as input object. This will be passed on to the logging and used for messages.
        When specifying both ErrorRecord AND Exception, Exception wins, but ErrorRecord is still used for record metadata.

    .PARAMETER OverrideExceptionMessage
        Disables automatic appending of exception messages.
        Use in cases where you already have a speaking message interpretation and do not need the original message.

    .PARAMETER Continue
        This will cause the function to call continue while not running silently.
        Useful when mass-processing items where an error shouldn't break the loop.

    .PARAMETER SilentlyContinue
        This will cause the function to call continue while running silently.
        Useful when mass-processing items where an error shouldn't break the loop.

    .PARAMETER ContinueLabel
        When specifying a label in combination with "-Continue" or "-SilentlyContinue", this function will call continue with this specified label.
        Helpful when trying to continue on an upper level named loop.

    .EXAMPLE
        Stop-Function -Message "Foo failed bar." -EnableException $EnableException -ErrorRecord $_
        return

        Depending on whether $EnableException is true or false it will:
        - Throw a bloody terminating error. Game over.
        - Write a nice warning about how Foo failed bar, then terminate the function. The return on the next line will then end the calling function.

    .EXAMPLE
        Stop-Function -Message "Foo failed bar." -EnableException $EnableException -Category InvalidOperation -Target $foo -Continue

        Depending on whether $silent is true or false it will:
        - Throw a bloody terminating error. Game over.
        - Write a nice warning about how Foo failed bar, then call continue to process the next item in the loop.
        In both cases, the error record added to $error will have the content of $foo added, the better to figure out what went wrong.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Plain')]
    param (
        [Parameter(Mandatory)]
        [string]
        $Message,

        [bool]
        $EnableException = $EnableException,

        [Parameter(ParameterSetName = 'Plain')]
        [Parameter(ParameterSetName = 'Exception')]
        [System.Management.Automation.ErrorCategory]
        $Category = ([System.Management.Automation.ErrorCategory]::NotSpecified),

        [Parameter(ParameterSetName = 'Exception')]
        [Alias('InnerErrorRecord')]
        [System.Management.Automation.ErrorRecord[]]
        $ErrorRecord,

        [string[]]
        $Tag,

        [string]
        $FunctionName = ((Get-PSCallStack)[0].Command),

        [string]
        $File,

        [int]
        $Line,

        [object]
        $Target,

        [System.Exception]
        $Exception,

        [switch]
        $OverrideExceptionMessage,

        [switch]
        $Continue,

        [switch]
        $SilentlyContinue,

        [string]
        $ContinueLabel
    )

    #region Initialize information on the calling command
    $callStack = (Get-PSCallStack)[1]
    $ModuleName = "dbatools"
    if (-not $FunctionName) {
        $FunctionName = $callStack.Command
    }
    if (-not $File) {
        $File = $callStack.Position.File
    }
    if (-not $Line) {
        $Line = $callStack.Position.StartLineNumber
    }

    $instance = $null
    if ($Target -and $FunctionName -match "Connect-.*Instance") {
        $instance = $Target
        $isconnstring = ([DbaInstanceParameter]$instance).IsConnectionString
        if ($isconnstring) {
            $instance = Hide-ConnectionString $instance
        }
    }
    #endregion Initialize information on the calling command

    #region Apply Transforms
    #region Target Transform
    if ($null -ne $Target) {
        $Target = Convert-DbaMessageTarget -Target $Target -FunctionName $FunctionName -ModuleName $ModuleName
    }
    #endregion Target Transform

    #region Exception Transforms
    if ($Exception) {
        $Exception = Convert-DbaMessageException -Exception $Exception -FunctionName $FunctionName -ModuleName $ModuleName
    } elseif ($ErrorRecord) {
        $int = 0
        while ($int -lt $ErrorRecord.Length) {
            $tempException = Convert-DbaMessageException -Exception $ErrorRecord[$int].Exception -FunctionName $FunctionName -ModuleName $ModuleName
            if ($tempException -ne $ErrorRecord[$int].Exception) {
                $ErrorRecord[$int] = New-Object System.Management.Automation.ErrorRecord($tempException, $ErrorRecord[$int].FullyQualifiedErrorId, $ErrorRecord[$int].CategoryInfo.Category, $ErrorRecord[$int].TargetObject)
            }
            $int++
        }
    }
    #endregion Exception Transforms
    #endregion Apply Transforms

    #region Message Handling
    $records = @()

    if ($ErrorRecord -or $Exception) {
        if ($ErrorRecord) {
            foreach ($record in $ErrorRecord) {
                $msg = Get-ErrorMessage -Record $record
                if ($instance) {
                    $msg = "Error connecting to [$instance]: $msg"
                }
                if (-not $Exception) {
                    $newException = New-Object System.Exception($msg, $record.Exception)
                } else {
                    $newException = $Exception
                }

                if ($record.CategoryInfo.Category) {
                    $Category = $record.CategoryInfo.Category
                }

                $records += New-Object System.Management.Automation.ErrorRecord($newException, "$($ModuleName)_$FunctionName", $Category, $Target)
            }
        } else {
            $records += New-Object System.Management.Automation.ErrorRecord($Exception, "$($ModuleName)_$FunctionName", $Category, $Target)
        }

        # Manage Debugging
        if ($EnableException) {
            Write-Message -Level Warning -Message $Message -EnableException $EnableException -FunctionName $FunctionName -Target $Target -ErrorRecord $records -Tag $Tag -ModuleName $ModuleName -OverrideExceptionMessage:$OverrideExceptionMessage -File $File -Line $Line 3>$null
        } else {
            Write-Message -Level Warning -Message $Message -EnableException $EnableException -FunctionName $FunctionName -Target $Target -ErrorRecord $records -Tag $Tag -ModuleName $ModuleName -OverrideExceptionMessage:$OverrideExceptionMessage -File $File -Line $Line
        }
    } else {
        $exception = New-Object System.Exception($Message)
        $records += New-Object System.Management.Automation.ErrorRecord($Exception, "dbatools_$FunctionName", $Category, $Target)

        # Manage Debugging
        if ($EnableException) {
            Write-Message -Level Warning -Message $Message -EnableException $EnableException -FunctionName $FunctionName -Target $Target -ErrorRecord $records -Tag $Tag -ModuleName $ModuleName -OverrideExceptionMessage:$true -File $File -Line $Line 3>$null
        } else {
            Write-Message -Level Warning -Message $Message -EnableException $EnableException -FunctionName $FunctionName -Target $Target -ErrorRecord $records -Tag $Tag -ModuleName $ModuleName -OverrideExceptionMessage:$true -File $File -Line $Line }
    }
    #endregion Message Handling

    #region EnableException Mode
    if ($EnableException) {
        if ($SilentlyContinue) {
            foreach ($record in $records) {
                Write-Error -Message $record -Category $Category -TargetObject $Target -Exception $record.Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue
            }
            if ($ContinueLabel) {
                continue $ContinueLabel
            } else {
                continue
            }
        }

        # Extra insurance that it'll stop
        Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 1 -Value $true

        throw $records[0]
    }
    #endregion EnableException Mode

    #region Non-EnableException Mode
    else {
        # This ensures that the error is stored in the $error variable AND has its Stacktrace (simply adding the record would lack the stacktrace)
        foreach ($record in $records) {
            $null = Write-Error -Message $record -Category $Category -TargetObject $Target -Exception $record.Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue 2>&1
        }

        if ($Continue) {
            if ($ContinueLabel) {
                continue $ContinueLabel
            } else {
                continue
            }
        } else {
            # Make sure the function knows it should be stopping
            Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 1 -Value $true

            return
        }
    }
    #endregion Non-EnableException Mode
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU7XvnOv4wYHbGZ529jYM+fpAV
# q2egghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPKA3K26aShdG9ayX+IsjRb59JErMA0G
# CSqGSIb3DQEBAQUABIIBAFGFKdY4XaNXuiFQxbx50G9Uf5tTqYMr/qj7AkXJKM5W
# r0OOko+4x9I4laHosboVaiosvte9Al+gzuO/gWEidxxU4auGxoSYKODPbMjRaIv8
# 2sNAg3indxHxGtlz72l2kM4q1cvOur5HMxlKBjw3Nt0GTD3on9xurHk2WwNmQIRd
# kcvam4UleZp1U7/QPE5OL16KB6luSYgIdctylEHFCvCE/wggxpMKAyFJIZPyKCRm
# nwzia5A3pNYWnHOBMdZudZbNLucOKiHl6b4dr/uOKDH+Tcxeqq0jeir5vP4EmQlq
# jxi3zRnYhhzhVRkowup4rq+PKIjQLt815w6oYu2iQ0ChggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDQyWjAvBgkqhkiG9w0BCQQxIgQg9zo3OcHLkfKOvTO4RNHY
# NjTEd2lMIKKkvFqf7kenXU0wDQYJKoZIhvcNAQEBBQAEggIAgOooGGOG6iFpRy3H
# oixelszhnaLwMh4DJ1cTISw6k8btNivZlltOik+2Q4yfOvHB4/qZNq3qcb5+tAS5
# xo13quVmycxmJ1oCEZHiMtzdC5PoByURys+k9XcfpVe06r1D2AXKoo405rOH4k4D
# Rlx/sbWYJLNoi2YdhDb+e5GhSqtv3K5zNFyCKIiPGr7YH5qaLr8fFdPOqAeQlxXZ
# TRbD5B6hYjRnMzdL+2ZGDAzMW+gNs38i8c3JnDQf+NnKEjgV0Rfnjrqh3o79lg04
# 2rkUsYWrMm7W0eYwiI0STgzprEvSS2nFfTDzPdjOZNv4B5nhiK26R58xjyX8X98u
# oMvjPu9J6xb2t4VcwTYmm1s+pJUw7xrqXFtq64Ile8hO9notgfSzirs1UeEX4MqR
# +i97IYfKID/Z+dhrBXSDfW2lrbXI35uJdYtnNCFmxXFUMQlC3VbPnTMZXj+a9spi
# slYDzCAqmIa7pj1Yc0Li4DU9l1auukU5oJ+RjBuP75w4bUhvkB/mogb1GSJgxi0F
# cJRef/jfSio7WYtt4Au/kVNsCpjEyHYUlQHbo6MPETG/W+D01T2mnruR4LVSqvQz
# k+hjkiDD/PtMxDRtjT1wEDxsvgLRV8Fv2IX6bh+uS/wMhK2PA49ovulrQ3VhZ9Q0
# Sc8kp6awhUHPZ/DzL6N6+lLId24=
# SIG # End signature block
