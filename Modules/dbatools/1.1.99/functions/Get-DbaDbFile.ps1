function Get-DbaDbFile {
    <#
    .SYNOPSIS
        Returns detailed information about database files.

    .DESCRIPTION
        Returns detailed information about database files. Does not use SMO - SMO causes enumeration and this command avoids that.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER FileGroup
        Filter results to only files within this certain filegroup.

    .PARAMETER InputObject
        A piped collection of database objects

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, File, Log
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbFile

    .EXAMPLE
        PS C:\> Get-DbaDbFile -SqlInstance sql2016

        Will return an object containing all file groups and their contained files for every database on the sql2016 SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbFile -SqlInstance sql2016 -Database Impromptu

        Will return an object containing all file groups and their contained files for the Impromptu Database on the sql2016 SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbFile -SqlInstance sql2016 -Database Impromptu, Trading

        Will return an object containing all file groups and their contained files for the Impromptu and Trading databases on the sql2016 SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database Impromptu, Trading | Get-DbaDbFile

        Will accept piped input from Get-DbaDatabase and return an object containing all file groups and their contained files for the Impromptu and Trading databases on the sql2016 SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbFile -SqlInstance sql2016 -Database AdventureWorks2017 -FileGroup Index

        Return any files that are in the Index filegroup of the AdventureWorks2017 database.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$FileGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        #region Sql Query Generation
        $sql = "select
            fg.name as FileGroupName,
            df.file_id as 'ID',
            df.Type,
            df.type_desc as TypeDescription,
            df.name as LogicalName,
            mf.physical_name as PhysicalName,
            df.state_desc as State,
            df.max_size as MaxSize,
            case mf.is_percent_growth when 1 then df.growth else df.Growth*8 end as Growth,
            COALESCE(fileproperty(df.name, 'spaceused'), 0) as UsedSpace,
            df.size as Size,
            COALESCE(vfs.size_on_disk_bytes, 0) as size_on_disk_bytes,
            case df.state_desc when 'OFFLINE' then 'True' else 'False' End as IsOffline,
            case mf.is_read_only when 1 then 'True' when 0 then 'False' End as IsReadOnly,
            case mf.is_media_read_only when 1 then 'True' when 0 then 'False' End as IsReadOnlyMedia,
            case mf.is_sparse when 1 then 'True' when 0 then 'False' End as IsSparse,
            case mf.is_percent_growth when 1 then 'Percent' when 0 then 'kb' End as GrowthType,
            COALESCE(vfs.num_of_writes, 0) as NumberOfDiskWrites,
            COALESCE(vfs.num_of_reads, 0) as NumberOfDiskReads,
            COALESCE(vfs.num_of_bytes_read, 0) as BytesReadFromDisk,
            COALESCE(vfs.num_of_bytes_written, 0) as BytesWrittenToDisk,
            fg.data_space_id as FileGroupDataSpaceId,
            fg.Type as FileGroupType,
            fg.type_desc as FileGroupTypeDescription,
            case fg.is_default When 1 then 'True' when 0 then 'False' end as FileGroupDefault,
            fg.is_read_only as FileGroupReadOnly"

        $sqlfrom = "from sys.database_files df
            left outer join  sys.filegroups fg on df.data_space_id=fg.data_space_id
            left join sys.dm_io_virtual_file_stats(db_id(),NULL) vfs on df.file_id=vfs.file_id
            inner join sys.master_files mf on df.file_id = mf.file_id
            and mf.database_id = db_id()"

        $sql2008 = ",vs.available_bytes as 'VolumeFreeSpace'"
        $sql2008from = "cross apply sys.dm_os_volume_stats(db_id(),df.file_id) vs"

        $sql2000 = "select
            fg.groupname as FileGroupName,
            df.fileid as ID,
            CONVERT(INT,df.status & 0x40) / 64 as Type,
            case CONVERT(INT,df.status & 0x40) / 64 when 1 then 'LOG' else 'ROWS' end as TypeDescription,
            df.name as LogicalName,
            df.filename as PhysicalName,
            'Existing' as State,
            df.maxsize as MaxSize,
            case CONVERT(INT,df.status & 0x100000) / 1048576 when 1 then df.growth when 0 then df.growth*8 End as Growth,
            fileproperty(df.name, 'spaceused') as UsedSpace,
            df.size as Size,
            case CONVERT(INT,df.status & 0x20000000) / 536870912 when 1 then 'True' else 'False' End as IsOffline,
            case CONVERT(INT,df.status & 0x1000) / 4096 when 1 then 'True' when 0 then 'False' End as IsReadOnlyMedia,
            case CONVERT(INT,df.status & 0x10000000) / 268435456 when 1 then 'True' when 0 then 'False' End as IsSparse,
            case CONVERT(INT,df.status & 0x100000) / 1048576 when 1 then 'Percent' when 0 then 'kb' End as GrowthType,
            case CONVERT(INT,df.status & 0x1000) / 4096 when 1 then 'True' when 0 then 'False' End as IsReadOnly,
            fg.groupid as FileGroupDataSpaceId,
            NULL as FileGroupType,
            NULL AS FileGroupTypeDescription,
            CAST(fg.status & 0x10 as BIT) as FileGroupDefault,
            CAST(fg.status & 0x8 as BIT) as FileGroupReadOnly
            from sysfiles df
            left outer join  sysfilegroups fg on df.groupid=fg.groupid"
        #endregion Sql Query Generation
    }

    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            Write-Message -Level Verbose -Message "Querying database $db"

            try {
                $version = $server.Query("SELECT compatibility_level FROM sys.databases WHERE name = '$($db.Name)'")
                $version = [int]($version.compatibility_level / 10)
            } catch {
                $version = 8
            }

            if ($version -ge 11) {
                $query = ($sql, $sql2008, $sqlfrom, $sql2008from) -Join "`n"
            } elseif ($version -ge 9) {
                $query = ($sql, $sqlfrom) -Join "`n"
            } else {
                $query = $sql2000
            }

            Write-Message -Level Debug -Message "SQL Statement: $query"

            try {
                $results = $server.Query($query, $db.Name)
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }

            if (Test-Bound -ParameterName FileGroup) {
                Write-Message -Message "Results will be filtered to FileGroup specified" -Level Verbose
                $results = $results | Where-Object { $_.FileGroupName -eq $FileGroup }
            }

            foreach ($result in $results) {
                $size = [dbasize]($result.Size * 8192)
                $usedspace = [dbasize]($result.UsedSpace * 8192)
                $maxsize = $result.MaxSize
                # calculation is done here because for snapshots or sparse files size is not the "virtual" size
                # (master_files.Size) but the currently allocated one (dm_io_virtual_file_stats.size_on_disk_bytes)
                $AvailableSpace = $size - $usedspace
                if ($result.size_on_disk_bytes) {
                    $size = [dbasize]($result.size_on_disk_bytes)
                }
                if ($maxsize -gt -1) {
                    $maxsize = [dbasize]($result.MaxSize * 8192)
                } else {
                    $maxsize = [dbasize]($result.MaxSize)
                }

                if ($result.VolumeFreeSpace) {
                    $VolumeFreeSpace = [dbasize]$result.VolumeFreeSpace
                } else {
                    # to get drive free space for each drive that a database has files on
                    # when database compatibility lower than 110. Lets do this with query2
                    $query2 = @'
-- to get drive free space for each drive that a database has files on
DECLARE @FixedDrives TABLE(Drive CHAR(1), MB_Free BIGINT);
INSERT @FixedDrives EXEC sys.xp_fixeddrives;

SELECT DISTINCT fd.MB_Free, LEFT(df.physical_name, 1) AS [Drive]
FROM @FixedDrives AS fd
INNER JOIN sys.database_files AS df
ON fd.Drive = LEFT(df.physical_name, 1);
'@
                    # if the server has one drive xp_fixeddrives returns one row, but we still need $disks to be an array.
                    if ($server.VersionMajor -gt 8) {
                        $disks = @($server.Query($query2, $db.Name))
                        $MbFreeColName = $disks[0].psobject.Properties.Name
                        # get the free MB value for the drive in question
                        $free = $disks | Where-Object {
                            $_.drive -eq $result.PhysicalName.Substring(0, 1)
                        } | Select-Object $MbFreeColName

                    $VolumeFreeSpace = [dbasize](($free.MB_Free) * 1024 * 1024)
                }
            }
            if ($result.GrowthType -eq "Percent") {
                $nextgrowtheventadd = [dbasize]($result.size * 8 * ($result.Growth * 0.01) * 1024)
            } else {
                $nextgrowtheventadd = [dbasize]($result.Growth * 1024)
            }
            if (($nextgrowtheventadd.Byte -gt ($MaxSize.Byte - $size.Byte)) -and $maxsize -gt 0) {
                [dbasize]$nextgrowtheventadd = 0
            }

            [PSCustomObject]@{
                ComputerName             = $server.ComputerName
                InstanceName             = $server.ServiceName
                SqlInstance              = $server.DomainInstanceName
                Database                 = $db.name
                DatabaseID               = $db.ID
                FileGroupName            = $result.FileGroupName
                ID                       = $result.ID
                Type                     = $result.Type
                TypeDescription          = $result.TypeDescription
                LogicalName              = $result.LogicalName.Trim()
                PhysicalName             = $result.PhysicalName.Trim()
                State                    = $result.State
                MaxSize                  = $maxsize
                Growth                   = $result.Growth
                GrowthType               = $result.GrowthType
                NextGrowthEventSize      = $nextgrowtheventadd
                Size                     = $size
                UsedSpace                = $usedspace
                AvailableSpace           = $AvailableSpace
                IsOffline                = $result.IsOffline
                IsReadOnly               = $result.IsReadOnly
                IsReadOnlyMedia          = $result.IsReadOnlyMedia
                IsSparse                 = $result.IsSparse
                NumberOfDiskWrites       = $result.NumberOfDiskWrites
                NumberOfDiskReads        = $result.NumberOfDiskReads
                ReadFromDisk             = [dbasize]$result.BytesReadFromDisk
                WrittenToDisk            = [dbasize]$result.BytesWrittenToDisk
                VolumeFreeSpace          = $VolumeFreeSpace
                FileGroupDataSpaceId     = $result.FileGroupDataSpaceId
                FileGroupType            = $result.FileGroupType
                FileGroupTypeDescription = $result.FileGroupTypeDescription
                FileGroupDefault         = $result.FileGroupDefault
                FileGroupReadOnly        = $result.FileGroupReadOnly
            }
        }
    }
}
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUUkamUKqWZ1S2Qb/iaABrflBO
# tKKgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFN2GF3ymQh+9CUMy53VLhxwnJBxAMA0G
# CSqGSIb3DQEBAQUABIIBAA8AqIRIAwFuc6IH/Attluj4Z+0njaNLBSIVk7EOzsgl
# XoJ/mdNOK1c5hEn9xDu+vldbYdAVwsCryBB3ijSyl6h7j/CJhhZrMdrBNj9srqj1
# A8hCjQUFgKfAb8Oq8DbehrOWAr0vSePWwWL3qPLkeg9MSdxQgjQd1II1DfaBSYrC
# Fc+MmHL9OprNaLxVxOCWtH0amiilEP3A6SvvzInqaJKP63e3oHq4FskKHEtkz5RR
# CJO57c5V3magu4fBK4XJXV+ImxPJzs9wfmBxBeDL93Vb2CrgzUBQYLqQnQ8+VoU+
# ULMNECgnDGtzcVo/agarkZ98L8o0EanrNRziczevGDShggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzI5WjAvBgkqhkiG9w0BCQQxIgQgr4iiPWvhK9XHvQw98qfJ
# eKl56EoC4wD5tKv9v6vD6ggwDQYJKoZIhvcNAQEBBQAEggIAYp4uHP9A8Sk0yJe9
# aw7rXip06EAwnptGpBIKJ5c2cD49XbiuH+2JUnqOYfuizUZ3t+GEdyV73j+VsN7f
# kV1+5ZDtNArwZZ3GnLAosUVxV9jNaIzgIy+rfG7pnVbi7e3IQdiobe/41eCTrRmO
# pGfM4op+GDg6KZXTtPZwjL9KZdlpg2VJBMyKSvd2TCqAua0MC1gof87XXGXx2BDT
# +YzLHJwUWIKdICFNUn67HwZlwyW31Jnscnw8CWLSPSDqQ7/gfluyfkmQ3tLErD8B
# 3gDanW8ihdANSyd2JEGAdMeJDOV7Wu8VRz5lGt0Jk+6fBHkpyX6EUw+y1sDjU4NV
# p04hUuw4cviPbluIYIsJoo4q3IYI45e+8vJgITO3IatA4wQ1fZturI4yuP3iSWLU
# YlN9j+LoUokGmjP/6SFSvLMHyXncg35ua3TvEatJAMScI4egYW8SC8vxiZRN1/pz
# NVPCxrulsXBKaCIe+gystVFzdBX9b6ZvwavcOr5KcNHZFyi+TFf6a/M/8AvGEd7R
# zsNAIDP48XEuHmnouPIaT73DzQgs4Mjl5n+QW7GAM1Q7UmS2Cj7WDyKNAUXlJsW0
# r5yWBLodg01IuvNGX2BUaVyGJHD2K4lgMXFCB6CyiueJ6mCmy6hEn1pwwX2lRMl+
# bJ2aDogsrAb0ePw/aZi361dPSXQ=
# SIG # End signature block
