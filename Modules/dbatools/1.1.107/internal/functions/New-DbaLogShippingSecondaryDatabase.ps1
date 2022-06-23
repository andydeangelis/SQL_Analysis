function New-DbaLogShippingSecondaryDatabase {
    <#
        .SYNOPSIS
            New-DbaLogShippingSecondaryDatabase sets up a secondary databases for log shipping.

        .DESCRIPTION
            New-DbaLogShippingSecondaryDatabase sets up a secondary databases for log shipping.
            This is executed on the secondary server.

        .PARAMETER SqlInstance
            SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER BufferCount
            The total number of buffers used by the backup or restore operation.
            The default is -1.

        .PARAMETER BlockSize
            The size, in bytes, that is used as the block size for the backup device.
            The default is -1.

        .PARAMETER DisconnectUsers
            If set to 1, users are disconnected from the secondary database when a restore operation is performed.
            Te default is 0.

        .PARAMETER HistoryRetention
            Is the length of time in minutes in which the history is retained.
            The default is 14420.

        .PARAMETER MaxTransferSize
            The size, in bytes, of the maximum input or output request which is issued by SQL Server to the backup device.

        .PARAMETER PrimaryServer
            The name of the primary instance of the Microsoft SQL Server Database Engine in the log shipping configuration.

        .PARAMETER PrimaryDatabase
            Is the name of the database on the primary server.

        .PARAMETER RestoreAll
            If set to 1, the secondary server restores all available transaction log backups when the restore job runs.
            The default is 1.

        .PARAMETER RestoreDelay
            The amount of time, in minutes, that the secondary server waits before restoring a given backup file.
            The default is 0.

        .PARAMETER RestoreMode
            The restore mode for the secondary database. The default is 0.
            0 = Restore log with NORECOVERY.
            1 = Restore log with STANDBY.

        .PARAMETER RestoreThreshold
            The number of minutes allowed to elapse between restore operations before an alert is generated.

        .PARAMETER SecondaryDatabase
            Is the name of the secondary database.

        .PARAMETER ThresholdAlert
            Is the alert to be raised when the backup threshold is exceeded.
            The default is 14420.

        .PARAMETER ThresholdAlertEnabled
            Specifies whether an alert is raised when backup_threshold is exceeded.

        .PARAMETER MonitorServer
            Is the name of the monitor server.
            The default is the name of the primary server.

        .PARAMETER MonitorCredential
            Allows you to login to enter a secure credential.
            This is only needed in combination with MonitorServerSecurityMode having either a 0 or 'sqlserver' value.
            To use: $scred = Get-Credential, then pass $scred object to the -MonitorCredential parameter.

        .PARAMETER MonitorServerSecurityMode
            The security mode used to connect to the monitor server. Allowed values are 0, "sqlserver", 1, "windows"
            The default is 1 or Windows.

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER Force
            The force parameter will ignore some errors in the parameters and assume defaults.
            It will also remove the any present schedules with the same name for the specific job.

        .NOTES
            Author: Sander Stad (@sqlstad, sqlstad.nl)
            Website: https://dbatools.io
            Copyright: (c) 2018 by dbatools, licensed under MIT
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            New-DbaLogShippingSecondaryDatabase -SqlInstance sql2 -SecondaryDatabase DB1_DR -PrimaryServer sql1 -PrimaryDatabase DB1 -RestoreDelay 0 -RestoreMode standby -DisconnectUsers -RestoreThreshold 45 -ThresholdAlertEnabled -HistoryRetention 14420
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]

    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$BufferCount = -1,
        [int]$BlockSize = -1,
        [switch]$DisconnectUsers,
        [int]$HistoryRetention = 14420,
        [int]$MaxTransferSize,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$PrimaryServer,
        [PSCredential]$PrimarySqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$PrimaryDatabase,
        [int]$RestoreAll = 1,
        [int]$RestoreDelay = 0,
        [ValidateSet(0, 'NoRecovery', 1, 'Standby')]
        [object]$RestoreMode = 0,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [int]$RestoreThreshold,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SecondaryDatabase,
        [int]$ThresholdAlert = 14420,
        [switch]$ThresholdAlertEnabled,
        [string]$MonitorServer,
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$MonitorServerSecurityMode = 1,
        [System.Management.Automation.PSCredential]$MonitorCredential,
        [switch]$EnableException,
        [switch]$Force
    )

    # Try connecting to the instance
    try {
        $ServerSecondary = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
    }

    # Try connecting to the instance
    try {
        $ServerPrimary = Connect-DbaInstance -SqlInstance $PrimaryServer -SqlCredential $PrimarySqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $PrimaryServer
    }

    # Check if the database is present on the primary sql server
    if ($ServerPrimary.Databases.Name -notcontains $PrimaryDatabase) {
        Stop-Function -Message "Database $PrimaryDatabase is not available on instance $PrimaryServer" -Target $PrimaryServer -Continue
    }

    # Check if the database is present on the primary sql server
    if ($ServerSecondary.Databases.Name -notcontains $SecondaryDatabase) {
        Stop-Function -Message "Database $SecondaryDatabase is not available on instance $ServerSecondary" -Target $SqlInstance -Continue
    }

    # Check the restore mode
    if ($RestoreMode -notin 0, 1) {
        $RestoreMode = switch ($RestoreMode) { "NoRecovery" { 0 }  "Standby" { 1 } }
        Write-Message -Message "Setting restore mode to $RestoreMode." -Level Verbose
    }

    # Check the if Threshold alert needs to be enabled
    if ($ThresholdAlertEnabled) {
        [int]$ThresholdAlertEnabled = 1
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    } else {
        [int]$ThresholdAlertEnabled = 0
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    }

    # Checking the option to disconnect users
    if ($DisconnectUsers) {
        [int]$DisconnectUsers = 1
        Write-Message -Message "Setting disconnect users to $DisconnectUsers." -Level Verbose
    } else {
        [int]$DisconnectUsers = 0
        Write-Message -Message "Setting disconnect users to $DisconnectUsers." -Level Verbose
    }

    # Check hte combination of the restore mode with the option to disconnect users
    if ($RestoreMode -eq 0 -and $DisconnectUsers -ne 0) {
        if ($Force) {
            [int]$DisconnectUsers = 0
            Write-Message -Message "Illegal combination of database restore mode $RestoreMode and disconnect users $DisconnectUsers. Setting it to $DisconnectUsers." -Level Warning
        } else {
            Stop-Function -Message "Illegal combination of database restore mode $RestoreMode and disconnect users $DisconnectUsers." -Target $SqlInstance -Continue
        }
    }

    # Set up the query
    $Query = "EXEC master.sys.sp_add_log_shipping_secondary_database
        @secondary_database = '$SecondaryDatabase'
        ,@primary_server = '$PrimaryServer'
        ,@primary_database = '$PrimaryDatabase'
        ,@restore_delay = $RestoreDelay
        ,@restore_all = $RestoreAll
        ,@restore_mode = $RestoreMode
        ,@disconnect_users = $DisconnectUsers
        ,@restore_threshold = $RestoreThreshold
        ,@threshold_alert = $ThresholdAlert
        ,@threshold_alert_enabled = $ThresholdAlertEnabled
        ,@history_retention_period = $HistoryRetention "


    if ($ServerSecondary.Version.Major -le 12) {
        $Query += "
        ,@ignoreremotemonitor = 1"
    }

    # Add inf extra options to the query when needed
    if ($BlockSize -ne -1) {
        $Query += ",@block_size = $BlockSize"
    }

    if ($BufferCount -ne -1) {
        $Query += ",@buffer_count = $BufferCount"
    }

    if ($MaxTransferSize -ge 1) {
        $Query += ",@max_transfer_size = $MaxTransferSize"
    }

    if ($Force -and ($ServerSecondary.Version.Major -gt 9)) {
        $Query += ",@overwrite = 1;"
    } else {
        $Query += ";"
    }

    # Execute the query to add the log shipping primary
    if ($PSCmdlet.ShouldProcess($SqlServer, ("Configuring logshipping for secondary database $SecondaryDatabase on $SqlInstance"))) {
        try {
            Write-Message -Message "Configuring logshipping for secondary database $SecondaryDatabase on $SqlInstance." -Level Verbose
            Write-Message -Message "Executing query:`n$Query" -Level Verbose
            $ServerSecondary.Query($Query)

            # For versions prior to SQL Server 2014, adding a monitor works in a different way.
            # The next section makes sure the settings are being synchronized with earlier versions
            if ($MonitorServer -and ($ServerSecondary.Version.Major -lt 12)) {
                # Get the details of the primary database
                $query = "SELECT * FROM msdb.dbo.log_shipping_monitor_secondary WHERE primary_database = '$PrimaryDatabase' AND primary_server = '$PrimaryServer'"
                $lsDetails = $ServerSecondary.Query($query)

                # Setup the procedure script for adding the monitor for the primary
                $query = "EXEC msdb.dbo.sp_processlogshippingmonitorsecondary @mode = $MonitorServerSecurityMode
                    ,@secondary_server = '$SqlInstance'
                    ,@secondary_database = '$SecondaryDatabase'
                    ,@secondary_id = '$($lsDetails.secondary_id)'
                    ,@primary_server = '$($lsDetails.primary_server)'
                    ,@primary_database = '$($lsDetails.primary_database)'
                    ,@restore_threshold = $RestoreThreshold
                    ,@threshold_alert = $([int]$lsDetails.threshold_alert)
                    ,@threshold_alert_enabled = $([int]$lsDetails.threshold_alert_enabled)
                    ,@history_retention_period = $([int]$lsDetails.history_retention_period)
                    ,@monitor_server = '$MonitorServer'
                    ,@monitor_server_security_mode = $MonitorServerSecurityMode "

                # Check the MonitorServerSecurityMode if it's SQL Server authentication
                if ($MonitorServer -and $MonitorServerSecurityMode -eq 0 ) {
                    $query += ",@monitor_server_login = N'$MonitorLogin'
                        ,@monitor_server_password = N'$MonitorPassword' "
                }

                Write-Message -Message "Configuring monitor server for secondary database $SecondaryDatabase." -Level Verbose
                Write-Message -Message "Executing query:`n$query" -Level Verbose
                Invoke-DbaQuery -SqlInstance $MonitorServer -SqlCredential $MonitorCredential -Database msdb -Query $query

                $query = "
                UPDATE msdb.dbo.log_shipping_secondary
                SET monitor_server = '$MonitorServer', user_specified_monitor = 1
                WHERE secondary_id = '$($lsDetails.secondary_id)'
                "

                Write-Message -Message "Updating monitor information for the secondary database $Database." -Level Verbose
                Write-Message -Message "Executing query:`n$query" -Level Verbose
                $ServerSecondary.Query($query)

            }
        } catch {
            Write-Message -Message "$($_.Exception.InnerException.InnerException.InnerException.InnerException.Message)" -Level Warning
            Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$Query"  -ErrorRecord $_ -Target $SqlInstance -Continue
        }
    }

    Write-Message -Message "Finished adding the secondary database $SecondaryDatabase to log shipping." -Level Verbose

}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDq7+fSPvb7avX4
# XH8VokA0zs4agfz39puNhzind5pLkqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCiklri/dPkObGfHkCnAEnFR/uzKuCDeOGf
# ID1iB79ODDANBgkqhkiG9w0BAQEFAASCAQBkQFSBOeFrltQJ88aHrNF8dn5ewz5K
# S/LP1lTjY0yGRLvIZZ9ZgGl7Y3NBKAx5y8dScQFa8A2Axpn85njDKaK5pdXG7LrF
# 9IAkVkvSEZPZope7Efc7w46DIg/1ZErHFZTB/HbcHDSOlnZIMYg0M3LoTcQKTBRd
# 1HET2jSt8uUogqQX4u98JAnn8je0ICmBTl2IqsLFsTMHodPH+f7paEZB4xt2W2/W
# NP+DHO7xed5cGKZFv3o0c6l9wA/ZnBmeXq9dWldsvGHCG8MKppytuOIgC2aE4NJZ
# wIzhfBLe2BVD0AKP26cM6ALGPiZbxkzBrtpOTgbBCn1wRwRM4Cemjt0MoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQ0OFowLwYJKoZIhvcNAQkEMSIEIG5RAJFH
# 4MepoSdO8VuSu+rYJjWPE9g+/gKM0Z0z/OYFMA0GCSqGSIb3DQEBAQUABIICAJxP
# emEbefWvMSzVSUPsC8N1PtM7puChuMvmSvmOiqK15SoMUkWWhlyICce2TbKqPiiO
# XtIm8W9JyysC5UZSZyTpIPhKPGR2PK2koT6dJasA35tri2IRRrB6CVx5GNz3VTBg
# utn/9hPL3Sd3uu+WGwvMj6bQ1Ta7U1X30bYsq4msy2sIjA7pnQTiPSdX6G3g/zxv
# /+Yn0SOZBz33sLAEeQ7UESFVbGWu/mv2CxaeT4Pp0eOow7dzz/yTtgPzEgYulIN1
# NSxhErw/+QVM+cCMvMAardaDfO4vH/c6ed5nuLQMoIKu6FD7hY7ad3s9FS2wozxw
# AZ4GpwVGxjke3db7urZKTzB4HqGje3UbhNXTlmqDbUlLZjxGsHyKWsQVo0Z+QVrW
# B6yB7rCWpzRbejyswBWY+RmBBavonkLRKw+g6LRIBZgNtO1X6gEy+rX+3tVzo4OP
# WKl2v5N1ScpkT20/jM98YjbnPePGB4lm2GKhgZf1+8dU2LHFIe/LDJPN+WUzglQR
# HE6JkZdWDnCNmIvZLjgUoVy7xmlZgMPE51Wph/7NDfwJydhOdpAiNt7oOhgyXJ0J
# QkML6sUAHzHrw5nftRh+zaIBdMRXC5KxTLq4CmUK27Ima97ZKGc+O8wEEFqTlH23
# tXf2q35f63MFr0MAiCaAisFnGPR3fdxFsVkXNSJR
# SIG # End signature block
