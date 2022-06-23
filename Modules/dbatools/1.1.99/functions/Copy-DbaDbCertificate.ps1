function Copy-DbaDbCertificate {
    <#
    .SYNOPSIS
        Copy-DbaDbCertificate migrates certificates from one SQL Server to another.

    .DESCRIPTION
        By default, all certificates are copied.

        If the certificate already exists on the destination, it will be skipped.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER Certificate
        The certificate(s) to process.

    .PARAMETER ExcludeCertificate
        The certificate(s) to exclude.

    .PARAMETER SharedPath
        Specifies the network location for the backup files. The SQL Server service accounts on both Source and Destination must have read/write permission to access this location.

    .PARAMETER EncryptionPassword
        A string value that specifies the secure password to encrypt the private key.

    .PARAMETER DecryptionPassword
        Secure string used to decrypt the private key.

    .PARAMETER MasterKeyPassword
        The password to encrypt the exported key. This must be a SecureString.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing certificates on Destination with matching names from Source will be dropped.

    .NOTES
        Tags: Migration, Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaDbCertificate

    .EXAMPLE
        PS C:\> $params1 = @{
        >>      Source = "sql01"
        >>      Destination = "sql02"
        >>      EncryptionPassword = $passwd
        >>      MasterKeyPassword = $passwd
        >>      SharedPath = "\\nas\sql\shared"
        >>  }
        PS C:\> Copy-DbaDbCertificate @params1 -Confirm:$false -OutVariable results

        Copies database certificates for matching databases on sql02 and creates master keys if needed

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Certificate,
        [string[]]$ExcludeCertificate,
        [string]$SharedPath,
        [Security.SecureString]$MasterKeyPassword,
        [Security.SecureString]$EncryptionPassword,
        [Security.SecureString]$DecryptionPassword,
        [switch]$EnableException
    )
    begin {
        try {
            $parms = @{
                SqlInstance     = $Source
                SqlCredential   = $SourceSqlCredential
                Database        = $Database
                ExcludeDatabase = $ExcludeDatabase
                Certificate     = $Certificate
                EnableException = $true
            }
            # Get presumably user certs, no way to tell if its a system object
            $sourcecertificates = Get-DbaDbCertificate @parms | Where-Object { $PSItem.Name -notlike "#*" -and $PSItem.Name -notin $ExcludeCertificate }
            $dbsnames = $sourcecertificates.Parent.Name | Select-Object -Unique
            $server = ($sourcecertificates | Select-Object -First 1).Parent.Parent
            $serviceAccount = $server.ServiceAccount
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $PSItem -Target $Source
            return
        }

        if (-not $PSBoundParameter.EncryptionPassword) {
            $backupEncryptionPassword = Get-RandomPassword
        } else {
            $backupEncryptionPassword = $EncryptionPassword
        }

        If ($serviceAccount -and -not (Test-DbaPath -SqlInstance $Source -SqlCredential $SourceSqlCredential -Path $SharedPath)) {
            Stop-Function -Message "The SQL Server service account ($serviceAccount) for $Source does not have access to $SharedPath"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $PSItem -Target $destinstance -Continue
            }
            $serviceAccount = $destserver.ServiceAccount

            If (-not (Test-DbaPath -SqlInstance $destServer -Path $SharedPath)) {
                Stop-Function -Message "The SQL Server service account ($serviceAccount) for $destinstance does not have access to $SharedPath" -Continue
            }

            if (($sourcecertificates | Where-Object PrivateKeyEncryptionType -eq MasterKey)) {
                $masterkey = Get-DbaDbMasterKey -SqlInstance $destServer -Database master
                if (-not $masterkey) {
                    Write-Message -Level Verbose -Message "master key not found, seeing if MasterKeyPassword was specified"
                    if ($MasterKeyPassword) {
                        Write-Message -Level Verbose -Message "master key not found, creating one"
                        try {
                            $params = @{
                                SqlInstance     = $destServer
                                SecurePassword  = $MasterKeyPassword
                                Database        = "master"
                                EnableException = $true
                            }
                            $masterkey = New-DbaDbMasterKey @params
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $PSItem -Continue
                        }
                    } else {
                        Stop-Function -Message "Master service key not found on $destinstance and MasterKeyPassword not specified, so it cannot be created" -Continue
                    }
                }
                $null = $destServer.Databases["master"].Refresh()
            }

            $destdbs = $destServer.Databases | Where-Object Name -in $dbsnames

            foreach ($db in $destdbs) {
                $dbName = $db.Name
                $sourcerts = $sourcecertificates | Where-Object { $PSItem.Parent.Name -eq $db.Name }

                # Check for master key requirement
                if (($sourcerts | Where-Object PrivateKeyEncryptionType -eq MasterKey)) {
                    $masterkey = Get-DbaDbMasterKey -SqlInstance $db.Parent -Database $db.Name

                    if (-not $masterkey) {
                        Write-Message -Level Verbose -Message "Master key not found, seeing if MasterKeyPassword was specified"
                        if ($MasterKeyPassword) {
                            try {
                                $params = @{
                                    SqlInstance     = $destServer
                                    SecurePassword  = $MasterKeyPassword
                                    Database        = $db.Name
                                    EnableException = $true
                                }
                                $masterkey = New-DbaDbMasterKey @params
                                $domasterkeymessage = $false
                                $domasterkeypasswordmessage = $false
                            } catch {
                                $domasterkeymessage = "Master key auto-generation failure: $PSItem"
                                Stop-Function -Message "Failure" -ErrorRecord $PSItem -Continue
                            }

                        } else {
                            $domasterkeypasswordmessage = $true
                        }
                    }

                    foreach ($cert in $sourcerts) {
                        $certname = $cert.Name
                        Write-Message -Level VeryVerbose -Message "Processing $certname on $dbName"

                        $copyDbCertificateStatus = [pscustomobject]@{
                            SourceServer          = $Source
                            SourceDatabase        = $dbName
                            SourceDatabaseID      = $cert.Parent.ID
                            DestinationServer     = $destServer.Name
                            DestinationDatabase   = $dbName
                            DestinationDatabaseID = $db.ID
                            type                  = "Database Certificate"
                            Name                  = $certname
                            Status                = $null
                            Notes                 = $null
                            DateTime              = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }

                        if ($domasterkeymessage) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = $domasterkeymessage
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message $domasterkeymessage
                            continue
                        }

                        if ($domasterkeypasswordmessage) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = "Master service key not found and MasterKeyPassword not provided for auto-creation"
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Master service key not found and MasterKeyPassword not provided for auto-creation"
                            continue
                        }
                        $null = $db.Refresh()
                        if ($db.Certificates.Name -contains $certname) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = "Already exists on destination"
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Certificate $certname exists at destination in the $dbName database"
                            continue
                        }

                        if ($Pscmdlet.ShouldProcess($destinstance.Name, "Copying certificate $certname from database.")) {
                            try {
                                # Back up certificate
                                $null = $db.Refresh()
                                $params = @{
                                    SqlInstance        = $cert.Parent.Parent
                                    Database           = $db.Name
                                    Certificate        = $certname
                                    Path               = $SharedPath
                                    EnableException    = $true
                                    EncryptionPassword = $backupEncryptionPassword
                                    DecryptionPassword = $DecryptionPassword
                                }
                                Write-Message -Level Verbose -Message "Backing up certificate $cername for $($dbName) on $($server.Name)"
                                try {
                                    $tempPath = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.cer"
                                    $tempKey = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.pvk"

                                    if ((Test-DbaPath -SqlInstance $server -Path $tempPath) -and (Test-DbaPath -SqlInstance $server -Path $tempKey)) {
                                        $export = [pscustomobject]@{
                                            Path = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.cer"
                                            Key  = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.pvk"
                                        }
                                        # if files exist, then try to be helpful, otherwise, it just kills the whole process
                                        # this workaround exists because if you rename the back file, you'll rename the cert on restore
                                        Write-Message -Level Verbose -Message "ATTEMPTING TO USE FILES THAT ALREADY EXIST: $tempPath and $tempKey"
                                        $usingtempfiles = $true
                                    } else {
                                        $export = Backup-DbaDbCertificate @params
                                    }
                                } catch {
                                    $copyDbCertificateStatus.Status = "Failed $PSItem"
                                    $copyDbCertificateStatus.Notes = $PSItem
                                    $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Stop-Function -Message "Issue backing up certificate $certname in $dbname on $($db.Parent.Name)" -Target $certname -ErrorRecord $PSItem -Continue
                                }

                                # Restore certificate
                                $params = @{
                                    SqlInstance        = $db.Parent
                                    Database           = $db.Name
                                    Name               = $export.Certificate
                                    Path               = $export.Path
                                    KeyFilePath        = $export.Key
                                    EnableException    = $true
                                    EncryptionPassword = $DecryptionPassword
                                    DecryptionPassword = $backupEncryptionPassword
                                }

                                $null = Restore-DbaDbCertificate @params
                                $copyDbCertificateStatus.Status = "Successful"
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            } catch {
                                if ($export.Path) {
                                    $null = Remove-Item -Force $export.Path -ErrorAction SilentlyContinue
                                }
                                if ($export.Key) {
                                    $null = Remove-Item -Force $export.Key -ErrorAction SilentlyContinue
                                }
                                $copyDbCertificateStatus.Status = "Failed"
                                $copyDbCertificateStatus.Notes = $PSItem
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                if ($usingtempfiles) {
                                    Stop-Function -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name). Note that $($export.Path) and $($export.Key) already existed so we tried to use them. If this is an issue, please move or rename both files and try again." -Target $certname -ErrorRecord $PSItem
                                } else {
                                    Stop-Function -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name)" -Target $certname -ErrorRecord $PSItem
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUiBJ04ArBmsFcrUfX46YJUKpw
# vbGgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFIuomVoKbjyXCQ9aLv+SIP0ymYupMA0G
# CSqGSIb3DQEBAQUABIIBAJhlz5rXzm9RNjGyQdT7np4IgJGvkL3v9Gw5OToQql6R
# 0QQuQ6vIHcN11Cln2fAW8RTVVPWxRUFU/2aMWqOEkqHaqXIZ1qs0ALUgLy7J6WFI
# XHNtUHfLdNKY69BTIsy9FkeVnJIq9XB5+NAwsiuxityKKOC5dBumcnWUTVE3swPJ
# sx9JGg6rIrK9qr29mbCA2/M5x+STo96LU6fr1gb+zc7bFuIMymaxt0fbmaJ0wRTv
# CMQFT6JO2xkpVOftyFn9O/wTR2/B/xBSpGoI2axuTkO0c6THyYmwI5UkEykio6ZS
# KueaCMs5vESyRSzF2AAWBkbXIijHqeCWJtKctNKvyVihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzEyWjAvBgkqhkiG9w0BCQQxIgQg6BC/6Z4CNbvPaV1o+PGT
# PBtQaiBA/1JORRpnd7wOqZEwDQYJKoZIhvcNAQEBBQAEggIABGEqH5xioIcQoPah
# iaXGBQdrLVa8tPGZ6rq30mUgXYGgsziZleM60nr2S0ab460O3+ZAo7JX1CU/Qz+B
# jiSi//pSL41W8hzd74OhPybJ6hMZmWIPKCp3awSAcJ6m3pE0li5NYK7yMNq12JOL
# hZPK3f8T0D37EynmV06yF+mDn7oc+/+/O/A/2WjX5mYBO+Pew+m3qymxAOIMmJGc
# uu245PhDYlGBfJWnqVul3i5jpA+GMYy0ruM4pDe07vFOzyDoWaiBukxgIc22BbTY
# 2SKfESRokZhbyEg9uqo+kGhilBamZZrO8HVHUtRZfDF2AItE5PGoIDkXrV/eeFNa
# DRXcZhOHSxd0jIhpBs83SiIFVY3Z+uJ5VDcPI6ASn+Pr497iTHtZA9ekxIRjJQ2Y
# 8sTI44Du/OhQKOxg2K8YoBQtXS4LV4/GpqrdgER2Gn4bOudxGF6D+nqilWFnNy79
# /NxrrrnTVp4PKmtkKSqiayiOf7SV3eToN+b3lYGx6XyD1S+RrglYJM4wdEww9qEK
# Xo0AninGt1bP1Nl5aQl2Ocwkvf+R9r6AVY3KMFS5dvQnrRInHWUs+3tl8vN6toCO
# C/60ENj4y8qrAVKGmM4vh6xc54HD8AiemhoRhNq/Wu3fkSF0RLvfk2vjbGAgT8qb
# TFYlEbU5UZf76NSeXSg4KB+v/8w=
# SIG # End signature block
