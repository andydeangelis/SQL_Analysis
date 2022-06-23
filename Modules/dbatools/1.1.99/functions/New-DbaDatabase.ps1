function New-DbaDatabase {
    <#
    .SYNOPSIS
        Creates a new database

    .DESCRIPTION
        This command creates a new database.

        It allows creation with multiple files, and sets all growth settings to be fixed size rather than percentage growth. The autogrowth settings are obtained from the modeldev file in the model database when not supplied as command line arguments.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the new database or databases to be created.

    .PARAMETER DataFilePath
        The location that data files will be placed, otherwise the default SQL Server data path will be used.

    .PARAMETER LogFilePath
        The location the log file will be placed, otherwise the default SQL Server log path will be used.

    .PARAMETER Collation
        The database collation, if not supplied the default server collation will be used.

    .PARAMETER RecoveryModel
        The recovery model for the database, if not supplied the recovery model from the model database will be used.
        Valid options are: Simple, Full, BulkLogged.

    .PARAMETER Owner
        The login that will be used as the database owner.

    .PARAMETER PrimaryFilesize
        The size in MB for the Primary file. If this is less than the primary file size for the model database, then the model size will be used instead.

    .PARAMETER PrimaryFileGrowth
        The size in MB that the Primary file will autogrow by.

    .PARAMETER PrimaryFileMaxSize
        The maximum permitted size in MB for the Primary File. If this is less than the primary file size for the model database, then the model size will be used instead.

    .PARAMETER LogSize
        The size in MB that the Transaction log will be created.

    .PARAMETER LogGrowth
        The amount in MB that the log file will be set to autogrow by.

    .PARAMETER LogMaxSize
        The maximum permitted size in MB. If this is less than the log file size for the model database, then the model log size will be used instead.

    .PARAMETER SecondaryFileCount
        The number of files to create in the Secondary filegroup for the database.

    .PARAMETER SecondaryFilesize
        The size in MB of the files to be added to the Secondary filegroup. Each file added will be created with this size setting.

    .PARAMETER SecondaryFileMaxSize
        The maximum permitted size in MB for the Secondary data files to grow to. Each file added will be created with this max size setting.

    .PARAMETER SecondaryFileGrowth
        The amount in MB that the Secondary files will be set to autogrow by. Use 0 for no growth allowed. Each file added will be created with this growth setting.

    .PARAMETER DefaultFileGroup
        Sets the default file group. Either primary or secondary.

    .PARAMETER DataFileSuffix
        The data file suffix.

    .PARAMETER LogFileSuffix
        The log file suffix. Defaults to "_log"

    .PARAMETER SecondaryDataFileSuffix
        The secondary data file suffix.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
        Author: Matthew Darwin (@evoDBA, naturalselectiondba.wordpress.com)  | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDatabase

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1

        Creates a randomly named database (random-N) on instance sql1

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1 -Name dbatools, dbachecks

        Creates a database named dbatools and a database named dbachecks on sql1

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1, sql2, sql3 -Name multidb, multidb2 -SecondaryFilesize 20 -SecondaryFileGrowth 20 -LogSize 20 -LogGrowth 20

        Creates two databases, multidb and multidb2, on 3 instances (sql1, sql2 and sql3) and sets the secondary data file size to 20MB, the file growth to 20MB and the log growth to 20MB for each

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1 -Name nondefault -DataFilePath M:\Data -LogFilePath 'L:\Logs with spaces' -SecondaryFileCount 2

        Creates a database named nondefault and places data files in in the M:\data directory and log files in "L:\Logs with spaces".

        Creates a secondary group with 2 files in the Secondary filegroup.

    .EXAMPLE
        PS C:\> $databaseParams = @{
        >> SqlInstance             = "sql1"
        >> Name                    = "newDb"
        >> LogSize                 = 32
        >> LogMaxSize              = 512
        >> PrimaryFilesize         = 64
        >> PrimaryFileMaxSize      = 512
        >> SecondaryFilesize       = 64
        >> SecondaryFileMaxSize    = 512
        >> LogGrowth               = 32
        >> PrimaryFileGrowth       = 64
        >> SecondaryFileGrowth     = 64
        >> DataFileSuffix          = "_PRIMARY"
        >> LogFileSuffix           = "_Log"
        >> SecondaryDataFileSuffix = "_MainData"
        >> }
        >> New-DbaDatabase @databaseParams

        Creates a new database named newDb on the sql1 instance and sets the file sizes, max sizes, and growth as specified. The resulting filenames will take the form:

        newDb_PRIMARY
        newDb_Log
        newDb_MainData_1  (Secondary filegroup files)

    #>
    [Cmdletbinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param
    (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Database')]
        [string[]]$Name,
        [string]$Collation,
        [ValidateSet('Simple', 'Full', 'BulkLogged')]
        [string]$RecoveryModel,
        [string]$Owner,
        [string]$DataFilePath,
        [string]$LogFilePath,
        [int32]$PrimaryFilesize,
        [int32]$PrimaryFileGrowth,
        [int32]$PrimaryFileMaxSize,
        [int32]$LogSize,
        [int32]$LogGrowth,
        [int32]$LogMaxSize,
        [int32]$SecondaryFilesize,
        [int32]$SecondaryFileGrowth,
        [int32]$SecondaryFileMaxSize,
        [int32]$SecondaryFileCount,
        [ValidateSet('Primary', 'Secondary')]
        [string]$DefaultFileGroup,
        [string]$DataFileSuffix,
        [string]$LogFileSuffix = '_log',
        [string]$SecondaryDataFileSuffix,
        [switch]$EnableException
    )

    begin {
        # do some checks to see if the advanced config settings will be invoked
        if (Test-Bound -ParameterName DataFilePath, DefaultFileGroup, LogFilePath, LogGrowth, LogMaxSize, LogSize, PrimaryFileGrowth, PrimaryFileMaxSize, PrimaryFilesize, SecondaryFileCount, SecondaryFileGrowth, SecondaryFileMaxSize, SecondaryFilesize, DataFileSuffix, LogFileSuffix, SecondaryDataFileSuffix) {
            $advancedconfig = $true
            Write-Message -Message "Advanced data file configuration will be invoked" -Level Verbose
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($advancedconfig -and $server.VersionMajor -eq 8) {
                Stop-Function -Message "Advanced configuration options are not available to SQL Server 2000. Aborting creation of database on $instance" -Target $instance -Continue
            }

            # validate the collation
            if ($Collation) {
                $collations = Get-DbaAvailableCollation -SqlInstance $server

                if ($collations.Name -notcontains $Collation) {
                    Stop-Function -Message "$Collation is not a valid collation on $instance" -Target $instance -Continue
                }
            }

            if (-not (Test-Bound -ParameterName Name)) {
                $Name = "random-$(Get-Random)"
            }

            if (-not (Test-Bound -ParameterName DataFilePath)) {
                $DataFilePath = (Get-DbaDefaultPath -SqlInstance $server).Data
            }

            if (-not (Test-Bound -ParameterName LogFilePath)) {
                $LogFilePath = (Get-DbaDefaultPath -SqlInstance $server).Log
            }

            if (-not (Test-DbaPath -SqlInstance $server -Path $LogFilePath)) {
                try {
                    Write-Message -Message "Creating directory $LogFilePath" -Level Verbose
                    $null = New-DbaDirectory -SqlInstance $server -Path $LogFilePath -EnableException
                } catch {
                    Stop-Function -Message "Error creating log file directory $LogFilePath" -Target $instance -Continue
                }
            }

            if (-not (Test-DbaPath -SqlInstance $server -Path $DataFilePath)) {
                try {
                    Write-Message -Message "Creating directory $DataFilePath" -Level Verbose
                    $null = New-DbaDirectory -SqlInstance $server -Path $DataFilePath -EnableException
                } catch {
                    Stop-Function -Message "Error creating secondary file directory $DataFilePath on $instance" -Target $instance -Continue
                }
            }

            Write-Message -Message "Set local data path to $DataFilePath and local log path to $LogFilePath" -Level Verbose

            foreach ($dbName in $Name) {
                if ($server.Databases[$dbName].Name) {
                    Stop-Function -Message "Database $dbName already exists on $instance" -Target $instance -Continue
                }

                try {
                    Write-Message -Message "Creating smo object for new database $dbName" -Level Verbose
                    $newdb = New-Object Microsoft.SqlServer.Management.Smo.Database($server, $dbName)
                } catch {
                    Stop-Function -Message "Error creating database object for $dbName on server $server" -ErrorRecord $_ -Target $instance -Continue
                }

                if ($Collation) {
                    Write-Message -Message "Setting collation to $Collation" -Level Verbose
                    $newdb.Collation = $Collation
                }

                if ($RecoveryModel) {
                    Write-Message -Message "Setting recovery model to $RecoveryModel" -Level Verbose
                    $newdb.RecoveryModel = $RecoveryModel
                }

                if ($advancedconfig) {
                    try {
                        Write-Message -Message "Creating PRIMARY filegroup" -Level Verbose
                        $primaryfg = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($newdb, "PRIMARY")
                        $newdb.Filegroups.Add($primaryfg)
                    } catch {
                        Stop-Function -Message "Error creating Primary filegroup object" -ErrorRecord $_ -Target $instance -Continue
                    }

                    #add the primary file
                    try {
                        $primaryfilename = $dbName + $DataFileSuffix
                        Write-Message -Message "Creating file name $primaryfilename in filegroup PRIMARY" -Level Verbose

                        # if PrimaryFilesize and PrimaryFileMaxSize were passed in then check the size of the modeldev file; if larger than our $PrimaryFilesize setting use that instead
                        if ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size -gt ($PrimaryFilesize * 1024)) {
                            Write-Message -Message "model database modeldev larger than our the PrimaryFilesize so using modeldev size for Primary file" -Level Verbose
                            $PrimaryFilesize = ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size / 1024)
                            if ($PrimaryFilesize -gt $PrimaryFileMaxSize) {
                                Write-Message -Message "Resetting Primary File Max size to be the new Primary File Size setting" -Level Verbose
                                $PrimaryFileMaxSize = $PrimaryFilesize
                            }
                        }

                        #create the primary file
                        $primaryfile = New-Object Microsoft.SqlServer.Management.Smo.DataFile($primaryfg, $primaryfilename)
                        $primaryfile.FileName = $DataFilePath + "\" + $primaryfilename + ".mdf"
                        $primaryfile.IsPrimaryFile = $true

                        if (Test-Bound -ParameterName PrimaryFilesize) {
                            $primaryfile.Size = ($PrimaryFilesize * 1024)
                        } else {
                            $primaryfile.Size = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size
                        }
                        if (Test-Bound -ParameterName PrimaryFileGrowth) {
                            $primaryfile.Growth = ($PrimaryFileGrowth * 1024)
                            $primaryfile.GrowthType = "KB"
                        } else {
                            $primaryfile.Growth = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
                            $primaryfile.GrowthType = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType
                        }
                        if (Test-Bound -ParameterName PrimaryFileMaxSize) {
                            $primaryfile.MaxSize = ($PrimaryFileMaxSize * 1024)
                        } else {
                            $primaryfile.MaxSize = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].MaxSize
                        }

                        #add the file to the filegroup
                        $primaryfg.Files.Add($primaryfile)
                    } catch {
                        Stop-Function -Message "Error adding file to Primary filegroup" -ErrorRecord $_ -Target $instance -Continue
                    }

                    try {
                        $logname = $dbName + $LogFileSuffix
                        Write-Message -Message "Creating log $logname" -Level Verbose

                        # if LogSize and LogMaxSize were passed in then check the size of the modellog file; if larger than our $LogSize setting use that instead
                        if ($server.Databases["model"].LogFiles["modellog"].Size -gt ($LogSize * 1024)) {
                            Write-Message -Message "model database modellog larger than our the LogSize so using modellog size for Log file size" -Level Verbose
                            $LogSize = ($server.Databases["model"].LogFiles["modellog"].Size / 1024)
                            if ($LogSize -gt $LogMaxSize) {
                                Write-Message -Message "Resetting Log File Max size to be the new Log File Size setting" -Level Verbose
                                $LogMaxSize = $LogSize
                            }
                        }

                        $tlog = New-Object Microsoft.SqlServer.Management.Smo.LogFile($newdb, $logname)
                        $tlog.FileName = $LogFilePath + "\" + $logname + ".ldf"

                        if (Test-Bound -ParameterName LogSize) {
                            $tlog.Size = ($LogSize * 1024)
                        } else {
                            $tlog.Size = $server.Databases["model"].LogFiles["modellog"].Size
                        }
                        if (Test-Bound -ParameterName LogGrowth) {
                            $tlog.Growth = ($LogGrowth * 1024)
                            $tlog.GrowthType = "KB"
                        } else {
                            $tlog.Growth = $server.Databases["model"].LogFiles["modellog"].Growth
                            $tlog.GrowthType = $server.Databases["model"].LogFiles["modellog"].GrowthType
                        }
                        if (Test-Bound -ParameterName LogMaxSize) {
                            $tlog.MaxSize = ($LogMaxSize * 1024)
                        } else {
                            $tlog.MaxSize = $server.Databases["model"].LogFiles["modellog"].MaxSize
                        }

                        #add the log to the db
                        $newdb.LogFiles.Add($tlog)
                    } catch {
                        Stop-Function -Message "Error adding log file to database." -ErrorRecord $_ -Target $instance -Continue
                    }

                    if ($DefaultFileGroup -eq "Secondary" -or (Test-Bound -ParameterName SecondaryFileMaxSize, SecondaryFileGrowth, SecondaryFilesize, SecondaryFileCount)) {
                        #add the Secondary data file group
                        try {
                            $secondaryfilegroupname = $dbName + $SecondaryDataFileSuffix
                            Write-Message -Message "Creating Secondary filegroup $secondaryfilegroupname" -Level Verbose

                            $secondaryfg = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($newdb, $secondaryfilegroupname)
                            $newdb.Filegroups.Add($secondaryfg)
                        } catch {
                            Stop-Function -Message "Error creating Secondary filegroup" -ErrorRecord $_ -Target $instance -Continue
                        }

                        # if SecondaryFilesize and SecondaryFileMaxSize were passed in then check the size of the modeldev file; if larger than our $SecondaryFilesize setting use that instead
                        if ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size -gt ($SecondaryFilesize * 1024)) {
                            Write-Message -Message "model database modeldev larger than our the SecondaryFilesize so using modeldev size for the Secondary file" -Level Verbose
                            $SecondaryFilesize = ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size / 1024)
                            if ($SecondaryFilesize -gt $SecondaryFileMaxSize) {
                                Write-Message -Message "Resetting Secondary File Max size to be the new Secondary File Size setting" -Level Verbose
                                $SecondaryFileMaxSize = $SecondaryFilesize
                            }
                        }

                        # add the required number of files to the filegroup in a loop
                        $secondaryfgcount = $bail = 0

                        # open a loop while the filecounter is less than the required number of files
                        do {
                            $secondaryfgcount++
                            try {
                                $secondaryfilename = "$($secondaryfilegroupname)_$($secondaryfgcount)"
                                Write-Message -Message "Creating file name $secondaryfilename in filegroup $secondaryfilegroupname" -Level Verbose
                                $secondaryfile = New-Object Microsoft.SQLServer.Management.Smo.Datafile($secondaryfg, $secondaryfilename)
                                $secondaryfile.FileName = $DataFilePath + "\" + $secondaryfilename + ".ndf"

                                if (Test-Bound -ParameterName SecondaryFilesize) {
                                    $secondaryfile.Size = ($SecondaryFilesize * 1024)
                                } else {
                                    $secondaryfile.Size = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size
                                }
                                if (Test-Bound -ParameterName SecondaryFileGrowth) {
                                    $secondaryfile.Growth = ($SecondaryFileGrowth * 1024)
                                    $secondaryfile.GrowthType = "KB"
                                } else {
                                    $secondaryfile.Growth = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
                                    $secondaryfile.GrowthType = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType
                                }
                                if (Test-Bound -ParameterName SecondaryFileMaxSize) {
                                    $secondaryfile.MaxSize = ($SecondaryFileMaxSize * 1024)
                                } else {
                                    $secondaryfile.MaxSize = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].MaxSize
                                }

                                $secondaryfg.Files.Add($secondaryfile)
                            } catch {
                                $bail = $true
                                Stop-Function -Message "Error adding file $secondaryfg to $secondaryfilegroupname" -ErrorRecord $_ -Target $instance
                                return
                            }
                        } while ($secondaryfgcount -lt $SecondaryFileCount -or $bail)
                    }
                }

                Write-Message -Message "Creating Database $dbName" -Level Verbose
                if ($PSCmdlet.ShouldProcess($instance, "Creating the database $dbName on instance $instance")) {
                    try {
                        $newdb.Create()
                    } catch {
                        Stop-Function -Message "Error creating Database $dbName on server $instance" -ErrorRecord $_ -Target $instance -Continue
                    }

                    if ($Owner) {
                        Write-Message -Message "Setting database owner to $Owner" -Level Verbose
                        try {
                            $newdb.SetOwner($Owner)
                            $newdb.Refresh()
                        } catch {
                            Stop-Function -Message "Error setting Database Owner to $Owner" -ErrorRecord $_ -Target $instance -Continue
                        }
                    }

                    if ($DefaultFileGroup -eq "Secondary") {
                        Write-Message -Message "Setting default filegroup to $secondaryfilegroupname" -Level Verbose
                        try {
                            $newdb.SetDefaultFileGroup($secondaryfilegroupname)
                        } catch {
                            Stop-Function -Message "Error setting default filegroup to $secondaryfilegroupname" -ErrorRecord $_ -Target $instance -Continue
                        }
                    }

                    Add-TeppCacheItem -SqlInstance $server -Type database -Name $dbName
                    Get-DbaDatabase -SqlInstance $server -Database $dbName
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUM+VQ63ZOMN0ajcv0Odxoip4S
# ZbugghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFHL4Mlw71dcmarfCvc1PXS8iGv6EMA0G
# CSqGSIb3DQEBAQUABIIBABWJWUWghItOYhUzHBMVvr7fHIfmWcdRGi+RNyYJeEKO
# Hx5VoHuqIkWp4Ww+NaBi2TfTQN9TQ38pNcOJt18csQmvZO+b0V2b3mmwi6cvh23B
# IA6ef8PNUkPb9+3pRgrGPZb2R+pMR5UwtSldFguOTkDejpmxF98ZL+tGa8YH7dtr
# ibj3850Zut67Z3IfES2Mizz0P+pIf0FSuXdxPdeQ6KfvcTqIUaM4+HFB3NvrAvt4
# gwpiu1V7sm1aRuugklYl/Nm1RvXcAtUJDKhJBcPMlseudOK2FPf3sBPRyXVxcoab
# T12Y9AR3NpmB20TPgx9KOw47wPuhig23UukhblRBOdihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDAxWjAvBgkqhkiG9w0BCQQxIgQgtZrmuadXaggMqsgjg19P
# 1cQr+A3vo7E+9Xxh9MPKFr4wDQYJKoZIhvcNAQEBBQAEggIAas64/Yh5WtEBgo4c
# D8t0SWk1nLEL8F0Qu0ZL4lSJAeyeuy3NS9RizTi8fiAmnWXEkGcHlDFTVtSgSOvx
# 47vhwhYbeX6ZiOH/W/aajH+eaxV7OmByKPyyn4XGThvqfmm0CEUjzurHxHvmqyO8
# JeELQW2dUi5q2EwUyWmT543709zwNDGSkUOqAO7oARZBs6/yxoHJOkS0Bf8k3xaT
# t/E3w84sLpGMdhn8d8vlO69PZ9GHxaJDcqeRHi3yYAXFI0XNTWmeKHcyaAfvQnUq
# gp+nd8ODn6bZHT08MHumBw9meNX2OclNDzMH2mJPu9sQPBftByTKUna0nKRvSAYR
# xFQjjX5VwOVXyaRzRvU5UpxfO5f8I8AyLZIrR12ELMqaIlkEsA66j+WE1BAfS0bw
# LXTTcEDEMdYGY4vzzq6hPReqrltyk+jd07s/bkgggcUZwkxmLdbYskyuuxXjk8Tk
# Mq0oLYRp222urL7Grrq4sMDO4N898COlCNgKMpSJFrs9oKiV39mJa6Qp/W1UuIYY
# g41kG69eIDe42pOhu7moHcozxFfRGBOm3iDSwwvEASmN5l0QO4DPXinoGpibobWr
# me0L8pvF/vEseooioawCKhS4FUzOlWkaimK5OFWm68nm9Gdiiq9zO7sNR3YnIyJr
# XNqOe3tiCcO9FdGd5fiFTLjnW9Y=
# SIG # End signature block
