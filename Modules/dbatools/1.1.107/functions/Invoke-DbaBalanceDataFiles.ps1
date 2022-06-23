function Invoke-DbaBalanceDataFiles {
    <#
    .SYNOPSIS
        Re-balance data between data files

    .DESCRIPTION
        When you have a large database with a single data file and add another file, SQL Server will only use the new file until it's about the same size.
        You may want to balance the data between all the data files.

        The function will check the server version and edition to see if the it allows for online index rebuilds.
        If the server does support it, it will try to rebuild the index online.
        If the server doesn't support it, it will rebuild the index offline. Be carefull though, this can cause downtime

        The tables must have a clustered index to be able to balance out the data.
        The function does NOT yet support heaps.

        The function will also check if the file groups are subject to balance out.
        A file group would have at least have 2 data files and should be writable.
        If a table is within such a file group it will be subject for processing. If not the table will be skipped.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process.

    .PARAMETER Table
        The tables(s) of the database to process. If unspecified, all tables will be processed.

    .PARAMETER RebuildOffline
        Will set all the indexes to rebuild offline.
        This option is also needed when the server version is below 2005.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        This will disable the check for enough disk space for the action to be successful.
        Use this with caution!!

    .NOTES
        Tags: Database, FileManagement, File, Utility
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaBalanceDataFiles

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1

        This command will distribute the data in database db1 on instance sql1

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 | Select-Object -ExpandProperty DataFilesEnd

        This command will distribute the data in database db1 on instance sql1

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 -Table table1,table2,table5

        This command will distribute the data for only the tables table1,table2 and table5

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 -RebuildOffline

        This command will consider the fact that there might be a SQL Server edition that does not support online rebuilds of indexes.
        By supplying this parameter you give permission to do the rebuilds offline if the edition does not support it.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Singular Noun doesn't make sense")]
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [Alias("Tables")]
        [object[]]$Table,
        [switch]$RebuildOffline,
        [switch]$EnableException,
        [switch]$Force
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        Write-Message -Message "Starting balancing out data files" -Level Verbose

        # Set the initial success flag
        [bool]$success = $true

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check the database parameter
            if ($Database) {
                if ($Database -notin $server.Databases.Name) {
                    Stop-Function -Message "One or more databases cannot be found on instance on instance $instance" -Target $instance -Continue
                }

                $DatabaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }
            } else {
                Stop-Function -Message "Please supply a database to balance out" -Target $instance -Continue
            }

            # Get the server version
            $serverVersion = $server.Version.Major

            # Check edition of the sql instance
            if ($RebuildOffline) {
                Write-Message -Message "Continuing with offline rebuild." -Level Verbose
            } elseif (-not $RebuildOffline -and ($serverVersion -lt 9 -or (([string]$Server.Edition -notmatch "Developer") -and ($Server.Edition -notmatch "Enterprise")))) {
                # Set up the confirm part
                $message = "The server does not support online rebuilds of indexes. `nDo you want to rebuild the indexes offline?"
                $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
                $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
                $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
                $result = $host.ui.PromptForChoice($title, $message, $options, 0)

                # Check the result from the confirm
                switch ($result) {
                    # If yes
                    0 {
                        # Set the option to generate a full backup
                        Write-Message -Message "Continuing with offline rebuild." -Level Verbose

                        [bool]$supportOnlineRebuild = $false
                    }
                    1 {
                        Stop-Function -Message "You chose to not allow offline rebuilds of indexes. Use -RebuildOffline" -Target $instance
                        return
                    }
                } # switch
            } elseif ($serverVersion -ge 9 -and (([string]$Server.Edition -like "Developer*") -or ($Server.Edition -like "Enterprise*"))) {
                [bool]$supportOnlineRebuild = $true
            }

            # Loop through each of the databases
            foreach ($db in $DatabaseCollection) {
                $dataFilesStarting = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object { $_.TypeDescription -eq 'ROWS' } | Select-Object ID, LogicalName, PhysicalName, Size, UsedSpace, AvailableSpace | Sort-Object ID

                if (-not $Force) {
                    # Check the amount of disk space available
                    $query = "SELECT SUBSTRING(physical_name, 0, 4) AS 'Drive' ,
                                        SUM(( size * 8 ) / 1024) AS 'SizeMB'
                                FROM	sys.master_files
                                WHERE	DB_NAME(database_id) = '$($db.Name)'
                                GROUP BY SUBSTRING(physical_name, 0, 4)"
                    # Execute the query
                    try {
                        $dbDiskUsage = $Server.Query($query)
                    } catch {
                        $errormsg = Get-ErrorMessage -Record $PSItem
                        Stop-Function -Message "$errormsg" -ErrorRecord $_ -Target $instance -Continue
                    }

                    # Get the free space for each drive
                    try {
                        $result = $Server.Query("xp_fixeddrives")
                    } catch {
                        Stop-Function -Message "Error occurred while finding free space on drives" -ErrorRecord $_ -Target $instance -Continue
                    }
                    $MbFreeColName = $result[0].psobject.Properties.Name[1]
                    $diskFreeSpace = $result | Select-Object Drive, @{ Name = 'FreeMB'; Expression = { $_.$MbFreeColName } }

                    # Loop through each of the drives to see if the size of files on that
                    # particular disk do not exceed the free space of that disk
                    foreach ($d in $dbDiskUsage) {
                        $freeSpace = $diskFreeSpace | Where-Object { $_.Drive -eq $d.Drive.Trim(':\') } | Select-Object FreeMB
                        if ($d.SizeMB -gt $freeSpace.FreeMB) {
                            # Set the success flag
                            $success = $false

                            Stop-Function -Message "The available space may not be sufficient to continue the process. Please use -Force to try anyway." -Target $instance -Continue
                            return
                        }
                    }
                }

                # Create the start time
                $start = Get-Date

                # Check if the function needs to continue
                if ($success) {

                    # Get the database files before all the alterations
                    Write-Message -Message "Retrieving data files before data move" -Level Verbose
                    Write-Message -Message "Processing database $db" -Level Verbose

                    # Check the datafiles of the database
                    $dataFiles = Get-DbaDbFile -SqlInstance $server -Database $db | Where-Object { $_.TypeDescription -eq 'ROWS' }
                    if ($dataFiles.Count -eq 1) {
                        # Set the success flag
                        $success = $false

                        Stop-Function -Message "Database $db only has one data file. Please add a data file to balance out the data" -Target $instance -Continue
                    }

                    # Check the tables parameter
                    if ($Table) {
                        if ($Table -notin $db.Table) {
                            # Set the success flag
                            $success = $false

                            Stop-Function -Message "One or more tables cannot be found in database $db on instance $instance" -Target $instance -Continue
                        }

                        $tableCollection = $db.Tables | Where-Object { $_.Name -in $Table }
                    } else {
                        $tableCollection = $db.Tables
                    }

                    # Get the database file groups and check the aount of data files
                    Write-Message -Message "Retrieving file groups" -Level Verbose
                    $fileGroups = $Server.Databases[$db.Name].FileGroups

                    # ARray to hold the file groups with properties
                    $balanceableTables = @()

                    # Loop through each of the file groups

                    foreach ($fg in $fileGroups) {

                        # If there is less than 2 files balancing out data is not possible
                        if (($fg.Files.Count -ge 2) -and ($fg.Readonly -eq $false)) {
                            $balanceableTables += $fg.EnumObjects() | Where-Object { $_.GetType().Name -eq 'Table' }
                        }
                    }

                    $unsuccessfulTables = @()

                    # Loop through each of the tables
                    foreach ($tbl in $tableCollection) {

                        # Chck if the table balanceable
                        if ($tbl.Name -in $balanceableTables.Name) {

                            Write-Message -Message "Processing table $tbl" -Level Verbose

                            # Chck the tables and get the clustered indexes
                            if ($tableCollection.Indexes.Count -lt 1) {
                                # Set the success flag
                                $success = $false

                                Stop-Function -Message "Table $tbl does not contain any indexes" -Target $instance -Continue
                            } else {

                                # Get all the clustered indexes for the table
                                $clusteredIndexes = $tableCollection.Indexes | Where-Object { $_.IndexType -eq 'ClusteredIndex' }

                                if ($clusteredIndexes.Count -lt 1) {
                                    # Set the success flag
                                    $success = $false

                                    Stop-Function -Message "No clustered indexes found in table $tbl" -Target $instance -Continue
                                }
                            }

                            # Loop through each of the clustered indexes and rebuild them
                            Write-Message -Message "$($clusteredIndexes.Count) clustered index(es) found for table $tbl" -Level Verbose
                            if ($PSCmdlet.ShouldProcess("Rebuilding indexes to balance data")) {
                                foreach ($ci in $clusteredIndexes) {

                                    Write-Message -Message "Rebuilding index $($ci.Name)" -Level Verbose

                                    # Get the original index operation
                                    [bool]$originalIndexOperation = $ci.OnlineIndexOperation

                                    # Set the rebuild option to be either offline or online
                                    if ($RebuildOffline) {
                                        $ci.OnlineIndexOperation = $false
                                    } elseif ($serverVersion -ge 9 -and $supportOnlineRebuild -and -not $RebuildOffline) {
                                        Write-Message -Message "Setting the index operation for index $($ci.Name) to online" -Level Verbose
                                        $ci.OnlineIndexOperation = $true
                                    }

                                    # Rebuild the index
                                    try {
                                        Write-Message -Message "Rebuilding index $($ci.Name)" -Level Verbose
                                        $ci.Rebuild()

                                        # Set the success flag
                                        $success = $true
                                    } catch {
                                        # Set the original index operation back for the index
                                        $ci.OnlineIndexOperation = $originalIndexOperation

                                        # Set the success flag
                                        $success = $false

                                        Stop-Function -Message "Something went wrong rebuilding index $($ci.Name). `n$($_.Exception.Message)" -ErrorRecord $_ -Target $instance -Continue
                                    }

                                    # Set the original index operation back for the index
                                    Write-Message -Message "Setting the index operation for index $($ci.Name) back to the original value" -Level Verbose
                                    $ci.OnlineIndexOperation = $originalIndexOperation

                                } # foreach index

                            } # if process

                        } # if table is balanceable
                        else {
                            # Add the table to the unsuccessful array
                            $unsuccessfulTables += $tbl.Name

                            # Set the success flag
                            $success = $false

                            Write-Message -Message "Table $tbl cannot be balanced out" -Level Verbose
                        }

                    } #foreach table
                }

                # Create the end time
                $end = Get-Date

                # Create the time span
                $timespan = New-TimeSpan -Start $start -End $end
                $ts = [timespan]::fromseconds($timespan.TotalSeconds)
                $elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                # Get the database files after all the alterations
                Write-Message -Message "Retrieving data files after data move" -Level Verbose
                $dataFilesEnding = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object { $_.TypeDescription -eq 'ROWS' } | Select-Object ID, LogicalName, PhysicalName, Size, UsedSpace, AvailableSpace | Sort-Object ID

                [pscustomobject]@{
                    ComputerName   = $server.ComputerName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    Database       = $db.Name
                    Start          = $start
                    End            = $end
                    Elapsed        = $elapsed
                    Success        = $success
                    Unsuccessful   = $unsuccessfulTables -join ","
                    DataFilesStart = $dataFilesStarting
                    DataFilesEnd   = $dataFilesEnding
                }

            } # foreach database

        } # end process
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC4QyIJV+fSKuG3
# KX8jCgwskQYJkfOE5baOpQkWgWIetqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCB487oy8c0kVF2veUyUReU0gkAJhbKh+UnB
# srhsxtk07jANBgkqhkiG9w0BAQEFAASCAQBfjX0osbC8kVQYd4SBVpLTyQ+DYyG+
# I/qHIEfbom2lmOJuedgGGdfbQkAhciD4oOQeXbStmJ/EhMNV+AwabcwoRLO9YVxZ
# HPGD9XAYlefJDJA0dBZK8VPokMCnHIoXTWe+EB/H5mbv4y9x3MaKhzpccuR7cRRf
# nPyMOZ6nXZMsShcNQtXkIvwjyYXaADBflng7w4HPQ4KeEebcRl6SWYTPVDk6K7q/
# QZy28W8qWjFhK/JU4ZIyoX/BG9RC62F+cXRLT5ZDxPy3e08y1YG2o5hNOICSMKtY
# HmnhbDAz9q/zt1aAO5I1+MKeyCjFtXHhZTYj9B894OhEzFXTyOG5fyusoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMyNlowLwYJKoZIhvcNAQkEMSIEIDvG7MU+
# LOukK07B7FbMwEnmEGBSoj9l1JSeH9gRo3RyMA0GCSqGSIb3DQEBAQUABIICAHob
# 4paL6lLEqpZdpKPdS1DKTNFKnrXvz5Bx+iGE8YDWfBU35LQNAF3CoiUeRXUipVR/
# dfnkZq3blYbnYpZkm17MIokAoK2JppnvF8QbqldOHzP6hFTqk6b7ieWF8H7+9FKy
# iSLcUTfjRi+l7C6HWNrCVKAsnFz7Z0x6L+cznRROOLCgdVhl+fngnGuZIA6G+Pbm
# U9BoOp28c4+yrYMs13TR2nmKh4m6A5qvhFYgeETQBCV/NOSMuQo/XPjocaoaJnjU
# NccPR1fed72591WyPqx6hjsO1HB1Ygl+TN0ebH4pUnyuJ89FiHtiH352ixEiVSoM
# qtyCY/b8KHFkRl9/qEHMKzA8TxM4p019lrffik5rq46ULpiqUtWJbhZ5aeCMmT15
# t/6cAXQhAd39E1Hl9z/vE8qAZfWHo6Fu6ZqKsBLi1hnEx91B/VzA+HN3BNDiSYvP
# mfVDd2Is464CqGX4znni+PwYTPWrxI4fzI7x/9ASuMzhCmO/u2YhQK90ixDRtizA
# 8jUC7Jlj2yJV9HifrSBnNhRu1XmAu4FGmW1yxNpjAjVA2NFWBgjEzkv4kSUd0uUp
# ZTmn+z1j9z7yE7cschA2n24ohki/IbHvLvETMIaLRPk1gC0E7K6dIXyItz2bDz9I
# xMFSiOVKWLU7/a/4hCtt9KhmPU0vZhODLzsEdVLu
# SIG # End signature block
