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
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAR8d48CB5sNq/v
# fXkYzMw4M/jMJpGD/a8u7hYxPn0NyaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAN9aVWkUv57FP0nm6wG0/kV/bXklGbAJBu
# J0SGIeU/ETANBgkqhkiG9w0BAQEFAASCAQBKjLrQO5dbc58RFloHeWPPcgbjvZIY
# 068rdhlV6KbPKpa4TkOE4iYfrKAC6/WaoMpZ98RAEud4oJVzcXzGJOWHM0Sxqss6
# R7U3bM93z+eUVNs34DHLD0AbUZXw8y6TQ2f0r2w6ZXQm78LjdjVRRkP613sJYWjS
# sSIHKXb7elF7A34fDpBwx1vHndBow3DnnxUyGbBOkQpXcLdujadFr9GySGD/icmn
# tR+wQ4+zc9Z84WZ1lq1nfvFENbcdGF0G1yBHwji+4yEYIXHtlb6DXGHkViWQF9CT
# KuR7W+028NJVjGYtNHJsg6F3I9m7dcrToUW164jjGcECEJyQDDlpZO/4oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDIzOFowLwYJKoZIhvcNAQkEMSIEILmC881N
# Sh4vvd5qgKlJbASeFl34jPE2a5BNr4HQBco6MA0GCSqGSIb3DQEBAQUABIICAG+0
# owBdTkDwVa2m5mAkaFiq8CMmb9p2jb0KLTjkfGzaoqiEDgK9f+J6hb20bpPSkGn5
# PuJbYl3bUj3KN4d0IFflYFW9QVcIhEbyGvHLsW9UWtooXf5wBb6ZUlYy6GoQOzCo
# 3Oq95GwgJ9J/MK5MBLptKulO0rJ2zJmiJrCmP4GaWJMw3pjl3EczI3kf2XP5+JGP
# lBxSo7Z/J84+4GVndiKxvO+CC7AXtvhGWs0CEDV/bEpW/W4LmboqqwpAcaT97AHr
# nEOBFxZyd35lqU28kJ3gnUVqzwzz+x1IUCMCyCwRDN3Kpfmlrz2lutKmK6gmRZ20
# nW5QUa8vmAXc6JeHi9wWJvlbfT3yO7TNSub6OpBNi8MVWkK/6cSRa/83LelOXY2T
# cuEShBZ7r33nxSHXCltPjcn9JtjFkuqSqgte5jz1oKDjvPyTCthUahQJxqHPXeSM
# NOhdES0cuCrOAN+OTPGoIKG6p2NrAOPb9vv1A+DsZXHFX5/EeZX8g2mNv2WQr+/D
# dPyS4YUPQIneFzK8t8bDlIgJ3UeHDmKr9e1U8E16gmlFd7cOtHUNDSt9B9LAorbR
# EoBLLNmlHN3Mo29X36PFzNGuEndOtMD9kSDWuYemY+oHICCWQ7FUEpt2mvPhqNK2
# yAtVjl+2y3aX2/NcPGmaXX2mgGLu3uUjk/eJnzxM
# SIG # End signature block
