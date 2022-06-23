function Test-DbaMigrationConstraint {
    <#
    .SYNOPSIS
        Show if you can migrate the database(s) between the servers.

    .DESCRIPTION
        When you want to migrate from a higher edition to a lower one there are some features that can't be used.
        This function will validate if you have any of this features in use and will report to you.
        The validation will be made ONLY on on SQL Server 2008 or higher using the 'sys.dm_db_persisted_sku_features' dmv.

        This function only validate SQL Server 2008 versions or higher.
        The editions supported by this function are:
        - Enterprise
        - Developer
        - Evaluation
        - Standard
        - Express

        Take into account the new features introduced on SQL Server 2016 SP1 for all versions. More information at https://blogs.msdn.microsoft.com/sqlreleaseservices/sql-server-2016-service-pack-1-sp1-released/

        The -Database parameter is auto-populated for command-line completion.

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
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaMigrationConstraint

    .EXAMPLE
        PS C:\> Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster

        All databases on sqlserver2014a will be verified for features in use that can't be supported on sqlcluster.

    .EXAMPLE
        PS C:\> Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        All databases will be verified for features in use that can't be supported on the destination server. SQL credentials are used to authenticate against sqlserver2014a and Windows Authentication is used for sqlcluster.

    .EXAMPLE
        PS C:\> Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster -Database db1

        Only db1 database will be verified for features in use that can't be supported on the destination server.

    #>
    [CmdletBinding(DefaultParameterSetName = "DbMigration")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstance]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    begin {
        <#
            1804890536 = Enterprise
            1872460670 = Enterprise Edition: Core-based Licensing
            610778273 = Enterprise Evaluation
            284895786 = Business Intelligence
            -2117995310 = Developer
            -1592396055 = Express
            -133711905= Express with Advanced Services
            -1534726760 = Standard
            1293598313 = Web
            1674378470 = SQL Database
        #>

        $editions = @{
            "Enterprise" = 10;
            "Developer"  = 10;
            "Evaluation" = 10;
            "Standard"   = 5;
            "Express"    = 1
        }
        $notesCanMigrate = "Database can be migrated."
        $notesCannotMigrate = "Database cannot be migrated."
    }
    process {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
        }

        try {
            $destServer = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination
        }

        if (-Not $Database) {
            $Database = $sourceServer.Databases | Where-Object IsSystemObject -eq 0 | Select-Object Name, Status
        }

        if ($ExcludeDatabase) {
            $Database = $sourceServer.Databases | Where-Object Name -NotIn $ExcludeDatabase
        }

        if ($Database.Count -gt 0) {
            if ($Database -in @("master", "msdb", "tempdb")) {
                Stop-Function -Message "Migrating system databases is not currently supported."
                return
            }

            if ($sourceServer.VersionMajor -lt 9 -and $destServer.VersionMajor -gt 10) {
                Stop-Function -Message "Sql Server 2000 databases cannot be migrated to SQL Server version 2012 and above. Quitting."
                return
            }

            if ($sourceServer.Collation -ne $destServer.Collation) {
                Write-Message -Level Warning -Message "Collation on $Source, $($sourceServer.collation) differs from the $Destination, $($destServer.collation)."
            }

            if ($sourceServer.VersionMajor -gt $destServer.VersionMajor) {
                #indicate they must use 'Generate Scripts' and 'Export Data' options?
                Stop-Function -Message "You can't migrate databases from a higher version to a lower one. Quitting."
                return
            }

            if ($sourceServer.VersionMajor -lt 10) {
                Stop-Function -Message "This function does not support versions lower than SQL Server 2008 (v10)"
                return
            }

            #if editions differs, from higher to lower one, verify the sys.dm_db_persisted_sku_features - only available from SQL 2008 +
            if (($sourceServer.VersionMajor -ge 10 -and $destServer.VersionMajor -ge 10)) {
                foreach ($db in $Database) {
                    if ([string]::IsNullOrEmpty($db.Status)) {
                        $dbstatus = ($sourceServer.Databases | Where-Object Name -eq $db).Status.ToString()
                        $dbName = $db
                    } else {
                        $dbstatus = $db.Status.ToString()
                        $dbName = $db.Name
                    }

                    Write-Message -Level Verbose -Message "Checking database '$dbName'."

                    if ($dbstatus.Contains("Offline") -eq $false -or $db.IsAccessible -eq $true) {

                        [long]$destVersionNumber = $($destServer.VersionString).Replace(".", "")
                        [string]$sourceVersion = "$($sourceServer.Edition) $($sourceServer.ProductLevel) ($($sourceServer.Version))"
                        [string]$destVersion = "$($destServer.Edition) $($destServer.ProductLevel) ($($destServer.Version))"
                        [string]$dbFeatures = ""

                        #Check if database has any FILESTREAM filegroup
                        Write-Message -Level Verbose -Message "Checking if FileStream is in use for database '$dbName'."
                        if ($sourceServer.Databases[$dbName].FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup') {
                            Write-Message -Level Verbose -Message "Found FileStream filegroup and files."
                            $fileStreamSource = Get-DbaSpConfigure -SqlInstance $sourceServer -ConfigName FilestreamAccessLevel
                            $fileStreamDestination = Get-DbaSpConfigure -SqlInstance $destServer -ConfigName FilestreamAccessLevel

                            if ($fileStreamSource.RunningValue -ne $fileStreamDestination.RunningValue) {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate. Destination server dones not have the 'FilestreamAccessLevel' configuration (RunningValue: $($fileStreamDestination.RunningValue)) equal to source server (RunningValue: $($fileStreamSource.RunningValue))."
                                }
                                Continue
                            }
                        }

                        try {
                            $sql = "SELECT feature_name FROM sys.dm_db_persisted_sku_features"

                            $skuFeatures = $sourceServer.Query($sql, $dbName)

                            Write-Message -Level Verbose -Message "Checking features in use..."

                            if (@($skuFeatures).Count -gt 0) {
                                foreach ($row in $skuFeatures) {
                                    $dbFeatures += ",$($row["feature_name"])"
                                }

                                $dbFeatures = $dbFeatures.TrimStart(",")
                            }
                        } catch {
                            Stop-Function -Message "Issue collecting sku features." -ErrorRecord $_ -Target $sourceServer -Continue
                        }

                        #If SQL Server 2016 SP1 (13.0.4001.0) or higher
                        if ($destVersionNumber -ge 13040010) {
                            <#
                                Need to verify if Edition = EXPRESS and database uses 'Change Data Capture' (CDC)
                                This means that database cannot be migrated because Express edition doesn't have SQL Server Agent
                            #>
                            if ($editions.Item($destServer.Edition.ToString().Split(" ")[0]) -eq 1 -and $dbFeatures.Contains("ChangeCapture")) {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate. Destination server edition is EXPRESS which does not support 'ChangeCapture' feature that is in use."
                                }
                            } else {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $true
                                    Notes               = $notesCanMigrate
                                }
                            }
                        }
                        #Version is lower than SQL Server 2016 SP1
                        else {
                            Write-Message -Level Verbose -Message "Source Server Edition: $($sourceServer.Edition) (Weight: $($editions.Item($sourceServer.Edition.ToString().Split(" ")[0])))"
                            Write-Message -Level Verbose -Message "Destination Server Edition: $($destServer.Edition) (Weight: $($editions.Item($destServer.Edition.ToString().Split(" ")[0])))"

                            #Check for editions. If destination edition is lower than source edition and exists features in use
                            if (($editions.Item($destServer.Edition.ToString().Split(" ")[0]) -lt $editions.Item($sourceServer.Edition.ToString().Split(" ")[0])) -and (!([string]::IsNullOrEmpty($dbFeatures)))) {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate There are features in use not available on destination instance."
                                }
                            }
                            #
                            else {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $true
                                    Notes               = $notesCanMigrate
                                }
                            }
                        }
                    } else {
                        Write-Message -Level Warning -Message "Database '$dbName' is offline or not accessible. Bring database online and re-run the command."
                    }
                }
            } else {
                #SQL Server 2005 or under
                Write-Message -Level Warning -Message "This validation will not be made on versions lower than SQL Server 2008 (v10)."
                Write-Message -Level Verbose -Message "Source server version: $($sourceServer.VersionMajor)."
                Write-Message -Level Verbose -Message "Destination server version: $($destServer.VersionMajor)."
            }
        } else {
            Write-Message -Level Output -Message "There are no databases to validate."
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUxCivOhZi9b3tV17EoogwMoGe
# N9GgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFJqrj7VruDshbtrbUgcAABemYs/MMA0G
# CSqGSIb3DQEBAQUABIIBAB/sAQeYf5Gp1QXOho6n3fBs3tp7YAMGNiuI5mmw99kV
# n90xtXhXgd9rCqFKMb3NbL7A6nfjuhzcakw2cGha0RkS07Sg614zT/KlHyO0nckG
# rMZdmdxAiX+R6sh4+/Cnw/EZ1rV/zDDDGzqWQUoC2H+3hwPjOglfdi6jIkdur7Wb
# FdOqnTniSwI4IEz7SBev2aJpgiwrUuBvV/7D8SJCRfb61S0Y7L2MWoyuQlZF6MlV
# 0mRJrR1DnIUB6hMmWzJB8XyyOjj3tYXvOBHD+WnYMsJM6R/65eJBoAlGiSO0owup
# UYQO01M7JrbChGgAQXhBreVAk3WF48ZYc8pTuczM156hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDMwWjAvBgkqhkiG9w0BCQQxIgQgjEXxY4Ss1XVMwxYa5QG2
# SSqMXF1+srsaMe+WXMEtOvMwDQYJKoZIhvcNAQEBBQAEggIAl1VRtLOaNVuZe9Oc
# roZkFx61qH0N1AGO1g7qEAJ2qc0ru4yqb5Sch0KeuNLFKFGBfNTpdbRcBGZ22SEt
# Howbpxr8+/I1BBtPgrnq7zKlUi+jeCYLFjJMB5HFITuBHoHo7k8L1bDDsIrcxG6p
# /DS9qc3iysS8zsGkYbn+f6aO86WOJIQjxDeSJxxop/R2s9JZ/CfgEOb2/msRNRK+
# mfwyg9H2DyfQb+ZTbiz0lRFra62YMOh6MTZNzMsC67WHJN7MRzccoRHydE1+f8bv
# cpDcUWSlK09wk7CUzHIK6xDhxG0pYsK9bWxMl1jEBuav8R86IMWMZ3LUaXEt2s4t
# JkXJBVQQ5UV+FOqHeBLMTD12/fIGI6755dQ0zOXjOi4F5sFYLQYjax5LhMyExyOF
# b67kuX45Mxi1gA2cDdGm+RYq9QAdRvoIJlOjRVfthCR0zI47uttEVZs2zJw9enx8
# 2MnNrgqKoqluYaUH1Xp8amDuyxOYyq7pn/rg8msezpolkfA06QW+gchRKSulu+Fc
# cOoNIMkPHnOKY50F3GXJSOwRlBYw0nqHMf1da/iyFEUJF+1EtGZocwSG2gEgilmh
# A8cYAPxSUjSe48WARvFfVCd4yVolh+joVaecloIMp4VdX8WNiqiL72gL7b7xvis4
# 2uxYgQ2wX6aBa/1xrl8xZdR7Gqc=
# SIG # End signature block
