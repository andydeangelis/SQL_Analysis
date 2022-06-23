function Start-DbaDbEncryption {
    <#
    .SYNOPSIS
        Combo command that encrypts all instances on a database and backs up all keys and certs

    .DESCRIPTION
        Combo command that encrypts all instances on a database and backs up all keys and certs

        * Ensures a database master key exists in the master database and backs it up
        * Ensures a database certificate or asymmetric key exists in the master database and backs it up
        * Creates a database encryption key in the target database and backs it up
        * Enables database encryption on the target database and backs it up

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases that will be encrypted

    .PARAMETER ExcludeDatabase
        The database or databases that will not be encrypted

    .PARAMETER EncryptorName
        The name of the encryptor (Certificate or Asymmetric Key) in master that will be used. Tries to find one if one is not specified.

        In order to encrypt the database encryption key with an asymmetric key, you must use an asymmetric key that resides on an extensible key management provider.

    .PARAMETER EncryptorType
        Type of Encryptor - either Asymmetric or Certificate

    .PARAMETER MasterKeySecurePassword
        A master service key will be created and backed up if one does not exist

        MasterKeySecurePassword is the secure string (password) used to create the key

        This parameter is required even if no master keys are made, as we won't know if master key creation will be required until each server is processed

    .PARAMETER BackupSecurePassword
        This command will perform backups of all maskter keys and certificates. Use this parameter to set the backup password

    .PARAMETER BackupPath
        The path (accessible by and relative to the SQL Server) where master keys and certificates are backed up

    .PARAMETER AllUserDatabases
        Run command against all user databases

        This was added to emphasize that all user databases will be encrypted

    .PARAMETER CertificateSubject
        Optional subject that will be used when creating all certificates

    .PARAMETER CertificateStartDate
        Optional start date that will be used when creating all certificates

        By default, certs will start immediately

    .PARAMETER CertificateExpirationDate
        Optional expiration that will be used when creating all certificates

        By default, certs will last 5 years

    .PARAMETER CertificateActiveForServiceBrokerDialog
        Microsoft has not provided a description so we can only assume the cert is active for service broker dialog

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Start-DbaDbEncryption

    .EXAMPLE
        PS C:\> $masterkeypass = (Get-Credential justneedpassword).Password
        PS C:\> $certbackuppass = (Get-Credential justneedpassword).Password
        PS C:\> $params = @{
        >>      SqlInstance             = "sql01"
        >>      AllUserDatabases        = $true
        >>      MasterKeySecurePassword = $masterkeypass
        >>      BackupSecurePassword    = $certbackuppass
        >>      BackupPath              = "C:\temp"
        >>      EnableException         = $true
        >>  }
        PS C:\> Start-DbaDbEncryption @params

        Prompts for two passwords (the username doesn't matter, this is just an easy & secure way to get a secure password)

        Then encrypts all user databases on sql01, creating master keys and certificates as needed, and backing all of them up to C:\temp, securing them with the password set in $certbackuppass

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$EncryptorName,
        [ValidateSet("AsymmetricKey", "Certificate")]
        [string]$EncryptorType = "Certificate",
        [string[]]$Database,
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [Parameter(Mandatory)]
        [Security.SecureString]$MasterKeySecurePassword,
        [string]$CertificateSubject,
        [datetime]$CertificateStartDate = (Get-Date),
        [datetime]$CertificateExpirationDate = (Get-Date).AddYears(5),
        [switch]$CertificateActiveForServiceBrokerDialog,
        [Parameter(Mandatory)]
        [Security.SecureString]$BackupSecurePassword,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$AllUserDatabases,
        [switch]$EnableException
    )
    process {
        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "You must specify either SqlInstance or pipe in an InputObject from Get-DbaDatabase"
            return
        }

        if ($SqlInstance) {
            if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases) {
                Stop-Function -Message "You must specify Database, ExcludeDatabase or AllUserDatabases when using SqlInstance"
                return
            }
            # all does not need to be addressed in the code because it gets all the dbs if $databases is empty
            $param = @{
                SqlInstance     = $SqlInstance
                SqlCredential   = $SqlCredential
                Database        = $Database
                ExcludeDatabase = $ExcludeDatabase
            }
            $InputObject += Get-DbaDatabase @param | Where-Object Name -NotIn 'master', 'model', 'tempdb', 'msdb', 'resource'
        }

        $PSDefaultParameterValues["Connect-DbaInstance:Verbose"] = $false
        foreach ($db in $InputObject) {
            try {
                # Just in case they use inputobject + exclude
                if ($db.Name -in $ExcludeDatabase) { continue }
                $server = $db.Parent
                # refresh in case we have a stale database
                $null = $db.Refresh()
                $null = $server.Refresh()
                $servername = $server.Name
                $dbname = $db.Name

                if ($db.EncryptionEnabled) {
                    Write-Message -Level Warning -Message "Database $($db.Name) on $($server.Name) is already encrypted"
                    continue
                }

                # before doing anything, see if the master cert is in order
                if ($EncryptorName) {
                    $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -eq $EncryptorName
                } else {
                    $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -NotMatch "##"
                }

                if ($EncryptorName -and -not $mastercert) {
                    Stop-Function -Message "EncryptorName specified but no matching certificate found on $($server.Name)" -Continue
                }

                if ($mastercert.Count -gt 1) {
                    Stop-Function -Message "More than one certificate found on $($server.Name), please specify an EncryptorName" -Continue
                }

                $stepCounter = 0
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Processing $($db.Name)"
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }

            try {
                # Ensure a database master key exists in the master database
                Write-Message -Level Verbose -Message "Ensure a database master key exists in the master database for $($server.Name)"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensure a database master key exists in the master database for $($server.Name)"
                $masterkey = Get-DbaDbMasterKey -SqlInstance $server -Database master

                if (-not $masterkey) {
                    Write-Message -Level Verbose -Message "master key not found, creating one"
                    $params = @{
                        SqlInstance     = $server
                        SecurePassword  = $MasterKeySecurePassword
                        EnableException = $true
                    }
                    $masterkey = New-DbaServiceMasterKey @params
                }

                $null = $db.Refresh()
                $null = $server.Refresh()

                $dbmasterkeytest = Get-DbaFile -SqlInstance $server -Path $BackupPath | Where-Object FileName -match "$servername-master"
                if (-not $dbmasterkeytest) {
                    # has to be repeated in the event databases are piped in
                    $params = @{
                        SqlInstance     = $server
                        Database        = "master"
                        Path            = $BackupPath
                        EnableException = $true
                        SecurePassword  = $BackupSecurePassword
                    }
                    $null = $server.Databases["master"].Refresh()
                    Write-Message -Level Verbose -Message "Backing up master key on $($server.Name)"
                    $null = Backup-DbaDbMasterKey @params
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }

            try {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Processing EncryptorType for $($db.Name) on $($server.Name)"
                if ($EncryptorType -eq "Certificate") {
                    if (-not $mastercert) {
                        Write-Message -Level Verbose -Message "master cert not found, creating one"
                        $params = @{
                            SqlInstance                  = $server
                            Database                     = "master"
                            StartDate                    = $CertificateStartDate
                            ExpirationDate               = $CertificateExpirationDate
                            ActiveForServiceBrokerDialog = $CertificateActiveForServiceBrokerDialog
                            EnableException              = $true
                        }
                        if ($CertificateSubject) {
                            $params.Subject = $CertificateSubject
                        }
                        $mastercert = New-DbaDbCertificate @params
                    } else {
                        Write-Message -Level Verbose -Message "master cert found on $($server.Name)"
                    }

                    $null = $db.Refresh()
                    $null = $server.Refresh()

                    $mastercerttest = Get-DbaFile -SqlInstance $server -Path $BackupPath | Where-Object FileName -match "$($mastercert.Name).cer"
                    if (-not $mastercerttest) {
                        # Back up certificate
                        $null = $server.Databases["master"].Refresh()
                        $params = @{
                            SqlInstance        = $server
                            Database           = "master"
                            Certificate        = $mastercert.Name
                            Path               = $BackupPath
                            EnableException    = $true
                            EncryptionPassword = $BackupSecurePassword
                        }
                        Write-Message -Level Verbose -Message "Backing up master certificate on $($server.Name)"
                        $null = Backup-DbaDbCertificate @params
                    }

                    if (-not $EncryptorName) {
                        Write-Message -Level Verbose -Message "Getting EncryptorName from master cert on $($server.Name)"
                        $EncryptorName = $mastercert.Name
                    }
                } else {
                    $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $server -Database master

                    if (-not $masterasym) {
                        Write-Message -Level Verbose -Message "Asymmetric key not found, creating one for master on $($server.Name)"
                        $params = @{
                            SqlInstance     = $server
                            Database        = "master"
                            EnableException = $true
                        }
                        $masterasym = New-DbaDbAsymmetricKey @params
                        $null = $server.Refresh()
                        $null = $server.Databases["master"].Refresh()
                    } else {
                        Write-Message -Level Verbose -Message "master asymmetric key found on $($server.Name)"
                    }

                    if (-not $EncryptorName) {
                        Write-Message -Level Verbose -Message "Getting EncryptorName from master asymmetric key"
                        $EncryptorName = $masterasym.Name
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }

            try {
                # Create a database encryption key in the target database
                # Enable database encryption on the target database
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating database encryption key in $($db.Name) on $($server.Name)"
                if ($db.HasDatabaseEncryptionKey) {
                    Write-Message -Level Verbose -Message "$($db.Name) on $($db.Parent.Name) already has a database encryption key"
                } else {
                    Write-Message -Level Verbose -Message "Creating new encryption key for $($db.Name) on $($server.Name) with EncryptorName $EncryptorName"
                    $null = $db | New-DbaDbEncryptionKey -EncryptorName $EncryptorName -EnableException
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Enabling database encryption in $($db.Name) on $($server.Name)"
                Write-Message -Level Verbose -Message "Enabling encryption for $($db.Name) on $($server.Name) using $EncryptorType $EncryptorName"
                $db | Enable-DbaDbEncryption -EncryptorName $EncryptorName
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQURriAog8txn9w/zFVS836TYgs
# F0ugghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFA2k7G7ShX2tA4Z6to5msVhVtqz8MA0G
# CSqGSIb3DQEBAQUABIIBALlCpOQMUYfrPSOkXiIMRKXmkgYGMF9Seb49DQ4ukAEj
# ymgZ6zuVy+Ho4ExgeTLS1R4CDX5nSdopdnFxzD4Q2sHiS76CTA7OTjpKLv4MIDjG
# KlkEfW907sTryuFKG/aYftAzjwZ8pRXoLsY4dbjPCmJSsqnsyAz2VCrtRxhRO3dw
# d+8YvehBGmEE7CxyDlJpk66aD6SDg5rxbIsoXGON1RtlqB+r2N1rdR+88uA+uSKo
# Qzvbeaitm9+/oVtiVMN5LCghlhE+tPYfvCn1jKqIOVDmHyONY30NOyvYGoPOW0/9
# ZMEiheb8M+BGaGpkhkhErrTFC9AFySq+F/7aAxRKCDmhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDIzWjAvBgkqhkiG9w0BCQQxIgQgzAA+ZC/t78zAF8YQ9L3g
# 9wlJmWMKcohor/0QHGA6K+YwDQYJKoZIhvcNAQEBBQAEggIAVio40hRLdnU7HKhI
# 0jnktzEocGYwbP1tpsESNUFrMoPhknSaZhTv54ECV5u3Wswqgf/8QWT8+U7jjbSh
# xGYOdTMFAXGgQjacI0nWsWOYjPawdITVTcN1j6ZxUwv8w8tmicna1SQan6x0V+is
# M2+fBrvTYmT/T7yk4ZjImR2/XTpnAZ4F0q4aECNkVjAyGE2jbBC9XxoMTc6cEDvY
# fvLgoR/JPXI0Dti4kBRviiDQr8CS4U4Fp++YPhXsOGejD5hXvjYn+M8rGIcuPkP4
# miFfnaqrG3SavaBx/CnAI6K6NZ79IdDr6kakTd2gM/Y/zv0Imsp2Th3SWXuEQx26
# JNIKJjlInygqs5dUEjNhM6cWcK7Fiz6wHmBCZqCggLoUupBwc7WbW9co0eXpL3D1
# mVO/oCJa8+n1XAUA512Afs8+BWm3Dqx0zIiF09IfAb3+McObRLhSzBSsD41YTn0J
# CSK9S73oloUX4Q8nOqr+3gQwb5ChSJ227k9B/SmlnTOZQPUfhLwV3/bNiHMVeBUd
# LHCUVMTjq1IyXjNs9IeFttBpk4lJtppQUprrJarrm4uQEiESjpqiRd+ylNJ/7e4a
# K3OuRxbgWoJbTBCtlCxzslPW8W0reEUXXQS3kpv6HKMbwIAGZcj4veEdkQHYkbHw
# lf5u1wD+vRMg4X6n4gJXQG3Cses=
# SIG # End signature block
