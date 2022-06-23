function New-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Creates a new computer certificate useful for Forcing Encryption

    .DESCRIPTION
        Creates a new computer certificate - self-signed or signed by an Active Directory CA, using the Web Server certificate.

        By default, a key with a length of 1024 and a friendly name of the machines FQDN is generated.

        This command was originally intended to help automate the process so that SSL certificates can be available for enforcing encryption on connections.

        It makes a lot of assumptions - namely, that your account is allowed to auto-enroll and that you have permission to do everything it needs to do ;)

        References:
        https://www.itprotoday.com/sql-server/7-steps-ssl-encryption
        https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
        https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/

        The certificate is generated using AD's webserver SSL template on the client machine and pushed to the remote machine.

    .PARAMETER ComputerName
        The target SQL Server instance or instances. Defaults to localhost. If target is a cluster, you must also specify ClusterInstanceName (see below)

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER CaServer
        Optional - the CA Server where the request will be sent to

    .PARAMETER CaName
        The properly formatted CA name of the corresponding CaServer

    .PARAMETER ClusterInstanceName
        When creating certs for a cluster, use this parameter to create the certificate for the cluster node name. Use ComputerName for each of the nodes.

    .PARAMETER SecurePassword
        Password to encrypt/decrypt private key for export to remote machine

    .PARAMETER FriendlyName
        The FriendlyName listed in the certificate. This defaults to the FQDN of the $ComputerName

    .PARAMETER CertificateTemplate
        The domain's Certificate Template - WebServer by default.

    .PARAMETER KeyLength
        The length of the key - defaults to 1024

    .PARAMETER Store
        Certificate store - defaults to LocalMachine

    .PARAMETER Folder
        Certificate folder - defaults to My (Personal)

    .PARAMETER Flag
        Defines where and how to import the private key of an X.509 certificate.

        Defaults to: Exportable, PersistKeySet

            EphemeralKeySet
            The key associated with a PFX file is created in memory and not persisted on disk when importing a certificate.

            Exportable
            Imported keys are marked as exportable.

            NonExportable
            Expliictly mark keys as nonexportable.

            PersistKeySet
            The key associated with a PFX file is persisted when importing a certificate.

            UserProtected
            Notify the user through a dialog box or other method that the key is accessed. The Cryptographic Service Provider (CSP) in use defines the precise behavior. NOTE: This can only be used when you add a certificate to localhost, as it causes a prompt to appear.

    .PARAMETER Dns
        Specify the Dns entries listed in SAN. By default, it will be ComputerName + FQDN, or in the case of clusters, clustername + cluster FQDN.

    .PARAMETER SelfSigned
        Creates a self-signed certificate. All other parameters can still apply except CaServer and CaName because the command does not go and get the certificate signed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaComputerCertificate

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate

        Creates a computer certificate signed by the local domain CA for the local machine with the keylength of 1024.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName Server1

        Creates a computer certificate signed by the local domain CA _on the local machine_ for server1 with the keylength of 1024.

        The certificate is then copied to the new machine over WinRM and imported.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName sqla, sqlb -ClusterInstanceName sqlcluster -KeyLength 4096

        Creates a computer certificate for sqlcluster, signed by the local domain CA, with the keylength of 4096.

        The certificate is then copied to sqla _and_ sqlb over WinRM and imported.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName Server1 -WhatIf

        Shows what would happen if the command were run

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -SelfSigned

        Creates a self-signed certificate

    .EXAMPLE
        PS C:\> Add-DbaComputerCertificate -ComputerName sql01 -Path C:\temp\sql01.pfx -Confirm:$false -Flag NonExportable

        Adds the local C:\temp\sql01.pfx to sql01's LocalMachine\My (Personal) certificate store and marks the private key as non-exportable. Skips confirmation prompt.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$CaServer,
        [string]$CaName,
        [string]$ClusterInstanceName,
        [Alias("Password")]
        [securestring]$SecurePassword,
        [string]$FriendlyName = "SQL Server",
        [string]$CertificateTemplate = "WebServer",
        [int]$KeyLength = 1024,
        [string]$Store = "LocalMachine",
        [string]$Folder = "My",
        [ValidateSet("EphemeralKeySet", "Exportable", "PersistKeySet", "UserProtected", "NonExportable")]
        [string[]]$Flag = @("Exportable", "PersistKeySet"),
        [string[]]$Dns,
        [switch]$SelfSigned,
        [switch]$EnableException
    )
    begin {
        if ("NonExportable" -in $Flag) {
            $flags = ($Flag | Where-Object { $PSItem -ne "Exportable" -and $PSItem -ne "NonExportable" } ) -join ","

            # It needs at least one flag
            if (-not $flags) {
                if ($Store -eq "LocalMachine") {
                    $flags = "MachineKeySet"
                } else {
                    $flags = "UserKeySet"
                }
            }
        } else {
            $flags = $Flag -join ","
        }

        $englishCodes = 9, 1033, 2057, 3081, 4105, 5129, 6153, 7177, 8201, 9225
        if ($englishCodes -notcontains (Get-DbaCmObject -ClassName Win32_OperatingSystem).OSLanguage) {
            Stop-Function -Message "Currently, this command is only supported in English OS locales. OS Locale detected: $([System.Globalization.CultureInfo]::GetCultureInfo([int](Get-DbaCmObject Win32_OperatingSystem).OSLanguage).DisplayName)`nWe apologize for the inconvenience and look into providing universal language support in future releases."
            return
        }

        if (-not (Test-ElevationRequirement -ComputerName $env:COMPUTERNAME)) {
            return
        }

        function GetHexLength {
            [cmdletbinding()]
            param(
                [int]$strLen
            )
            $hex = [String]::Format("{0:X2}", $strLen)

            if (($hex.length % 2) -gt 0) { $hex = "0$hex" }

            if ($strLen -gt 127) { [String]::Format("{0:X2}", 128 + ($hex.Length / 2)) + $hex }
            else { $hex }
        }

        function Get-SanExt {
            [cmdletbinding()]
            param(
                [string[]]$hostName
            )
            # thanks to Lincoln of
            # https://social.technet.microsoft.com/Forums/windows/en-US/f568edfa-7f93-46a4-aab9-a06151592dd9/converting-ascii-to-asn1-der

            $temp = ''
            foreach ($fqdn in $hostName) {
                # convert each character of fqdn to hex
                $hexString = ($fqdn.ToCharArray() | ForEach-Object { [String]::Format("{0:X2}", [int]$_) }) -join ''

                # length of hex fqdn, in hex
                $hexLength = GetHexLength ($hexString.Length / 2)

                # concatenate special code 82, hex length, hex string
                $temp += "82${hexLength}${hexString}"
            }
            # calculate total length of concatenated string, in hex
            $totalHexLength = GetHexLength ($temp.Length / 2)
            # concatenate special code 30, hex length, hex string
            $temp = "30${totalHexLength}${temp}"
            # convert to binary
            $bytes = $(
                for ($i = 0; $i -lt $temp.Length; $i += 2) {
                    [byte]"0x$($temp.SubString($i, 2))"
                }
            )
            # convert to base 64
            $base64 = [Convert]::ToBase64String($bytes)
            # output in proper format
            for ($i = 0; $i -lt $base64.Length; $i += 64) {
                $line = $base64.SubString($i, [Math]::Min(64, $base64.Length - $i))
                if ($i -eq 0) { "2.5.29.17=$line" }
                else { "_continue_=$line" }
            }
        }

        if ((-not $CaServer -or !$CaName) -and !$SelfSigned) {
            try {
                Write-Message -Level Verbose -Message "No CaServer or CaName specified. Performing lookup."
                # hat tip Vadims Podans
                $domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
                $domain = "DC=" + $domain -replace '\.', ", DC="
                $pks = [ADSI]"LDAP://CN=Enrollment Services, CN=Public Key Services, CN=Services, CN=Configuration, $domain"
                $cas = $pks.psBase.Children

                $allCas = @()
                foreach ($ca in $cas) {
                    $allCas += [pscustomobject]@{
                        CA       = $ca | ForEach-Object { $_.Name }
                        Computer = $ca | ForEach-Object { $_.DNSHostName }
                    }
                }
            } catch {
                Stop-Function -Message "Cannot access Active Directory or find the Certificate Authority" -ErrorRecord $_
                return
            }

            if (-not $CaServer) {
                $CaServer = ($allCas | Select-Object -First 1).Computer
                Write-Message -Level Verbose -Message "Root Server: $CaServer"
            }

            if (-not $CaName) {
                $CaName = ($allCas | Select-Object -First 1).CA
                Write-Message -Level Verbose -Message "Root CA name: $CaName"
            }
        }

        $tempDir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $certTemplate = "CertificateTemplate:$CertificateTemplate"
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # uses dos command locally


        foreach ($computer in $ComputerName) {
            $stepCounter = 0

            if (-not $secondaryNode) {

                if ($ClusterInstanceName) {
                    if ($ClusterInstanceName -notmatch "\.") {
                        $fqdn = "$ClusterInstanceName.$env:USERDNSDOMAIN"
                    } else {
                        $fqdn = $ClusterInstanceName
                    }
                } else {
                    $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -WarningAction SilentlyContinue

                    if (-not $resolved) {
                        $fqdn = "$ComputerName.$env:USERDNSDOMAIN"
                        Write-Message -Level Warning -Message "Server name cannot be resolved. Guessing it's $fqdn"
                    } else {
                        $fqdn = $resolved.fqdn
                    }
                }

                $certDir = "$tempDir\$fqdn"
                $certCfg = "$certDir\request.inf"
                $certCsr = "$certDir\$fqdn.csr"
                $certCrt = "$certDir\$fqdn.crt"
                $certPfx = "$certDir\$fqdn.pfx"
                $tempPfx = "$certDir\temp-$fqdn.pfx"

                if (Test-Path($certDir)) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Deleting files from $certDir"
                    $null = Remove-Item "$certDir\*.*"
                } else {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating $certDir"
                    $null = New-Item -Path $certDir -ItemType Directory -Force
                }

                # Make sure output is compat with clusters
                $shortName = $fqdn.Split(".")[0]

                if (-not $dns) {
                    $dns = $shortName, $fqdn
                }

                $san = Get-SanExt $dns
                # Write config file
                Set-Content $certCfg "[Version]"
                Add-Content $certCfg 'Signature="$Windows NT$"'
                Add-Content $certCfg "[NewRequest]"
                Add-Content $certCfg "Subject = ""CN=$fqdn"""
                Add-Content $certCfg "KeySpec = 1"
                Add-Content $certCfg "KeyLength = $KeyLength"
                Add-Content $certCfg "Exportable = TRUE"
                Add-Content $certCfg "MachineKeySet = TRUE"
                Add-Content $certCfg "FriendlyName=""$FriendlyName"""
                Add-Content $certCfg "SMIME = False"
                Add-Content $certCfg "PrivateKeyArchive = FALSE"
                Add-Content $certCfg "UserProtected = FALSE"
                Add-Content $certCfg "UseExistingKeySet = FALSE"
                Add-Content $certCfg "ProviderName = ""Microsoft RSA SChannel Cryptographic Provider"""
                Add-Content $certCfg "ProviderType = 12"
                if ($SelfSigned) {
                    Add-Content $certCfg "RequestType = Cert"
                } else {
                    Add-Content $certCfg "RequestType = PKCS10"
                }
                Add-Content $certCfg "KeyUsage = 0xa0"
                Add-Content $certCfg "[EnhancedKeyUsageExtension]"
                Add-Content $certCfg "OID=1.3.6.1.5.5.7.3.1"
                Add-Content $certCfg "[Extensions]"
                Add-Content $certCfg $san
                Add-Content $certCfg "Critical=2.5.29.17"


                if ($PScmdlet.ShouldProcess("local", "Creating certificate for $computer")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Running: certreq -new $certCfg $certCsr"
                    $create = certreq -new $certCfg $certCsr
                }

                if ($SelfSigned) {
                    $serial = (($create -Split "Serial Number:" -Split "Subject")[2]).Trim() # D:
                    $storedCert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object SerialNumber -eq $serial

                    if ($computer.IsLocalHost) {
                        $storedCert | Select-Object * | Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
                    }
                } else {
                    if ($PScmdlet.ShouldProcess("local", "Submitting certificate request for $computer to $CaServer\$CaName")) {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "certreq -submit -config `"$CaServer\$CaName`" -attrib $certTemplate $certCsr $certCrt $certPfx"
                        $submit = certreq -submit -config ""$CaServer\$CaName"" -attrib $certTemplate $certCsr $certCrt $certPfx
                    }

                    if ($submit -match "ssued") {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "certreq -accept -machine $certCrt"
                        $null = certreq -accept -machine $certCrt
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                        $cert.Import($certCrt, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
                        $storedCert = Get-ChildItem "Cert:\$store\$folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                    } elseif ($submit) {
                        Write-Message -Level Warning -Message "Something went wrong"
                        Write-Message -Level Warning -Message "$create"
                        Write-Message -Level Warning -Message "$submit"
                        Stop-Function -Message "Failure when attempting to create the cert on $computer. Exception: $_" -ErrorRecord $_ -Target $computer -Continue
                    }

                    if ($Computer.IsLocalHost) {
                        $storedCert | Select-Object * | Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
                    }
                }
            }

            if (-not $Computer.IsLocalHost) {

                if (-not $secondaryNode) {
                    if ($PScmdlet.ShouldProcess("local", "Generating pfx and reading from disk")) {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting PFX with password to $tempPfx"
                        $certdata = $storedCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::PFX, $SecurePassword)
                    }

                    if ($PScmdlet.ShouldProcess("local", "Removing cert from disk but keeping it in memory")) {
                        $storedCert | Remove-Item
                    }

                    if ($ClusterInstanceName) { $secondaryNode = $true }
                }

                $scriptBlock = {
                    param (
                        $CertificateData,
                        [SecureString]$SecurePassword,
                        $Store,
                        $Folder,
                        $flags
                    )
                    Write-Verbose -Message "Importing cert to $Folder\$Store using flags: $flags"

                    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                    $cert.Import($CertificateData, $SecurePassword, $flags)
                    $certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
                    $certstore.Open('ReadWrite')
                    $certstore.Add($cert)
                    $certstore.Close()
                    Get-ChildItem "Cert:\$($Store)\$($Folder)" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                }

                if ($PScmdlet.ShouldProcess($computer, "Attempting to import new cert")) {
                    if ($flags -contains "UserProtected" -and -not $computer.IsLocalHost) {
                        Stop-Function -Message "UserProtected flag is only valid for localhost because it causes a prompt, skipping for $computer" -Continue
                    }
                    try {
                        $thumbprint = (Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $certdata, $SecurePassword, $Store, $Folder, $flags -ScriptBlock $scriptBlock -ErrorAction Stop -Verbose).Thumbprint
                        Get-DbaComputerCertificate -ComputerName $computer -Credential $Credential -Thumbprint $thumbprint
                    } catch {
                        Stop-Function -Message "Issue importing new cert on $computer" -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
            if ($PScmdlet.ShouldProcess("local", "Removing all files from $certDir")) {
                try {
                    Remove-Item -Force -Recurse $certDir -ErrorAction SilentlyContinue
                } catch {
                    Stop-Function "Isue removing files from $certDir" -Target $certDir -ErrorRecord $_
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUkPHLIhwVnew8bLPCCLFhbF7e
# GI6gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPVuWEYSktPN3tWOk/zUYMdPXM5CMA0G
# CSqGSIb3DQEBAQUABIIBADgA6IJkspS2OjBsQRMXCRdNphNvca7tcBAWEdfup21f
# CqJJSiOfrNAV9MDM5xwWIMm+b1OlGQrvOmnzhzoUvqeEzsXz10SHixjF8fJaPEzc
# qrBe/0jV8gkJD8r4P8fNxDgDDtdwmy22d0+u1lXdmwSosMk08RP1HoDr0NwAUQpq
# 0o4sHj224xDaK90JVFiZqTVprdeTpmGABs/xyC27TD8y3p0IjqEm+cn02OiVb+7e
# m508k6JX/Z4cz1ITnd9ApwOv918d4KWB2+BNH3Ri+UlLLWgZ2Ow3uv+Kdj73eHrW
# 2EBnTrUhsyTCq7i8RX73yiQ9NeWGaRAeOfJOiDRK33ahggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDAwWjAvBgkqhkiG9w0BCQQxIgQgZR+HwSP/V8IAyxLH/L9U
# P8oPlM7Avf0BYmOSOuLIOnEwDQYJKoZIhvcNAQEBBQAEggIAJzgWrnHYopBqWv54
# aA7Ne1ouRVL/jzh+PgOrDzpLFmXJIW857fyIqGEPcjCHWGYY5WaHhmeTHKsOXz58
# eDVP8vwq+7llVGk6V/2UN4bgC2zzHowe1Pp+0ANVl6CdBet0DRGRpMzU6BDonsnY
# u6ZUCS1kwJ3y6bgF0eae6a73msORGVghUgP2UFw3yrF6UO0wEh43Flz+y48YwM3r
# 6dZI0+1Q6dGWoxJR9OeS96l1WoQ4KPHGvJDwTupGAPLuFJWuXmNHAZ4xB/Vsxjum
# Vq8kQNOyJe7asbJVTDG8XsBVh9fnwchtWkY/SlLtVifPl9rln/0BiLATP7Uq9bqu
# nyceqWQ2fAZjHJ1xouypdWAe6HLs/cUcx/+941PsFUCSeJUgCTmdB23wKC3D8NG3
# mGnrHgxsOjIKF0RQyfv8rWuXAFdwGMyagpT80QuybakTTWPzqQUWN5gE+95//pd3
# KOKTY1TGb/T2NjnnaIcfGjr6PmYCtnsojvY8Hvajy4zapT0g0SRgTFLPNDmh2h51
# hIc1LRTnBOQxD7O9KTmn4H/n6NnCJplX+/PmVBX/ab5902zCYQh+W+aoCbcGLISd
# m2V4qBwAiv3CDueSa0WAOmGz8pcSVDYQKDxJlXURRdQHIguLXXfA4vSZZYJDmRX0
# RcACL5THKTgOGIVdpD33TVGSjuU=
# SIG # End signature block
