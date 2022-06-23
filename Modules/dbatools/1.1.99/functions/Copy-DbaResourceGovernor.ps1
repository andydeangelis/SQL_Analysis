function Copy-DbaResourceGovernor {
    <#
    .SYNOPSIS
        Migrates Resource Pools

    .DESCRIPTION
        By default, all non-system resource pools are migrated. If the pool already exists on the destination, it will be skipped unless -Force is used.

        The -ResourcePool parameter is auto-populated for command-line completion and can be used to copy only specific objects.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2008 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ResourcePool
        Specifies the resource pool(s) to process. Options for this list are auto-populated from the server. If unspecified, all resource pools will be processed.

    .PARAMETER ExcludeResourcePool
        Specifies the resource pool(s) to exclude. Options for this list are auto-populated from the server

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the policies will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, ResourceGovernor
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaResourceGovernor

    .EXAMPLE
        PS C:\> Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster

        Copies all all non-system resource pools from sqlserver2014a to sqlcluster using Windows credentials to connect to the SQL Server instances..

    .EXAMPLE
        PS C:\> Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all all non-system resource pools from sqlserver2014a to sqlcluster using SQL credentials to connect to sqlserver2014a and Windows credentials to connect to sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$ResourcePool,
        [object[]]$ExcludeResourcePool,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $sourceClassifierFunction = Get-DbaRgClassifierFunction -SqlInstance $sourceServer

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destClassifierFunction = Get-DbaRgClassifierFunction -SqlInstance $destServer

            $copyResourceGovSetting = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Resource Governor Settings"
                Name              = "All Settings"
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            $copyResourceGovClassifierFunc = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Resource Governor Settings"
                Name              = "Classifier Function"
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            if ($Pscmdlet.ShouldProcess($destinstance, "Updating Resource Governor settings")) {
                if ($destServer.Edition -notmatch 'Enterprise' -and $destServer.Edition -notmatch 'Datacenter' -and $destServer.Edition -notmatch 'Developer') {
                    Write-Message -Level Verbose -Message "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
                } else {
                    try {
                        Write-Message -Level Verbose -Message "Managing classifier function."
                        if (!$sourceClassifierFunction) {
                            $copyResourceGovClassifierFunc.Status = "Skipped"
                            $copyResourceGovClassifierFunc.Notes = $null
                            $copyResourceGovClassifierFunc | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } else {
                            $fullyQualifiedFunctionName = $sourceClassifierFunction.Schema + "." + $sourceClassifierFunction.Name

                            if (!$destClassifierFunction) {
                                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                                $destFunction = $destServer.Databases["master"].UserDefinedFunctions[$sourceClassifierFunction.Name]
                                if ($destFunction) {
                                    Write-Message -Level Verbose -Message "Dropping the function with the source classifier function name."
                                    $destFunction.Drop()
                                }

                                Write-Message -Level Verbose -Message "Creating function."
                                $destServer.Query($sourceClassifierFunction.Script())

                                $sql = "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = $fullyQualifiedFunctionName);"
                                Write-Message -Level Debug -Message $sql
                                Write-Message -Level Verbose -Message "Mapping Resource Governor classifier function."
                                $destServer.Query($sql)

                                $copyResourceGovClassifierFunc.Status = "Successful"
                                $copyResourceGovClassifierFunc.Notes = "The new classifier function has been created"
                                $copyResourceGovClassifierFunc | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                                Write-Message -Level Debug -Message $sql
                                Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                                $destServer.Query($sql)
                            } else {
                                if ($Force -eq $false) {
                                    $copyResourceGovClassifierFunc.Status = "Skipped"
                                    $copyResourceGovClassifierFunc.Notes = "Already exists on destination"
                                    $copyResourceGovClassifierFunc | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                } else {

                                    $sql = "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL);"
                                    Write-Message -Level Debug -Message $sql
                                    Write-Message -Level Verbose -Message "Disabling the Resource Governor."
                                    $destServer.Query($sql)

                                    $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                                    Write-Message -Level Debug -Message $sql
                                    Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                                    $destServer.Query($sql)

                                    Write-Message -Level Verbose -Message "Dropping the destination classifier function."
                                    $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                                    $destFunction = $destServer.Databases["master"].UserDefinedFunctions[$sourceClassifierFunction.Name]
                                    $destClassifierFunction.Drop()

                                    Write-Message -Level Verbose -Message "Re-creating the Resource Governor classifier function."
                                    $destServer.Query($sourceClassifierFunction.Script())

                                    $sql = "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = $fullyQualifiedFunctionName);"
                                    Write-Message -Level Debug -Message $sql
                                    Write-Message -Level Verbose -Message "Mapping Resource Governor classifier function."
                                    $destServer.Query($sql)

                                    $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                                    Write-Message -Level Debug -Message $sql
                                    Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                                    $destServer.Query($sql)

                                    $copyResourceGovClassifierFunc.Status = "Successful"
                                    $copyResourceGovClassifierFunc.Notes = "The old classifier function has been overwritten."
                                    $copyResourceGovClassifierFunc | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
                            }
                        }
                    } catch {
                        $copyResourceGovSetting.Status = "Failed"
                        $copyResourceGovSetting.Notes = (Get-ErrorMessage -Record $_)
                        $copyResourceGovSetting | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                        $destServer.Query($sql)

                        Stop-Function -Message "Not able to update settings." -Target $destServer -ErrorRecord $_
                    }
                }
            }

            # Pools
            if ($ResourcePool) {
                $pools = $sourceServer.ResourceGovernor.ResourcePools | Where-Object Name -In $ResourcePool
            } elseif ($ExcludeResourcePool) {
                $pool = $sourceServer.ResourceGovernor.ResourcePools | Where-Object Name -NotIn $ExcludeResourcePool
            } else {
                $pools = $sourceServer.ResourceGovernor.ResourcePools | Where-Object { $_.Name -notin "internal", "default" }
            }

            Write-Message -Level Verbose -Message "Migrating pools."
            foreach ($pool in $pools) {
                $poolName = $pool.Name

                $copyResourceGovPool = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Resource Governor Pool"
                    Name              = $poolName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destServer.ResourceGovernor.ResourcePools[$poolName]) {
                    if ($force -eq $false) {
                        Write-Message -Level Verbose -Message "Pool '$poolName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate."

                        $copyResourceGovPool.Status = "Skipped"
                        $copyResourceGovPool.Notes = "Already exists on destination"
                        $copyResourceGovPool | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Attempting to drop $poolName")) {
                            Write-Message -Level Verbose -Message "Pool '$poolName' exists on $destinstance."
                            Write-Message -Level Verbose -Message "Force specified. Dropping $poolName."

                            try {
                                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                                $destPool = $destServer.ResourceGovernor.ResourcePools[$poolName]
                                $workloadGroups = $destPool.WorkloadGroups
                                foreach ($workloadGroup in $workloadGroups) {
                                    $workloadGroup.Drop()
                                }
                                $destPool.Drop()
                                $destServer.ResourceGovernor.Alter()
                            } catch {
                                $copyResourceGovPool.Status = "Failed to drop from Destination"
                                $copyResourceGovPool.Notes = (Get-ErrorMessage -Record $_)
                                $copyResourceGovPool | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Stop-Function -Message "Unable to drop: $_ Moving on." -Target $destPool -ErrorRecord $_ -Continue

                                $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                                Write-Message -Level Debug -Message $sql
                                Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                                $destServer.Query($sql)
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Migrating pool $poolName")) {
                    try {
                        $sql = $pool.Script() | Out-String
                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Copying pool $poolName."
                        $destServer.Query($sql)

                        $copyResourceGovPool.Status = "Successful"
                        $copyResourceGovPool | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        $workloadGroups = $pool.WorkloadGroups
                        foreach ($workloadGroup in $workloadGroups) {
                            $workgroupName = $workloadGroup.Name

                            $copyResourceGovWorkGroup = [pscustomobject]@{
                                SourceServer      = $sourceServer.Name
                                DestinationServer = $destServer.Name
                                Type              = "Resource Governor Pool Workgroup"
                                Name              = $workgroupName
                                Status            = $null
                                Notes             = $null
                                DateTime          = [DbaDateTime](Get-Date)
                            }

                            $sql = $workloadGroup.Script() | Out-String
                            Write-Message -Level Debug -Message $sql
                            Write-Message -Level Verbose -Message "Copying $workgroupName."
                            $destServer.Query($sql)

                            $copyResourceGovWorkGroup.Status = "Successful"
                            $copyResourceGovWorkGroup | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                            Write-Message -Level Debug -Message $sql
                            Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                            $destServer.Query($sql)
                        }
                    } catch {
                        if ($copyResourceGovWorkGroup) {
                            $copyResourceGovWorkGroup.Status = "Failed"
                            $copyResourceGovWorkGroup.Notes = (Get-ErrorMessage -Record $_)
                            $copyResourceGovWorkGroup | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        Stop-Function -Message "Unable to migrate pool." -Target $pool -ErrorRecord $_
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destinstance, "Reconfiguring")) {
                if ($destServer.Edition -notmatch 'Enterprise' -and $destServer.Edition -notmatch 'Datacenter' -and $destServer.Edition -notmatch 'Developer') {
                    Write-Message -Level Verbose -Message "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
                } else {

                    Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                    try {
                        if (!$sourceServer.ResourceGovernor.Enabled) {
                            $sql = "ALTER RESOURCE GOVERNOR DISABLE"
                            $destServer.Query($sql)

                            $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                            Write-Message -Level Debug -Message $sql
                            Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                            $destServer.Query($sql)
                        } else {
                            $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE"
                            $destServer.Query($sql)
                        }
                    } catch {
                        $altermsg = $_.Exception
                    }


                    $copyResourceGovReconfig = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Type              = "Reconfigure Resource Governor"
                        Name              = "Reconfigure Resource Governor"
                        Status            = "Successful"
                        Notes             = $altermsg
                        DateTime          = [DbaDateTime](Get-Date)
                    }
                    $copyResourceGovReconfig | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUquNuXlkgz+D5gxgrIG4n13La
# 2aOgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFDZ2eiTO+SFFlHGa1BWmWO6FuqyJMA0G
# CSqGSIb3DQEBAQUABIIBAGB2bfkGdJQLX9QCjuFPojbX/OWy3M72S0IAcQ8Uoe0C
# Z4NhUO8e4K4bAWRxYHtGrfwN3ydGAVasrGpiwvb2AkutVUez7w54UMvA2zYfOzSR
# BjoOM1SAUPoxFoqzLLfUR+bAJZrUL7D5HlJJyrGhaKMWckA1t2lfEgbHF6HuKlLE
# VjYcscFB9vrxrXtMnO614dxjB2gNkhnakfGLDU/hFqbPx9xpY6mbPJttX5UdUZBy
# cc37yqs+Ms91raBIJJKld6TXj3xWRVhTRK2FnBUMRZMg1tjl1ZH7CZyvOGJWjpMg
# ReKrDyfaEA1k/rAiLNDvN6ORgRxg1fxhHywVC6zlS/yhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzE0WjAvBgkqhkiG9w0BCQQxIgQgnE/O3psJfmEAZ9pQ7LP4
# 200ujI0fJKjoJLkU1j6FQywwDQYJKoZIhvcNAQEBBQAEggIAAlfAsuLAnbhqnU4G
# Et7hnVIr44NkGA+W3HgH656mdr6JhyZo/fiEFnvnDmhfo3vyKDgMDc2Cf4HqouSz
# Dni5HbgwXFLuAhRUQfvfbFrz04Op47konc6TMjSbJ7OuHGUKiB2CKjsDWIYu0gOU
# 27Rc/3q7AKNg2/G8Bt7wsu7q9VwpH00vdOiEANb93gNQujdS9YWBNKaRnw73PJr7
# 75Jo4gxsLNCUAQeisRLl9iDXyxbc69wiw/y7ax1J5BiJMu21/k6jD3RjHho14zx9
# V/XBTX6h5PcU3c9c9d23pAlZmRaNun+1+KCVu5dVGDaCxX1oDEkoq6ULMZu9aSI9
# R1XxKMlEcowcUTsAgUpOHGCUcQtcKwUMA3qqxnS2hB/xioJ4sbcS+6QmwRieYkvW
# ITvO/TnWcqUywy9p5kgCJimEkXEtbNZnCwWb8q56+sMZSzCIuYgdH4U082r3wAOX
# MgVha2KJNLOkAccGnQ87BLDYFQUe50kNeqBPp+nJy+GllcWN9anvqWQHRKgG1GYm
# mkPYvHifTPy1DiOPjjqdUDKT9BTw4UbteFG0OQ0XJaWNpXGd9jZ1PHkXLVGioqwc
# e4DIVd8stOCzNrRPN8C4a/DsvnWEOuI9us3RHWUlTUL7MneER2hmeBfJ4plVYS1U
# WvYdkK/iZYPWpUi2jWXNPfHctgM=
# SIG # End signature block
