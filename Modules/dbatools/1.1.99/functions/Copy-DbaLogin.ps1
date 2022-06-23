function Copy-DbaLogin {
    <#
    .SYNOPSIS
        Migrates logins from source to destination SQL Servers. Supports SQL Server versions 2000 and newer.

    .DESCRIPTION
        SQL Server 2000: Migrates logins with SIDs, passwords, server roles and database roles.

        SQL Server 2005 & newer: Migrates logins with SIDs, passwords, defaultdb, server roles & securables, database permissions & securables, login attributes (enforce password policy, expiration, etc.)

        The login hash algorithm changed in SQL Server 2012, and is not backwards compatible with previous SQL Server versions. This means that while SQL Server 2000 logins can be migrated to SQL Server 2012, logins created in SQL Server 2012 can only be migrated to SQL Server 2012 and above.

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

    .PARAMETER Login
        The login(s) to process. Options for this list are auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        The login(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER ExcludeSystemLogins
        If this switch is enabled, NT SERVICE accounts will be skipped.

    .PARAMETER ExcludePermissionSync
        Skips permission syncs

    .PARAMETER SyncSaName
        If this switch is enabled, the name of the sa account will be synced between Source and Destination

    .PARAMETER OutFile
        Calls Export-DbaLogin and exports all logins to a T-SQL formatted file. This does not perform a copy, so no destination is required.

    .PARAMETER InputObject
        Takes the parameters required from a Login object that has been piped into the command

    .PARAMETER NewSid
        Ignore sids from the source login objects to generate new sids on the destination server. Useful when copying login onto the same server

    .PARAMETER LoginRenameHashtable
        Pass a hash table into this parameter to create logins under different names based on hashtable mapping.

    .PARAMETER ObjectLevel
        Include object-level permissions for each user associated with copied login.

    .PARAMETER KillActiveConnection
        A login cannot be dropped when it has active connections on the instance. If this switch is enabled, all active connections and sessions on Destination will be killed.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Login(s) will be dropped and recreated on Destination. Logins that own Agent jobs cannot be dropped at this time.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Login
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaLogin

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Force

        Copies all logins from Source Destination. If a SQL Login on Source exists on the Destination, the Login on Destination will be dropped and recreated.

        If active connections are found for a login, the copy of that Login will fail as it cannot be dropped.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Force -KillActiveConnection

        Copies all logins from Source Destination. If a SQL Login on Source exists on the Destination, the Login on Destination will be dropped and recreated.

        If any active connections are found they will be killed.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -ExcludeLogin realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

        Copies all Logins from Source to Destination except for realcajun using SQL Authentication to connect to both instances.

        If a Login already exists on the destination, it will not be migrated.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds -force

        Copies ONLY Logins netnerds and realcajun. If Login realcajun or netnerds exists on Destination, the existing Login(s) will be dropped and recreated.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -LoginRenameHashtable @{ "PreviousUser" = "newlogin" } -Source $Sql01 -Destination Localhost -SourceSqlCredential $sqlcred -Login PreviousUser

        Copies PreviousUser as newlogin.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -LoginRenameHashtable @{ OldLogin = "NewLogin" } -Source Sql01 -Destination Sql01 -Login ORG\OldLogin -ObjectLevel -NewSid

        Clones OldLogin as NewLogin onto the same server, generating a new SID for the login. Also clones object-level permissions.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 | Out-GridView -Passthru | Copy-DbaLogin -Destination sql2017

        Displays all available logins on sql2016 in a grid view, then copies all selected logins to sql2017.

    .EXAMPLE
        PS C:\> $loginSplat = @{
        >> Source = $Sql01
        >> Destination = "Localhost"
        >> SourceSqlCredential = $sqlcred
        >> Login = 'ReadUserP', 'ReadWriteUserP', 'AdminP'
        >> LoginRenameHashtable = @{
        >> "ReadUserP" = "ReadUserT"
        >> "ReadWriteUserP" = "ReadWriteUserT"
        >> "AdminP"         = "AdminT"
        >> }
        >> }
        PS C:\> Copy-DbaLogin @loginSplat

        Copies the three specified logins to 'localhost' and renames them according to the LoginRenameHashTable.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(ParameterSetName = "File", Mandatory)]
        [parameter(ParameterSetName = "SqlInstance", Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(ParameterSetName = "SqlInstance", Mandatory)]
        [parameter(ParameterSetName = "InputObject", Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Login,
        [object[]]$ExcludeLogin,
        [switch]$ExcludeSystemLogins,
        [parameter(ParameterSetName = "Live")]
        [parameter(ParameterSetName = "SqlInstance")]
        [switch]$SyncSaName,
        [parameter(ParameterSetName = "File", Mandatory)]
        [string]$OutFile,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [object[]]$InputObject,
        [hashtable]$LoginRenameHashtable,
        [switch]$KillActiveConnection,
        [switch]$NewSid,
        [switch]$Force,
        [switch]$ObjectLevel,
        [switch]$ExcludePermissionSync,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
        function Copy-Login {
            [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
            Param (
                $SourceServer,
                $DestServer,
                $Login,
                $Exclude
            )
            if ($LoginRenameHashtable.Keys -contains $Login.name) {
                $newUserName = $LoginRenameHashtable[$Login.name]
            } else {
                $newUserName = $Login.name
            }

            $copyLoginStatus = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Login - $($Login.LoginType)"
                Name              = $newUserName
                DestinationLogin  = $newUserName
                SourceLogin       = $Login.name
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            if ($ExcludeLogin -contains $Login.name) { continue }

            if ($Login.id -eq 1) { continue }

            if ($newUserName.StartsWith("##") -or $newUserName -eq 'sa') {
                Write-Message -Level Verbose -Message "Skipping $newUserName."
                continue
            }

            if ($Login.LoginType -like 'Window*' -and $destServer.DatabaseEngineEdition -eq 'SqlManagedInstance' ) {
                Write-Message -Level Verbose -Message "$Login is a Windows login, not supported on a SQL Managed Instance"
                $copyLoginStatus.Status = "Skipped"
                $copyLoginStatus.Notes = "$($Login.name) is a Windows login, not supported on a SQL Managed Instance"
                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                continue
            }

            # Here we don't need the FullComputerName, but only the machine name to compare to the host part of the login name. So ComputerName should be fine.
            $serverName = $sourceServer.ComputerName

            $currentLogin = $DestServer.ConnectionContext.truelogin

            if ($currentLogin -eq $newUserName -and $force) {
                if ($Pscmdlet.ShouldProcess("console", "Stating $newUserName is skipped because it is performing the migration.")) {
                    Write-Message -Level Verbose -Message "Cannot drop login performing the migration. Skipping."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "Current login"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            if (($destServer.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($Login.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin)) {
                Write-Message -Level Verbose -Message "$Destination does not have Mixed Mode enabled. [$($Login.Name)] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login."
            }

            $userBase = ($Login.Name.Split("\")[0]).ToLowerInvariant()

            if ($serverName -eq $userBase -or $Login.Name.StartsWith("NT ")) {
                if ($sourceServer.ComputerName -ne $destServer.ComputerName) {
                    if ($Pscmdlet.ShouldProcess("console", "Stating $($Login.Name) was skipped because it is a local machine name.")) {
                        Write-Message -Level Verbose -Message "$($Login.Name) was skipped because it is a local machine name."
                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "Local machine name"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                } else {
                    if ($ExcludeSystemLogins) {
                        if ($Pscmdlet.ShouldProcess("console", "$($Login.Name) was skipped because ExcludeSystemLogins was specified.")) {
                            Write-Message -Level Verbose -Message "$($Login.Name) was skipped because ExcludeSystemLogins was specified."

                            $copyLoginStatus.Status = "Skipped"
                            $copyLoginStatus.Notes = "System login"
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess("console", "Stating local login $($Login.Name) since the source and destination server reside on the same machine.")) {
                        Write-Message -Level Verbose -Message "Copying local login $($Login.Name) since the source and destination server reside on the same machine."
                    }
                }
            }

            if ($null -ne $destServer.Logins.Item($newUserName) -and !$force) {
                if ($Pscmdlet.ShouldProcess("console", "Stating $newUserName is skipped because it exists at destination.")) {
                    Write-Message -Level Verbose -Message "$newUserName already exists in destination. Use -Force to drop and recreate."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "Already exists on destination"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            if ($null -ne $destServer.Logins.Item($newUserName) -and $force) {
                if ($newUserName -eq $destServer.ServiceAccount) {
                    if ($Pscmdlet.ShouldProcess("console", "$newUserName is the destination service account. Skipping drop.")) {
                        Write-Message -Level Verbose -Message "$newUserName is the destination service account. Skipping drop."

                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "Destination service account"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $newUserName")) {

                    # Kill connections, delete user
                    Write-Message -Level Verbose -Message "Attempting to migrate $newUserName"
                    Write-Message -Level Verbose -Message "Force was specified. Attempting to drop $newUserName on $destinstance."

                    try {
                        $ownedDbs = $destServer.Databases | Where-Object Owner -eq $newUserName

                        foreach ($ownedDb in $ownedDbs) {
                            Write-Message -Level Verbose -Message "Changing database owner for $($ownedDb.name) from $newUserName to sa."
                            $ownedDb.SetOwner('sa')
                            $ownedDb.Alter()
                        }

                        $ownedJobs = $destServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $newUserName

                        foreach ($ownedJob in $ownedJobs) {
                            Write-Message -Level Verbose -Message "Changing job owner for $($ownedJob.name) from $newUserName to sa."
                            $ownedJob.Set_OwnerLoginName('sa')
                            $ownedJob.Alter()
                        }

                        $activeConnections = $destServer.EnumProcesses() | Where-Object Login -eq $newUserName

                        if ($activeConnections -and $KillActiveConnection) {
                            if (!$destServer.Logins.Item($newUserName).IsDisabled) {
                                $disabled = $true
                                $destServer.Logins.Item($newUserName).Disable()
                            }

                            $activeConnections | ForEach-Object { $destServer.KillProcess($_.Spid) }
                            Write-Message -Level Verbose -Message "-KillActiveConnection was provided. There are $($activeConnections.Count) active connections killed."
                        } elseif ($activeConnections) {
                            Write-Message -Level Verbose -Message "There are $($activeConnections.Count) active connections found for the login $newUserName. Utilize -KillActiveConnection to kill the connections."
                        }
                        try {
                            $destServer.Logins.Item($newUserName).Drop()
                        } catch {
                            # just in case the kill didn't work, it'll leave behind a disabled account
                            if ($disabled) { $destServer.Logins.Item($newUserName).Enable() }
                            throw $_
                        }

                        Write-Message -Level Verbose -Message "Successfully dropped $newUserName on $destinstance."
                    } catch {
                        $copyLoginStatus.Status = "Failed"
                        $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Could not drop $newUserName." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue 3>$null
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destinstance, "Adding SQL login $newUserName")) {

                Write-Message -Level Verbose -Message "Attempting to add $newUserName to $destinstance."
                try {
                    $splatNewLogin = @{
                        SqlInstance          = $destServer
                        InputObject          = $Login
                        NewSid               = $NewSid
                        LoginRenameHashtable = $LoginRenameHashtable
                    }
                    if ($Login.DefaultDatabase -notin $destServer.Databases.Name) {
                        $copyLoginStatus.Notes = "Database $($Login.DefaultDatabase) does not exist on $destServer, switching DefaultDatabase to 'master' for $($Login.Name)"
                        Write-Message -Level Warning -Message $copyLoginStatus.Notes
                        $splatNewLogin.DefaultDatabase = 'master'
                    }
                    $destLogin = New-DbaLogin @splatNewLogin -EnableException:$true
                    $copyLoginStatus.Status = "Successful"
                } catch {
                    $copyLoginStatus.Status = "Failed"
                    $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Failed to add $newUserName to $destinstance." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue 3>$null
                }

                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                if (-not $ExcludePermissionSync) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Updating SQL login $newUserName permissions")) {
                        # In rare cases, when the instance has a case sensitive collation and there are two logins that differ only in case, New-DbaLogin will return them both into $destLogin
                        # So we loop, just in case...
                        foreach ($dl in $destLogin) {
                            Update-SqlPermission -SourceServer $sourceServer -SourceLogin $Login -DestServer $destServer -DestLogin $dl -ObjectLevel:$ObjectLevel
                        }
                    }
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $loginsCollection = @()
        if ($InputObject) {
            $loginsCollection += $InputObject
        } else {
            $loginsCollection += Get-DbaLogin -SqlInstance $Source -SqlCredential $SourceSqlCredential -Login $Login -EnableException:$EnableException
        }

        if ($OutFile) {
            return (Export-DbaLogin -SqlInstance $Source -SqlCredential $SourceSqlCredential -FilePath $OutFile -Login $loginsCollection -ObjectLevel:$ObjectLevel -ExcludeLogin $ExcludeLogin -EnableException:$EnableException)
        }
        foreach ($loginObject in $loginsCollection) {
            $sourceServer = $loginObject.Parent
            $sourceVersionMajor = $sourceServer.VersionMajor

            foreach ($destinstance in $Destination) {
                try {
                    $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -AzureUnsupported
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
                }

                $destVersionMajor = $destServer.VersionMajor
                if ($sourceVersionMajor -gt 10 -and $destVersionMajor -lt 11) {
                    Stop-Function -Message "Login migration from version $sourceVersionMajor to $destVersionMajor is not supported." -Target $sourceServer
                }

                if ($sourceVersionMajor -lt 8 -or $destVersionMajor -lt 8) {
                    Stop-Function -Message "SQL Server 7 and below are not supported." -Target $sourceServer
                }

                if ($destserver.ConnectionContext.TrueLogin -notin $destserver.Logins.Name -and $Force) {
                    if ($Login -or $ExcludeLogin -or $InputObject) {
                        Write-Message -Level Verbose -Message "Force was used and $($destserver.ConnectionContext.TrueLogin) not found in logins list but an explicit Login or ExcludeLogin was specified, so we trust you won't drop the group that allows $($destserver.ConnectionContext.TrueLogin) access. Proceeding."
                    } else {
                        Stop-Function -Message "Force was used, no explicit -Login or -ExcludeLogin was specified and $($destserver.ConnectionContext.TrueLogin) cannot be found in the logins list. It may be part of a group. This will likely result in you being locked out of the server. To use Force, $($destserver.ConnectionContext.TrueLogin) must be added directly to logins before proceeding." -Target $destserver
                        continue
                    }
                }

                Write-Message -Level Verbose -Message "Attempting Login Migration."
                Copy-Login -sourceserver $sourceServer -destserver $destServer -Login $loginObject -Exclude $ExcludeLogin

                if ($SyncSaName) {
                    $sa = $sourceServer.Logins | Where-Object id -eq 1
                    $destSa = $destServer.Logins | Where-Object id -eq 1
                    $saName = $sa.Name
                    if ($saName -ne $destSa.name) {
                        Write-Message -Level Verbose -Message "Changing sa username to match source ($saName)."
                        if ($Pscmdlet.ShouldProcess($destinstance, "Changing sa username to match source ($saName)")) {
                            $destSa.Rename($saName)
                            $destSa.Alter()
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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU+iYiczmxTqNBuPXPXT80bdtI
# CU+gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFLKWdTSt4TApPgVNRd3RKtZG5zruMA0G
# CSqGSIb3DQEBAQUABIIBAC/wXz1K6EA/G8bSC3qpJYLsbhK7OfQKeJK+QyHX4nnv
# 4xb4SwnGDGGsMlBQ3YmAhyIKu2oC4of2QnD8qkNfjHXpTkk8F5KWHFFzgvj+4yM9
# Di01ruVEQvC2bI3BgTW7dhr/RLfo4W8tvR7Bwwrc/csnJ83ddFggQC76o7q7wQv7
# uWkpDEdldT8KcVzs8m0GktLBxKupCzO3ZAc0SABq+oNdVg7zN7DsuZ73JUC9Wtxm
# Jt3D2SzJ1VzugLtBsjpyMpNxBZvVmeCTh9ktiSLsiLK6cns4k7YocPvTuvQfAhA8
# LBCaCdgdYLEpvXGWe2A4Q4N7PbXTgC7iIKl3M9nRO/ehggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzE0WjAvBgkqhkiG9w0BCQQxIgQgn4hEWSfzCAkfYEnH1Gts
# QrbCFnRhILi4Krb3h45sUNkwDQYJKoZIhvcNAQEBBQAEggIAgti7LkE20aIntL0V
# 0FtCLcd5lYj1XNb+fz9CIeCOoAnpvSELgh1lV5lU7nfciD1d8wW4uJpxK+2/Ww5B
# tNJ+NIMs3lorcJ6lDTYFUeqeYVEEBa4qC4FpQNuzQZoAbtpgtJAYPK7fkAmTsBP7
# qCb1UykBLQV0jZx5xoEr8JOtbshHn7raqjVBkb+ePwmaam0w2kvMo9Lzy1Z+cv+E
# 3sTxk13eVXJS4s/4h73o9f0v9SmiwumHSwMfmGEbM4Uak18lP86Rf4gWbhYRIf0j
# OEUucu2f2o7jeOhSEoaJVmzGeFgQ1h3Ft+TUEhp6z+gvySSZLHMWznE8FSrM28IT
# Sm4PPAY4i4/d8aCqanPXKNM4aP1OTbFfXiFqjW4a4yUMKKYzpP5ZKSvmallZ6y2I
# X3lNQdj/PcIqoP/4iDWwzwjc5Ire+qJ+UQTVSnJtFIeWLphEvqLw59hMl5JINhsd
# FTbuwR8lw979kCEFkZL+AKJexhSr6PONwu7mG/R/0p8SSvm5XYWmNBZAsGg/mZwW
# adg9ywxYB+yn63KGPLPXQnMWDEfDGtFcipON6bouZFc+XHJMyho6rF60J2DKWxhP
# iHAF0KwoiWr0HHeEYLxswZ/2PDmexJiDl0QQIKmPSlMbqTjGZNUJZpN4jdD+5S0u
# NCAsi9qdaLxK1U9vx2CV1Yr9KDQ=
# SIG # End signature block
