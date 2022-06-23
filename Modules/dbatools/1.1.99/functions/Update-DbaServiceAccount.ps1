function Update-DbaServiceAccount {
    <#
    .SYNOPSIS
        Changes service account (or just its password) of the SQL Server service.

    .DESCRIPTION
        Reconfigure the service account or update the password of the specified SQL Server service. The service will be restarted in the event of changing the account.

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Windows Credential with permission to log on to the server running the SQL instance

    .PARAMETER InputObject
        A collection of services. Basically, any object that has ComputerName and ServiceName properties. Can be piped from Get-DbaService.

    .PARAMETER ServiceName
        A name of the service on which the action is performed. E.g. MSSQLSERVER or SqlAgent$INSTANCENAME

    .PARAMETER ServiceCredential
        Windows Credential object under which the service will be setup to run. Cannot be used with -Username. For local service accounts use one of the following usernames with empty password:
        LOCALSERVICE
        NETWORKSERVICE
        LOCALSYSTEM

    .PARAMETER PreviousPassword
        An old password of the service account. Optional when run under local admin privileges.

    .PARAMETER SecurePassword
        New password of the service account. The function will ask for a password if not specified. MSAs and local system accounts will ignore the password.

    .PARAMETER Username
        Username of the service account. Cannot be used with -ServiceCredential. For local service accounts use one of the following usernames omitting the -SecurePassword parameter:
        LOCALSERVICE
        NETWORKSERVICE
        LOCALSYSTEM

    .PARAMETER NoRestart
        Do not immediately restart the service after changing the password.

        **Note that the changes will not go into effect until you restart the SQL Services**

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .LINK
        https://dbatools.io/Update-DbaServiceAccount

    .NOTES
        Tags: Service, SqlServer, Instance, Connect
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Local Admin rights on destination computer(s).

    .EXAMPLE
        PS C:\> $SecurePassword = ConvertTo-SecureString 'Qwerty1234' -AsPlainText -Force
        PS C:\> Update-DbaServiceAccount -ComputerName sql1 -ServiceName 'MSSQL$MYINSTANCE' -SecurePassword $SecurePassword

        Changes the current service account's password of the service MSSQL$MYINSTANCE to 'Qwerty1234'

    .EXAMPLE
        PS C:\> $cred = Get-Credential
        PS C:\> Get-DbaService sql1 -Type Engine,Agent -Instance MYINSTANCE | Update-DbaServiceAccount -ServiceCredential $cred

        Requests credentials from the user and configures them as a service account for the SQL Server engine and agent services of the instance sql1\MYINSTANCE

    .EXAMPLE
        PS C:\> Update-DbaServiceAccount -ComputerName sql1,sql2 -ServiceName 'MSSQLSERVER','SQLSERVERAGENT' -Username NETWORKSERVICE

        Configures SQL Server engine and agent services on the machines sql1 and sql2 to run under Network Service system user.

    .EXAMPLE
        PS C:\> Get-DbaService sql1 -Type Engine -Instance MSSQLSERVER | Update-DbaServiceAccount -Username 'MyDomain\sqluser1'

        Configures SQL Server engine service on the machine sql1 to run under MyDomain\sqluser1. Will request user to input the account password.


    .EXAMPLE
        PS C:\> Get-DbaService sql1 -Type Engine -Instance MSSQLSERVER | Update-DbaServiceAccount -Username 'MyDomain\sqluser1' -NoRestart

        Configures SQL Server engine service on the machine sql1 to run under MyDomain\sqluser1. Will request user to input the account password.

        Will not restart, which means the changes will not go into effect, so you will still have to restart during your planned outage window.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "ServiceName" )]
    param (
        [parameter(ParameterSetName = "ServiceName")]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "InputObject")]
        [Alias("ServiceCollection")]
        [object[]]$InputObject,
        [parameter(ParameterSetName = "ServiceName", Position = 1, Mandatory)]
        [Alias("Name", "Service")]
        [string[]]$ServiceName,
        [Alias("User")]
        [string]$Username,
        [PSCredential]$ServiceCredential,
        [securestring]$PreviousPassword = (New-Object System.Security.SecureString),
        [Alias("Password", "NewPassword")]
        [securestring]$SecurePassword = (New-Object System.Security.SecureString),
        [switch]$NoRestart,
        [switch]$EnableException
    )
    begin {
        $svcCollection = @()
        $scriptAccountChange = {
            $service = $wmi.Services[$args[0]]
            $service.SetServiceAccount($args[1], $args[2])
            $service.Alter()
        }
        $scriptPasswordChange = {
            $service = $wmi.Services[$args[0]]
            $service.ChangePassword($args[1], $args[2])
            $service.Alter()
        }
        #Check parameters
        if ($Username) {
            $actionType = 'Account'
            if ($ServiceCredential) {
                Stop-Function -EnableException $EnableException -Message "You cannot specify both -UserName and -ServiceCredential parameters" -Category InvalidArgument
                return
            }
            #System logins should not have a domain name, whitespaces or passwords
            $trimmedUsername = (Split-Path $Username -Leaf).Trim().Replace(' ', '')
            #Request password input if password was not specified and account is not MSA or system login
            if ($SecurePassword.Length -eq 0 -and $PSBoundParameters.Keys -notcontains 'SecurePassword' -and $trimmedUsername -notin 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE' -and $Username.EndsWith('$') -eq $false -and $Username.StartsWith('NT Service\') -eq $false) {
                $SecurePassword = Read-Host -Prompt "Input new password for account $UserName" -AsSecureString
                $NewPassword2 = Read-Host -Prompt "Repeat password" -AsSecureString
                if ((New-Object System.Management.Automation.PSCredential ("user", $SecurePassword)).GetNetworkCredential().Password -ne `
                    (New-Object System.Management.Automation.PSCredential ("user", $NewPassword2)).GetNetworkCredential().Password) {
                    Stop-Function -Message "Passwords do not match" -Category InvalidArgument -EnableException $EnableException
                    return
                }
            }
            $currentCredential = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)
        } elseif ($ServiceCredential) {
            $actionType = 'Account'
            $currentCredential = $ServiceCredential
        } else {
            $actionType = 'Password'
        }
        if ($actionType -eq 'Account') {
            #System logins should not have a domain name, whitespaces or passwords
            $credUserName = (Split-Path $currentCredential.UserName -Leaf).Trim().Replace(' ', '')
            #Check for system logins and replace the Credential object to simplify passing localsystem-like login names
            if ($credUserName -in 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE') {
                $currentCredential = New-Object System.Management.Automation.PSCredential ($credUserName, (New-Object System.Security.SecureString))
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($PsCmdlet.ParameterSetName -match 'ServiceName') {
            foreach ($Computer in $ComputerName.ComputerName) {
                $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
                if ($Server.FullComputerName) {
                    foreach ($service in $ServiceName) {
                        $svcCollection += [psobject]@{
                            ComputerName = $server.FullComputerName
                            ServiceName  = $service
                        }
                    }
                } else {
                    Stop-Function -EnableException $EnableException -Message "Failed to connect to $Computer" -Continue
                }
            }
        } elseif ($PsCmdlet.ParameterSetName -match 'InputObject') {
            foreach ($service in $InputObject) {
                if ($service.ServiceName -eq 'PowerBIReportServer') {
                    Stop-Function -Message "PowerBIReportServer service is not supported, skipping." -Continue
                } else {
                    $Server = Resolve-DbaNetworkName -ComputerName $service.ComputerName -Credential $credential
                    if ($Server.FullComputerName) {
                        $svcCollection += [psobject]@{
                            ComputerName = $Server.FullComputerName
                            ServiceName  = $service.ServiceName
                        }
                    } else {
                        Stop-Function -EnableException $EnableException -Message "Failed to connect to $($service.FullComputerName)" -Continue
                    }
                }
            }
        }

    }
    end {
        foreach ($svc in $svcCollection) {
            if ($serviceObject = Get-DbaService -ComputerName $svc.ComputerName -ServiceName $svc.ServiceName -Credential $Credential -EnableException:$EnableException) {
                $outMessage = $outStatus = $agent = $null
                if ($actionType -eq 'Password' -and $SecurePassword.Length -eq 0) {
                    $currentPassword = Read-Host -Prompt "New password for $($serviceObject.StartName) ($($svc.ServiceName) on $($svc.ComputerName))" -AsSecureString
                    $currentPassword2 = Read-Host -Prompt "Repeat password" -AsSecureString
                    if ((New-Object System.Management.Automation.PSCredential ("user", $currentPassword)).GetNetworkCredential().Password -ne `
                        (New-Object System.Management.Automation.PSCredential ("user", $currentPassword2)).GetNetworkCredential().Password) {
                        Stop-Function -Message "Passwords do not match. This service will not be updated" -Category InvalidArgument -EnableException $EnableException -Continue
                    }
                } else {
                    $currentPassword = $SecurePassword
                }
                if ($serviceObject.ServiceType -eq 'Engine') {
                    #Get SQL Agent running status
                    $agent = Get-DbaService -ComputerName $svc.ComputerName -Type Agent -InstanceName $serviceObject.InstanceName
                }
                if ($PsCmdlet.ShouldProcess($serviceObject, "Changing account information for service $($svc.ServiceName) on $($svc.ComputerName)")) {
                    try {
                        if ($actionType -eq 'Account') {
                            # Test if a certificate is used. If so, remove it and set it again later.
                            $certificate = $null
                            if ($serviceObject.ServiceType -eq 'Engine') {
                                $sqlInstance = $svc.ComputerName
                                if ($svc.ServiceName -ne 'MSSQLSERVER') {
                                    $instanceName = $svc.ServiceName -replace '^MSSQL\$', ''
                                    $sqlInstance += '\' + $instanceName
                                }
                                # We try to get the certificate, but don't fail in case we are not able to.
                                $certificate = Get-DbaNetworkConfiguration -SqlInstance $sqlInstance -Credential $Credential -OutputType Certificate
                                if ($certificate.Thumbprint) {
                                    Write-Message -Level Verbose -Message "Removing certificate from service $($svc.ServiceName) on $($svc.ComputerName)"
                                    $null = Remove-DbaNetworkCertificate -SqlInstance $sqlInstance -Credential $Credential -EnableException
                                }
                            }
                            Write-Message -Level Verbose -Message "Attempting an account change for service $($svc.ServiceName) on $($svc.ComputerName)"
                            $null = Invoke-ManagedComputerCommand -ComputerName $svc.ComputerName -Credential $Credential -ScriptBlock $scriptAccountChange -ArgumentList @($svc.ServiceName, $currentCredential.UserName, $currentCredential.GetNetworkCredential().Password) -EnableException:$EnableException
                            $outMessage = "The login account for the service has been successfully set."
                            if ($certificate.Thumbprint) {
                                Write-Message -Level Verbose -Message "Setting certificate for service $($svc.ServiceName) on $($svc.ComputerName)"
                                $null = Set-DbaNetworkCertificate -SqlInstance $sqlInstance -Credential $Credential -Thumbprint $certificate.Thumbprint -EnableException
                            }
                        } elseif ($actionType -eq 'Password') {
                            Write-Message -Level Verbose -Message "Attempting a password change for service $($svc.ServiceName) on $($svc.ComputerName)"
                            $null = Invoke-ManagedComputerCommand -ComputerName $svc.ComputerName -Credential $Credential -ScriptBlock $scriptPasswordChange -ArgumentList @($svc.ServiceName, (New-Object System.Management.Automation.PSCredential ("user", $PreviousPassword)).GetNetworkCredential().Password, (New-Object System.Management.Automation.PSCredential ("user", $currentPassword)).GetNetworkCredential().Password) -EnableException:$EnableException
                            $outMessage = "The password has been successfully changed."
                        }
                        $outStatus = 'Successful'
                    } catch {
                        $outStatus = 'Failed'
                        $outMessage = $_.Exception.Message
                        if ($certificate.Thumbprint) {
                            # Depending on where the process failed, the certificate might be already removed but not yet set again.
                            $outMessage += " Please check if certificate with thumbprint $($certificate.Thumbprint) is still in place."
                        }
                        Stop-Function -Message $outMessage -Continue
                    }
                } else {
                    $outStatus = 'Successful'
                    $outMessage = 'No changes made - running in -WhatIf mode.'
                }
                if ($serviceObject.ServiceType -eq 'Engine' -and $actionType -eq 'Account' -and $outStatus -eq 'Successful' -and $agent.State -eq 'Running' -and -not $NoRestart) {
                    #Restart SQL Agent after SQL Engine has been restarted
                    if ($PsCmdlet.ShouldProcess($serviceObject, "Starting SQL Agent after Engine account change on $($svc.ComputerName)")) {
                        $res = Start-DbaService -ComputerName $svc.ComputerName -Type Agent -InstanceName $serviceObject.InstanceName
                        if ($res.Status -ne 'Successful') {
                            Write-Message -Level Warning -Message "Failed to restart SQL Agent after changing credentials. $($res.Message)"
                        }
                    }
                }
                if ($NoRestart) {
                    Write-Message -Level Warning -Message "Changes will not go into effect until you restart. Please restart the services manually during your designated outage window."
                }
                $serviceObject = Get-DbaService -ComputerName $svc.ComputerName -ServiceName $svc.ServiceName -Credential $Credential -EnableException:$EnableException
                Add-Member -Force -InputObject $serviceObject -NotePropertyName Message -NotePropertyValue $outMessage
                Add-Member -Force -InputObject $serviceObject -NotePropertyName Status -NotePropertyValue $outStatus
                Select-DefaultView -InputObject $serviceObject -Property ComputerName, ServiceName, State, StartName, Status, Message
            } Else {
                Stop-Function -Message "The service $($svc.ServiceName) has not been found on $($svc.ComputerName)" -EnableException $EnableException -Continue
            }
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUYaeJfwxEvjUtuzsZpPChxMLZ
# K/mgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFF+joie/nM7HoqMgGlwCvskJWZ29MA0G
# CSqGSIb3DQEBAQUABIIBAI6HHjBnbaIa5mPK9RF+EtcoVmkpC96I5nfuFtrPmpUr
# QoujOSgmbCw3JCdq5S8QflsdpPd+1L+gytKLlbekP8pLL6g+krQ23iONmgFj6xj/
# y4POMe98bhJwnwRFnkkJn+/L5VUzfLpltKQ2KZMgURlfUzzx4UYfCtMjVga2D1a2
# mFeevw4OxieWpdEnzBhe7PxyKRjLFesRl847yOIqDNvRXFyFOJoD+bRqyjycLv+Y
# zy5fSjpA4a0y/gDxdypBgPdCeK8QXn6CdRD3m3XhU+MloEtOQMJIbAfG+xgZrf1u
# qav5MMxH1FKfP4wMT/pScVWO82Bk0wzyrm3MWQ3jrrihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDMyWjAvBgkqhkiG9w0BCQQxIgQgiDbt6pJjJUT1y4QcV2pj
# UdXqqIsoeBz4cFXPQrnu0EQwDQYJKoZIhvcNAQEBBQAEggIAORE7IuElYQZGXu6E
# jJkuyzgtXw/Eeflo7IqImK6D7iXxLiG2SWSn2+tzslatvvNya/POs8OCKnZa6XiB
# TcY9VW4qSOotP9icnDwcDO/FBv3heAgtAgjJy9fBTl1vOg3bcCaQSsQQdorgiIxM
# vi9GG+cy62Rx0gBT2C9accJYajw7Slfmo3+iDUdGCDfMTTfQTnBRjFk54HGLxjus
# Igb0ICed/cnafAqXaTRQqIzkhvyzNZHA49Eb/L7UraFkZweH2emIuEptpEFr2VPf
# PiyYXqO3B4wMJf8FGPuE/x1kyEZsEJPvXzigJYAMsQDwVxxcIOEZhIpzJgb4zLSy
# 0Afmv8Yy8sVp59xepIsux9MgUlbCU2nYqYe5ph2+3oxJRSzdMqo5ITYG02pWQ3lK
# qC1onMP8ywfjjI4w5u1Q4zTlS1TSxRGuKL1tquR2tVOtict1KRoK3d/IKE7N4EBW
# 4PQFlJ8CC+65cJsi+kA+DzaiysGRwy5+p6YFYCFlahwi7EYvWXB/Gzx9tPqB3Z+2
# ciNdwe1y8xPJj3ViZRWezWH0yJ5dvOkwAnyPJ/F8OQS1GJLSOr5Yd2+cLNHX5eZ3
# TsKck5gl/J2tODjdtwfImd91kOGXunpAxqkJids9CswuvXwztWv1m+ZC7Z+p/DQc
# U8GYlQXWGAN+LPA3MIIqJ8YAjxo=
# SIG # End signature block
