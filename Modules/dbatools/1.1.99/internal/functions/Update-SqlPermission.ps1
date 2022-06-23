function Update-SqlPermission {
    <#
        .SYNOPSIS
            Internal function. Updates permission sets, roles, database mappings on server and databases
        .PARAMETER SourceServer
            Source Server
        .PARAMETER SourceLogin
            Source login
        .PARAMETER DestServer
            Destination Server
        .PARAMETER DestLogin
            Destination Login
        .PARAMETER ObjectLevel
            Use Export-DbaUser to update object-level permissions as well
        .PARAMETER EnableException
            Use this switch to disable any kind of verbose messages
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SourceServer,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SourceLogin,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$DestServer,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$DestLogin,
        [switch]$ObjectLevel,
        [switch]$EnableException
    )

    $destination = $DestServer.DomainInstanceName
    $source = $SourceServer.DomainInstanceName
    $loginName = $SourceLogin.Name
    $newLoginName = $DestLogin.Name

    $saname = Get-SaLoginName -SqlInstance $DestServer

    # gotta close because enum repeatedly causes problems with the datareader
    $null = $SourceServer.ConnectionContext.SqlConnectionObject.Close()
    $null = $DestServer.ConnectionContext.SqlConnectionObject.Close()

    # Server Roles: sysadmin, bulklogin, etc
    foreach ($role in $SourceServer.Roles) {
        $roleName = $role.Name
        $destRole = $DestServer.Roles[$roleName]

        if ($null -ne $destRole) {
            try {
                $destRoleMembers = $destRole.EnumMemberNames()
            } catch {
                $destRoleMembers = $destRole.EnumServerRoleMembers()
            }
        }

        try {
            $roleMembers = $role.EnumMemberNames()
        } catch {
            $roleMembers = $role.EnumServerRoleMembers()
        }

        if ($roleMembers -contains $loginName) {
            if ($null -ne $destRole) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $newLoginName to $roleName server role.")) {
                    if ($loginName -ne $saname) {
                        try {
                            $destRole.AddMember($newLoginName)
                            Write-Message -Level Verbose -Message "Adding $newLoginName to $roleName server role on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to add $newLoginName to $roleName server role on $destination." -Target $role -ErrorRecord $_
                        }
                    }
                }
            }
        }

        # Remove for Syncs
        if ($roleMembers -notcontains $loginName -and $destRoleMembers -contains $newLoginName -and $null -ne $destRole) {
            if ($Pscmdlet.ShouldProcess($destination, "Adding $loginName to $roleName server role.")) {
                try {
                    $destRole.DropMember($loginName)
                    Write-Message -Level Verbose -Message "Removing $newLoginName from $destRoleName server role on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to remove $newLoginName from $destRoleName server role on $destination." -Target $role -ErrorRecord $_
                }
            }
        }
    }

    $ownedJobs = $SourceServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $loginName
    foreach ($ownedJob in $ownedJobs) {
        if ($null -ne $DestServer.JobServer.Jobs[$ownedJob.Name]) {
            if ($Pscmdlet.ShouldProcess($destination, "Changing of job owner to $newLoginName for $($ownedJob.Name).")) {
                try {
                    $destOwnedJob = $DestServer.JobServer.Jobs | Where-Object { $_.Name -eq $ownedJob.Name }
                    $destOwnedJob.Set_OwnerLoginName($newLoginName)
                    $destOwnedJob.Alter()
                    Write-Message -Level Verbose -Message "Changing job owner to $newLoginName for $($ownedJob.Name) on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to change job owner for $($ownedJob.Name) to $newLoginName on $destination." -Target $ownedJob -ErrorRecord $_
                }
            }
        }
    }

    if ($SourceServer.VersionMajor -ge 9 -and $DestServer.VersionMajor -ge 9) {
        <#
            These operations are only supported by SQL Server 2005 and above.
            Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
        #>

        $null = $sourceServer.ConnectionContext.SqlConnectionObject.Close()
        $null = $destServer.ConnectionContext.SqlConnectionObject.Close()

        $perms = $SourceServer.EnumServerPermissions($loginName)
        foreach ($perm in $perms) {
            $permState = $perm.PermissionState
            if ($permState -eq "GrantWithGrant") {
                $grantWithGrant = $true;
                $permState = "grant"
            } else {
                $grantWithGrant = $false
            }

            $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)
            if ($Pscmdlet.ShouldProcess($destination, "$permState on $($perm.PermissionType) for $newLoginName.")) {
                try {
                    $DestServer.PSObject.Methods[$permState].Invoke($permSet, $newLoginName, $grantWithGrant)
                    Write-Message -Level Verbose -Message "$permState $($perm.PermissionType) to $newLoginName on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to $permState $($perm.PermissionType) to $newLoginName on $destination." -Target $perm -ErrorRecord $_
                }
            }

            # for Syncs
            $destPerms = $DestServer.EnumServerPermissions($newLoginName)
            foreach ($perm in $destPerms) {
                $permState = $perm.PermissionState
                $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }

                if ($null -eq $sourcePerm) {
                    if ($Pscmdlet.ShouldProcess($destination, "Revoking $($perm.PermissionType) for $newLoginName.")) {
                        try {
                            $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)

                            if ($permState -eq "GrantWithGrant") {
                                $grantWithGrant = $true;
                                $permState = "grant"
                            } else {
                                $grantWithGrant = $false
                            }

                            $DestServer.PSObject.Methods["Revoke"].Invoke($permSet, $newLoginName, $false, $grantWithGrant)
                            Write-Message -Level Verbose -Message "Revoking $($perm.PermissionType) for $newLoginName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $newLoginName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
                }
            }
        }

        # Credential mapping. Credential removal not currently supported for Syncs.
        $loginCredentials = $SourceServer.Credentials | Where-Object { $_.Identity -eq $SourceLogin.Name }
        foreach ($credential in $loginCredentials) {
            if ($null -eq $DestServer.Credentials[$credential.Name]) {
                if ($Pscmdlet.ShouldProcess($destination, "Creating credential $($credential.Name) for $newLoginName.")) {
                    try {
                        $newCred = New-Object Microsoft.SqlServer.Management.Smo.Credential($DestServer, $credential.Name)
                        $newCred.Identity = $newLoginName
                        $newCred.Create()
                        Write-Message -Level Verbose -Message "Creating credential $($credential.Name) for $newLoginName on $destination successfully performed."
                    } catch {
                        Stop-Function -Message "Failed to create credential $($credential.Name) for $newLoginName on $destination." -Target $credential -ErrorRecord $_
                    }
                }
            }
        }
    }

    if ($DestServer.VersionMajor -lt 9) {
        Write-Message -Level Warning -Message "SQL Server 2005 or greater required for database mappings.";
        continue
    }

    # For Sync, if info doesn't exist in EnumDatabaseMappings, then no big deal.
    foreach ($db in $DestLogin.EnumDatabaseMappings()) {
        $dbName = $db.DbName
        $destDb = $DestServer.Databases[$dbName]
        $sourceDb = $SourceServer.Databases[$dbName]
        $newDbUsername = $db.Username;
        # Adjust renamed database usernames for old server
        if ($newDbUsername -eq $newLoginName) { $dbUsername = $loginName } else { $dbUsername = $newDbUsername }
        $dbLogin = $db.LoginName

        if ($null -ne $sourceDb) {
            if (-not $sourceDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$($sourceDb.Name)] is not accessible on $source. Skipping."
                continue
            }
            if (-not $destDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$($sourceDb.Name)] is not accessible on destination. Skipping."
                continue
            }
            if ((Get-DbaAgDatabase -SqlInstance $DestServer -Database $dbName -ErrorAction Ignore -WarningAction SilentlyContinue)) {
                Write-Message -Level Verbose -Message "Database [$dbName] is part of an availability group. Skipping."
                continue
            }
            if ($null -eq $sourceDb.Users[$dbUsername] -and $null -eq $destDb.Users[$newDbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Dropping user $dbUsername from $dbName.")) {
                    try {
                        $destDb.Users[$newDbUsername].Drop()
                        Write-Message -Level Verbose -Message "Dropping user $newDbUsername (login: $dbLogin) from $dbName on destination successfully performed."
                        Write-Message -Level Verbose -Message "Any schema in $dbaName owned by $newDbUsername may still exist."
                    } catch {
                        Stop-Function -Message "Failed to drop $newDbUsername (login: $dbLogin) from $dbName on destination." -Target $db -ErrorRecord $_
                    }
                }
            }

            # Remove user from role. Role removal not currently supported for Syncs.
            # TODO: reassign if dbo, application roles
            foreach ($destRole in $destDb.Roles) {
                $destRoleName = $destRole.Name
                $sourceRole = $sourceDb.Roles[$destRoleName]
                if ($null -eq $sourceRole) {
                    if ($destRole.EnumMembers() -contains $newDbUsername) {
                        if ($newDbUsername -ne "dbo") {
                            if ($Pscmdlet.ShouldProcess($destination, "Dropping user $newDbUsername from $destRoleName database role in $dbName.")) {
                                try {
                                    $destRole.DropMember($newDbUsername)
                                    $destDb.Alter()
                                    Write-Message -Level Verbose -Message "Dropping user $newDbUsername (login: $dbLogin) from $destRoleName database role in $dbName on $destination successfully performed."
                                } catch {
                                    Stop-Function -Message "Failed to remove $newDbUsername (login: $dbLogin) from $destRoleName database role in $dbName on $destination." -Target $destRole -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
            }

            $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
            $null = $destDb.Parent.ConnectionContext.SqlConnectionObject.Close()
            # Remove Connect, Alter Any Assembly, etc
            $destPerms = $destDb.EnumDatabasePermissions($newLoginName)
            $perms = $sourceDb.EnumDatabasePermissions($loginName)
            # for Syncs
            foreach ($perm in $destPerms) {
                $permState = $perm.PermissionState
                $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }
                if ($null -eq $sourcePerm) {
                    if ($Pscmdlet.ShouldProcess($destination, "Revoking $($perm.PermissionType) from $newLoginName in $dbName.")) {
                        try {
                            $permSet = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.PermissionType)

                            if ($permState -eq "GrantWithGrant") {
                                $grantWithGrant = $true;
                                $permState = "grant"
                            } else {
                                $grantWithGrant = $false
                            }

                            $destDb.PSObject.Methods["Revoke"].Invoke($permSet, $newLoginName, $false, $grantWithGrant)
                            Write-Message -Level Verbose -Message "Revoking $($perm.PermissionType) from $newLoginName in $dbName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $newLoginName in $dbName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
                }
            }
        }
    }

    # Adding database mappings and securables
    $null = $SourceLogin.Parent.ConnectionContext.SqlConnectionObject.Close()
    $null = $DestServer.ConnectionContext.SqlConnectionObject.Close()

    foreach ($db in $SourceLogin.EnumDatabaseMappings()) {
        $dbName = $db.DbName
        $destDb = $DestServer.Databases[$dbName]
        $sourceDb = $SourceServer.Databases[$dbName]
        $dbUsername = $db.Username;
        # Adjust renamed database usernames for new server
        if ($newLoginName -eq $loginName) { $newDbUsername = $dbUsername } else { $newDbUsername = $newLoginName }

        if ($null -ne $destDb) {
            if (-not $destDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$dbName] is not accessible. Skipping."
                continue
            }

            if ((Get-DbaAgDatabase -SqlInstance $DestServer -Database $dbName -ErrorAction Ignore -WarningAction SilentlyContinue)) {
                Write-Message -Level Verbose -Message "Database [$dbName] is part of an availability group. Skipping."
                continue
            }
            if ($null -eq $destDb.Users[$newDbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $newDbUsername to $dbName.")) {
                    $sql = $SourceServer.Databases[$dbName].Users[$dbUsername].Script() | Out-String
                    try {
                        $destDb.ExecuteNonQuery($sql.Replace("[$dbUsername]", "[$newDbUsername]"))
                        Write-Message -Level Verbose -Message "Adding user $newDbUsername (login: $newLoginName) to $dbName successfully performed."
                    } catch {
                        Stop-Function -Message "Failed to add $newDbUsername (login: $newLoginName) to $dbName on $destination." -Target $db -ErrorRecord $_
                    }
                }
            }

            # Db owner
            if ($sourceDb.Owner -eq $loginName) {
                if ($Pscmdlet.ShouldProcess($destination, "Changing $dbName dbowner to $newLoginName.")) {
                    try {
                        if ($dbName -notin 'master', 'msdb', 'tempdb', 'model') {
                            $result = Set-DbaDbOwner -SqlInstance $DestServer -Database $dbName -TargetLogin $newLoginName -EnableException:$EnableException
                            if ($result.Owner -eq $newLoginName) {
                                Write-Message -Level Verbose -Message "Changed $($destDb.Name) owner to $newLoginName."
                            } else {
                                Write-Message -Level Warning -Message "Failed to update $($destDb.Name) owner to $newLoginName."
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to update $($destDb.Name) owner to $newLoginName." -ErrorRecord $_
                    }
                }
            }

            if ($ObjectLevel) {
                if ($dbUsername -ne "dbo") {
                    $scriptOptions = New-DbaScriptingOption
                    $scriptVersion = $destDb.CompatibilityLevel
                    $scriptOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                    $scriptOptions.AllowSystemObjects = $false
                    $scriptOptions.IncludeDatabaseRoleMemberships = $true
                    $scriptOptions.ContinueScriptingOnError = $false
                    $scriptOptions.IncludeDatabaseContext = $false
                    $scriptOptions.IncludeIfNotExists = $true
                    $userScript = Export-DbaUser -SqlInstance $SourceServer -Database $dbName -User $dbUsername -Passthru -Template -ScriptingOptionsObject $scriptOptions -EnableException:$EnableException
                    $userScript = $userScript.Replace('{templateUser}', $newDbUsername)
                    $destDb.ExecuteNonQuery($userScript)
                }
            } else {
                # Database Roles: db_owner, db_datareader, etc
                foreach ($role in $sourceDb.Roles) {
                    $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
                    $null = $destDb.Parent.ConnectionContext.SqlConnectionObject.Close()
                    if ($role.EnumMembers() -contains $loginName) {
                        $roleName = $role.Name
                        $destDbRole = $destDb.Roles[$roleName]

                        if ($null -ne $destDbRole -and $dbUsername -ne "dbo" -and $destDbRole.EnumMembers() -notcontains $newDbUsername) {
                            if ($Pscmdlet.ShouldProcess($destination, "Adding $newDbUsername to $roleName database role in $dbName.")) {
                                try {
                                    $destDbRole.AddMember($newDbUsername)
                                    $destDb.Alter()
                                    Write-Message -Level Verbose -Message "Adding $newDbUsername to $roleName database role in $dbName on $destination successfully performed."
                                } catch {
                                    Stop-Function -Message "Failed to add $newDbUsername to $roleName database role in $dbName on $destination." -Target $role -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
                # Connect, Alter Any Assembly, etc
                $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
                $perms = $sourceDb.EnumDatabasePermissions($loginName)
                foreach ($perm in $perms) {
                    $permState = $perm.PermissionState
                    if ($permState -eq "GrantWithGrant") {
                        $grantWithGrant = $true;
                        $permState = "grant"
                    } else {
                        $grantWithGrant = $false
                    }
                    $permSet = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.PermissionType)

                    if ($Pscmdlet.ShouldProcess($destination, "$permState on $($perm.PermissionType) for $newDbUsername on $dbName")) {
                        try {
                            $destDb.PSObject.Methods[$permState].Invoke($permSet, $newDbUsername, $grantWithGrant)
                            Write-Message -Level Verbose -Message "$permState on $($perm.PermissionType) to $newDbUsername on $dbName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to perform $permState on $($perm.PermissionType) to $newDbUsername on $dbName on $destination." -Target $perm -ErrorRecord $_
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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQULTrLZ+Z0MKsAglR0wsshJIQl
# +WegghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPBViTgeau9unpxRRMZ4zAaF6MkxMA0G
# CSqGSIb3DQEBAQUABIIBAI5yFk81t51x36bNNFFMn9GjMuV229xHVaobu+9SKHPC
# +658ucmVjqbNSijNNvir5EfOnPBJmMLhTDXu8p+wdFhUE8ybXLlZys20goOUEBSK
# Wfc9FTvqjobAPYXYxqZxRSuNitzNNzM/sRkZkc36+sQcGquLrsrt/qc0ArxMw/Qa
# Dwa29FsCFOcmzOwar1GPfthX3uIfOL+52nLQgPU2fGKK4tsOujKNEhgkxhqN/4XC
# LBe6i42q089E+FS69YaycfTLPtjxSDxdKFCtapre8fe7OVyXnrFmHM1Wc4/T4F3c
# irqkKua3y4jfN14h3hYS60lpS3jCd+QJw7fGoZxBPDGhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDU4WjAvBgkqhkiG9w0BCQQxIgQgp71DfRoN8C6BZWZjEpvC
# OUQz/+9BijnjseV+r4o6O4MwDQYJKoZIhvcNAQEBBQAEggIArtKBT3YEMDBBb+LZ
# m0YbUDBqf06dgX8BJu+2udkvifgdiqUGLdmOYkN52LTMqCadIPghCA8C23P7MPLz
# Wl8kmU+uc3s+MPKz//Z+FPN2LBbHR9ZoWKZkqCB7m7FGZ+QntJzrmboz1grV58iC
# Ko97Cjggjr8hX+DjlhzKylvxUbP+iEIDorbCG4ocBNpizK0LD/oBMcWPm7P4zSCF
# UfMRkZuj8Uweo2nSziTChDaig1VM+gb2ppY3SArBEPcJKEif2WuCQVKynwSvAVIY
# VkKCMfbviWON7aR0FUl/lm9Omjuhq9R25T85/9RVX1nQG/hdoy6Qq/hf61KpQJM7
# QnSaXiENZ97sy23MJxZLFAlSc913P1uAGU21p+5qkx2Jx9hYAoVW0QgIEcQMLyil
# fcxSduXm84/6873EFeHX5bwh2WfW4fc6tvXg+TTyCZ0n92+iRV6GbbyO6l1cEdgR
# RdWsfNpdkncqy+1wjW8Pibattt4o2+wy1t2sbHuBmVl5BMdU/85+adsQBEokSVQv
# 5dpqgZA4YBEj4uVfLcUaKRWzYyXMFv37KxRI2MlsWeFOPmAqn7d5FKj+tDeLVljh
# fxaxdtNFq2M1gWO1Io3SU2G6KSOOj9Ons+oymunCwANdm9OyDLm3sT/BScdbstG4
# bgr8IVfzyuZ1bGZyOHZInAL3m+Y=
# SIG # End signature block
