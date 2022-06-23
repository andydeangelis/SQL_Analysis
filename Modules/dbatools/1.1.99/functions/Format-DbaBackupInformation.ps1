function Format-DbaBackupInformation {
    <#
    .SYNOPSIS
        Transforms the data in a dbatools BackupHistory object for a restore

    .DESCRIPTION
        Performs various mapping on Backup History, ready restoring
        Options include changing restore paths, backup paths, database name and many others

    .PARAMETER BackupHistory
        A dbatools backupHistory object, normally this will have been created using Select-DbaBackupInformation

    .PARAMETER ReplaceDatabaseName
        If a single value is provided, this will be replaced do all occurrences a database name
        If a Hashtable is passed in, each database name mention will be replaced as specified. If a database's name does not appear it will not be replace
        DatabaseName will also be replaced where it  occurs in the file paths of data and log files.
        Please note, that this won't change the Logical Names of data files, that has to be done with a separate Alter DB call

    .PARAMETER DatabaseNamePrefix
        This string will be prefixed to all restored database's name

    .PARAMETER DataFileDirectory
        This will move ALL restored files to this location during the restore

    .PARAMETER LogFileDirectory
        This will move all log files to this location, overriding DataFileDirectory

    .PARAMETER DestinationFileStreamDirectory
        This move the FileStream folder and contents to the new location, overriding DataFileDirectory

    .PARAMETER FileNamePrefix
        This string will  be prefixed to all restored files (Data and Log)

    .PARAMETER RebaseBackupFolder
        Use this to rebase where your backups are stored.

    .PARAMETER Continue
        Indicates that this is a continuing restore

    .PARAMETER DatabaseFilePrefix
        A string that will be prefixed to every file restored

    .PARAMETER DatabaseFileSuffix
        A string that will be suffixed to every file restored

    .PARAMETER ReplaceDbNameInFile
        If set, will replace the old database name with the new name if it occurs in the file name

    .PARAMETER FileMapping
        A hashtable that can be used to move specific files to a location.
        `$FileMapping = @{'DataFile1'='c:\restoredfiles\Datafile1.mdf';'DataFile3'='d:\DataFile3.mdf'}`
        And files not specified in the mapping will be restored to their original location
        This Parameter is exclusive with DestinationDataDirectory
        If specified, this will override any other file renaming/relocation options.

    .PARAMETER PathSep
        By default is Windows's style (`\`) but you can pass also, e.g., `/` for Unix's style paths

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Format-DbaBackupInformation

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -ReplaceDatabaseName NewDb

        Changes as database name references to NewDb, both in the database name and any restore paths. Note, this will fail if the BackupHistory object contains backups for more than 1 database

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -ReplaceDatabaseName @{'OldB'='NewDb';'ProdHr'='DevHr'}

        Will change all occurrences of original database name in the backup history (names and restore paths) using the mapping in the hashtable.
        In this example any occurrence of OldDb will be replaced with NewDb and ProdHr with DevPR

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -DataFileDirectory 'D:\DataFiles\' -LogFileDirectory 'E:\LogFiles\

        This example with change the restore path for all data files (everything that is not a log file) to d:\datafiles
        And all Transaction Log files will be restored to E:\Logfiles

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -RebaseBackupFolder f:\backups

        This example changes the location that SQL Server will look for the backups. This is useful if you've moved the backups to a different location

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$BackupHistory,
        [object]$ReplaceDatabaseName,
        [switch]$ReplaceDbNameInFile,
        [string]$DataFileDirectory,
        [string]$LogFileDirectory,
        [string]$DestinationFileStreamDirectory,
        [string]$DatabaseNamePrefix,
        [string]$DatabaseFilePrefix,
        [string]$DatabaseFileSuffix,
        [string]$RebaseBackupFolder,
        [switch]$Continue,
        [hashtable]$FileMapping,
        [string]$PathSep = '\',
        [switch]$EnableException
    )
    begin {

        Write-Message -Message "Starting" -Level Verbose
        if ($null -ne $ReplaceDatabaseName) {
            if ($ReplaceDatabaseName -is [string] -or $ReplaceDatabaseName.ToString() -ne 'System.Collections.Hashtable') {
                Write-Message -Message "String passed in for DB rename" -Level Verbose
                $ReplaceDatabaseNameType = 'single'
            } elseif ($ReplaceDatabaseName -is [HashTable] -or $ReplaceDatabaseName.ToString() -eq 'System.Collections.Hashtable' ) {
                Write-Message -Message "Hashtable passed in for DB rename" -Level Verbose
                $ReplaceDatabaseNameType = 'multi'
            } else {
                Write-Message -Message "ReplacemenDatabaseName is $($ReplaceDatabaseName.Gettype().ToString()) - $ReplaceDatabaseName" -level Verbose
            }
        }
        if ((Test-Bound -Parameter DataFileDirectory) -and $DataFileDirectory.EndsWith($PathSep)) {
            $DataFileDirectory = $DataFileDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter DestinationFileStreamDirectory) -and $DestinationFileStreamDirectory.EndsWith($PathSep) ) {
            $DestinationFileStreamDirectory = $DestinationFileStreamDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter LogFileDirectory) -and $LogFileDirectory.EndsWith($PathSep) ) {
            $LogFileDirectory = $LogFileDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter RebaseBackupFolder) -and $RebaseBackupFolder.EndsWith($PathSep) ) {
            $RebaseBackupFolder = $RebaseBackupFolder -Replace '.$'
        }
    }


    process {

        foreach ($History in $BackupHistory) {
            if ("OriginalDatabase" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalDatabase' -Type NoteProperty -Value $History.Database
            }
            if ("OriginalFileList" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalFileList' -Type NoteProperty -Value ''
                $History | ForEach-Object { $_.OriginalFileList = $_.FileList }
            }
            if ("OriginalFullName" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalFullName' -Type NoteProperty -Value $History.FullName
            }
            if ("IsVerified" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'IsVerified' -Type NoteProperty -Value $False
            }
            switch ($History.Type) {
                'Full' { $History.Type = 'Database' }
                'Differential' { $History.Type = 'Database Differential' }
                'Log' { $History.Type = 'Transaction Log' }
            }


            if ($ReplaceDatabaseNameType -eq 'single' -and $ReplaceDatabaseName -ne '' ) {
                $History.Database = $ReplaceDatabaseName
                Write-Message -Message "New DbName (String) = $($History.Database)" -Level Verbose
            } elseif ($ReplaceDatabaseNameType -eq 'multi') {
                if ($null -ne $ReplaceDatabaseName[$History.Database]) {
                    $History.Database = $ReplaceDatabaseName[$History.Database]
                    Write-Message -Message "New DbName (Hash) = $($History.Database)" -Level Verbose
                }
            }
            $History.Database = $DatabaseNamePrefix + $History.Database

            $History.FileList | ForEach-Object {
                if ($null -ne $FileMapping ) {
                    if ($null -ne $FileMapping[$_.LogicalName]) {
                        $_.PhysicalName = $FileMapping[$_.LogicalName]
                    }
                } else {
                    if ($ReplaceDbNameInFile -eq $true) {
                        $_.PhysicalName = $_.PhysicalName -Replace $History.OriginalDatabase, $History.Database
                    }
                    Write-Message -Message " 1 PhysicalName = $($_.PhysicalName) " -Level Verbose
                    $Pname = [System.Io.FileInfo]$_.PhysicalName
                    $RestoreDir = $Pname.DirectoryName
                    if ($_.Type -eq 'D' -or $_.FileType -eq 'D') {
                        if ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    } elseif ($_.Type -eq 'L' -or $_.FileType -eq 'L') {
                        if ('' -ne $LogFileDirectory) {
                            $RestoreDir = $LogFileDirectory
                        } elseif ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    } elseif ($_.Type -eq 'S' -or $_.FileType -eq 'S') {
                        if ('' -ne $DestinationFileStreamDirectory) {
                            $RestoreDir = $DestinationFileStreamDirectory
                        } elseif ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    }

                    $_.PhysicalName = $RestoreDir + $PathSep + $DatabaseFilePrefix + $Pname.BaseName + $DatabaseFileSuffix + $Pname.extension
                    Write-Message -Message "PhysicalName = $($_.PhysicalName) " -Level Verbose
                }
            }
            if ('' -ne $RebaseBackupFolder -and $History.FullName[0] -notmatch 'http') {
                Write-Message -Message 'Rebasing backup files' -Level Verbose

                for ($j = 0; $j -lt $History.fullname.count; $j++) {
                    $file = [System.IO.FileInfo]($History.fullname[$j])
                    $History.fullname[$j] = $RebaseBackupFolder + $PathSep + $file.BaseName + $file.Extension
                }

            }

            $History
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUR9gHHxJCF3H0SV5VsGa8ls/R
# 2AqgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFBABqlFXjcjcoBBCQqcPM1OdomaaMA0G
# CSqGSIb3DQEBAQUABIIBABUgNqkz9cxqRZCjMixqo/X93DOl8KZfgy74sBG1mNcb
# s8ID5mkS4p0XBLoLePTt63Cqs2wYLnyBkuHs48ajIDZdsFpO7enJhbqK62V94ZTG
# bm0oyEcBlJLj8WdrhQ/QVcbY0dil+kw8JucI7BVZhwucA3YgwFg1/lzO+CkzDVGR
# FjiHn0K1OlE5w3RDMJeGqy0rSsHtg9BdFwswyJiCtiWY8qfiorkOwQQBNGYFH3I0
# Qc3NqjvxdnGRSu7M60XJkfdOUEah+KThI3BFenDU6e9QfshXMbDxweEuPVZb+2fs
# tEB55Yo7qFuSljrEWDEG2yMUrybd3O9Porqm9wlOk+yhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzIyWjAvBgkqhkiG9w0BCQQxIgQgDZYtQZaXz0/waa/Sux/V
# jQqh8Y/9s93azAvac7M+3ygwDQYJKoZIhvcNAQEBBQAEggIANsUpT5XREQsmpH+a
# 3kNRvDyIQhmBoo89WJsNS4AHtnQUox3jOQ5wWtKSKqX+L9YiDHW1NjU0YZgklYfk
# zvFDcYRAg6QBYGjVekt4L7nByxZ2JLa6uhXrlmr48lQbSvlSdyUiiP6AUdVyduWx
# ExDtzTFH0/fTeZ9RVpOnWXdpwDxiKzb74Jbl7U5IVhlodno89kOm0CuaCLqqP2Ag
# AET1rZkT9APuG4u2+clDDZ75LA5Yl7tPKACJ5pU3RWTL2c1NIZ4hI9TF346x+Lan
# oEWtwsOOxF8i6W3RqS0sIP5oamYjDrOIMlVM+099R1Z+/+h07yCH8Pr71HJldOWb
# Ts4rFkTX+JrmVhrNJnyaSONtl704f+VoGZi+A3Yk103c9NGvn+DA7jHY6YHl5JbB
# eHIupgsDiGafh7cJFTG/0KVOvrBozCVMKz86F+K05wqcASDbNVLOHPonj0V1y5op
# DLqC2bCteJuUPEbAl0Gc0rNOVvFJC0Uw49ijxypKWHw0RNYvPnJZnJ4Tk7ZneDGz
# QOO7GvISN6t3a/7CMeNqp9c3/DA0BUMBXPJx9ZbYHsBiklFc5Cp3JvIuMfWGSwyV
# ROCQ7zKe+0x+zCxruiI28b1oZWbhpP94RSmMG67gSGxhvS5zl8k0WPSMe3ZlnKpq
# S+wl0eqbcpTBH0ks+gEZWZ+ynjA=
# SIG # End signature block
