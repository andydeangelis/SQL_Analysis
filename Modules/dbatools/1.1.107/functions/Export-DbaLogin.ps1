function Export-DbaLogin {
    <#
    .SYNOPSIS
        Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

    .DESCRIPTION
        Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2000 and above supported.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase, Get-DbaLogin and more.

    .PARAMETER Login
        The login(s) to process. Options for this list are auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        The login(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeJobs
        If this switch is enabled, Agent job ownership will not be exported.

    .PARAMETER ExcludeDatabase
        If this switch is enabled, mappings for databases will not be exported.

    .PARAMETER ExcludePassword
        If this switch is enabled, hashed passwords will not be exported.

   .PARAMETER DefaultDatabase
        If this switch is enabled, all logins will be scripted with specified default database,
        that could help to successfully import logins on server that is missing default database for login.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.
        Will default to Path.DbatoolsExport Configuration entry

    .PARAMETER FilePath
        Specifies the full file path of the output file. If left blank then filename based on Instance name and date is created.
        If more than one instance is input then this parameter should be blank.

    .PARAMETER Passthru
        Output script to console

    .PARAMETER BatchSeparator
        Batch separator for scripting output. Uses the value from configuration Formatting.BatchSeparator by default. This is normally "GO"

    .PARAMETER NoClobber
        If this switch is enabled, a file already existing at the path specified by Path will not be overwritten.

    .PARAMETER Append
        If this switch is enabled, content will be appended to a file already existing at the path specified by Path. If the file does not exist, it will be created.

    .PARAMETER DestinationVersion
        To say to which version the script should be generated. If not specified will use instance major version.

    .PARAMETER NoPrefix
        Do not include a Prefix

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER ObjectLevel
        Include object-level permissions for each user associated with copied login.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Export, Login
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaLogin

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sql2005 -Path C:\temp\sql2005-logins.sql

        Exports the logins for SQL Server "sql2005" and writes them to the file "C:\temp\sql2005-logins.sql"

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2014a -ExcludeLogin realcajun -SqlCredential $scred -Path C:\temp\logins.sql -Append

        Authenticates to sqlserver2014a using SQL Authentication. Exports all logins except for realcajun to C:\temp\logins.sql, and appends to the file if it exists. If not, the file will be created.

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2014a -Login realcajun, netnerds -Path C:\temp\logins.sql

        Exports ONLY logins netnerds and realcajun FROM sqlserver2014a to the file  C:\temp\logins.sql

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2014a -Login realcajun, netnerds -Database HR, Accounting

        Exports ONLY logins netnerds and realcajun FROM sqlserver2014a with the permissions on databases HR and Accounting

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2014a -Database HR, Accounting | Export-DbaLogin

        Exports ONLY logins FROM sqlserver2014a with permissions on databases HR and Accounting

    .EXAMPLE
        PS C:\> Set-DbatoolsConfig -FullName formatting.batchseparator -Value $null
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2008 -Login realcajun, netnerds -Path C:\temp\login.sql

        Exports ONLY logins netnerds and realcajun FROM sqlserver2008 server, to the C:\temp\login.sql file without the 'GO' batch separator.

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2008 -Login realcajun -Path C:\temp\users.sql -DestinationVersion SQLServer2016

        Exports login realcajun from sqlserver2008 to the file C:\temp\users.sql with syntax to run on SQL Server 2016

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2008 -Login realcajun | Export-DbaLogin

        Exports login realcajun from sqlserver2008

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sqlserver2008, sqlserver2012  | Where-Object { $_.IsDisabled -eq $false } | Export-DbaLogin

        Exports all enabled logins from sqlserver2008 and sqlserver2008

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter()]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [object[]]$Login,
        [object[]]$ExcludeLogin,
        [object[]]$Database,
        [switch]$ExcludeJobs,
        [Alias("ExcludeDatabases")]
        [switch]$ExcludeDatabase,
        [switch]$ExcludePassword,
        [string]$DefaultDatabase,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [Alias("NoOverwrite")]
        [switch]$NoClobber,
        [switch]$Append,
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator'),
        [ValidateSet('SQLServer2000', 'SQLServer2005', 'SQLServer2008/2008R2', 'SQLServer2012', 'SQLServer2014', 'SQLServer2016', 'SQLServer2017', 'SQLServer2019')]
        [string]$DestinationVersion,
        [switch]$NoPrefix,
        [switch]$Passthru,
        [switch]$ObjectLevel,
        [switch]$EnableException
    )

    begin {
        $null = Test-ExportDirectory -Path $Path
        $outsql = @()
        $instanceArray = @()
        $logonCollection = New-Object System.Collections.ArrayList
        if ($IsLinux -or $IsMacOs) {
            $executingUser = $env:USER
        } else {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $commandName = $MyInvocation.MyCommand.Name

        $eol = [System.Environment]::NewLine
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a login, database, or server or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    try {
                        $server = Connect-DbaInstance -SqlInstance $input -SqlCredential $SqlCredential
                    } catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $input -Continue
                    }
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $server = Connect-DbaInstance -SqlInstance $input -SqlCredential $SqlCredential
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $server = $input.Parent
                    $Database = $input
                }
                'Microsoft.SqlServer.Management.Smo.Login' {
                    Write-Message -Level Verbose -Message "Processing Login through InputObject"
                    $server = $input.Parent
                    $Login = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or login."
                    return
                }
            }

            if ($ExcludeDatabase -eq $false -or $Database) {
                # if we got a database or a list of databases passed
                # and we need to enumerate mappings, login.enumdatabasemappings() takes forever
                # the cool thing though is that database.enumloginmappings() is fast. A lot.
                # if we get a list of databases passed (or even the default list of all the databases)
                # we save ourself a call to enumloginmappings if there is no map at all
                $DbMapping = @()
                $DbsToMap = $server.Databases
                if ($Database) {
                    if ($Database[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Database') {
                        $DbsToMap = $DbsToMap | Where-Object Name -in $Database.Name
                    } else {
                        $DbsToMap = $DbsToMap | Where-Object Name -in $Database
                    }
                }
                foreach ($db in $DbsToMap) {
                    if ($db.IsAccessible -eq $false) {
                        continue
                    }
                    $dbmap = $db.EnumLoginMappings()
                    foreach ($el in $dbmap) {
                        $DbMapping += [pscustomobject]@{
                            Database  = $db.Name
                            UserName  = $el.Username
                            LoginName = $el.LoginName
                        }
                    }
                }
            }

            $serverLogins = $server.Logins

            if ($Login) {
                if ($Login[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Login') {
                    $serverLogins = $serverLogins | Where-Object { $_.Name -in $Login.Name }
                } else {
                    $serverLogins = $serverLogins | Where-Object { $_.Name -in $Login }
                }
            }

            foreach ($sourceLogin in $serverLogins) {
                Write-Message -Level Verbose -Message "Processing login $sourceLogin"
                $userName = $sourceLogin.name

                if ($ExcludeLogin -contains $userName) {
                    Write-Message -Level Warning -Message "Skipping $userName"
                    continue
                }

                if ($userName.StartsWith("##") -or $userName -eq 'sa') {
                    Write-Message -Level Warning -Message "Skipping $userName"
                    continue
                }

                $serverName = $server

                $userBase = ($userName.Split("\")[0]).ToLowerInvariant()
                if ($serverName -eq $userBase -or $userName.StartsWith("NT ")) {
                    if ($Pscmdlet.ShouldProcess("console", "Stating $userName is skipped because it is a local machine name")) {
                        Write-Message -Level Warning -Message "$userName is skipped because it is a local machine name"
                        continue
                    }
                }

                if ($Pscmdlet.ShouldProcess("Outfile", "Adding T-SQL for login $userName")) {
                    if ($Path -or $FilePath) {
                        Write-Message -Level Verbose -Message "Exporting $userName"
                    }

                    $outsql += "$($eol)USE master$eol"
                    # Getting some attributes
                    if ($DefaultDatabase) {
                        $defaultDb = $DefaultDatabase
                    } else {
                        $defaultDb = $sourceLogin.DefaultDatabase
                    }
                    $language = $sourceLogin.Language

                    if ($sourceLogin.PasswordPolicyEnforced -eq $false) {
                        $checkPolicy = "OFF"
                    } else {
                        $checkPolicy = "ON"
                    }

                    if (!$sourceLogin.PasswordExpirationEnabled) {
                        $checkExpiration = "OFF"
                    } else {
                        $checkExpiration = "ON"
                    }

                    # Attempt to script out SQL Login
                    if ($sourceLogin.LoginType -eq "SqlLogin") {
                        if (!$ExcludePassword) {
                            $sourceLoginName = $sourceLogin.name

                            switch ($server.versionMajor) {
                                0 {
                                    $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceLoginName'"
                                }
                                8 {
                                    $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM dbo.syslogins WHERE name='$sourceLoginName'"
                                }
                                9 {
                                    $sql = "SELECT CONVERT(VARBINARY(256),password_hash) as hashedpass FROM sys.sql_logins WHERE name='$sourceLoginName'"
                                }
                                default {
                                    $sql = "SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name,'PasswordHash') AS VARBINARY(256)), 1) AS NVARCHAR(max)) AS hashedpass FROM sys.server_principals WHERE principal_id = $($sourceLogin.id)"
                                }
                            }

                            try {
                                $hashedPass = $server.ConnectionContext.ExecuteScalar($sql)
                            } catch {
                                $hashedPassDt = $server.Databases['master'].ExecuteWithResults($sql)
                                $hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
                            }

                            if ($hashedPass.GetType().Name -ne "String") {
                                $passString = "0x"; $hashedPass | ForEach-Object {
                                    $passString += ("{0:X}" -f $_).PadLeft(2, "0")
                                }
                                $hashedPass = $passString
                            }
                        } else {
                            $hashedPass = '#######'
                        }

                        $sid = "0x"; $sourceLogin.sid | ForEach-Object {
                            $sid += ("{0:X}" -f $_).PadLeft(2, "0")
                        }
                        $outsql += "IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = '$userName') CREATE LOGIN [$userName] WITH PASSWORD = $hashedPass HASHED, SID = $sid, DEFAULT_DATABASE = [$defaultDb], CHECK_POLICY = $checkPolicy, CHECK_EXPIRATION = $checkExpiration, DEFAULT_LANGUAGE = [$language]"
                    }
                    # Attempt to script out Windows User
                    elseif ($sourceLogin.LoginType -eq "WindowsUser" -or $sourceLogin.LoginType -eq "WindowsGroup") {
                        $outsql += "IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = '$userName') CREATE LOGIN [$userName] FROM WINDOWS WITH DEFAULT_DATABASE = [$defaultDb], DEFAULT_LANGUAGE = [$language]"
                    }
                    # This script does not currently support certificate mapped or asymmetric key users.
                    else {
                        Write-Message -Level Warning -Message "$($sourceLogin.LoginType) logins not supported. $($sourceLogin.Name) skipped"
                        continue
                    }

                    if ($sourceLogin.IsDisabled) {
                        $outsql += "ALTER LOGIN [$userName] DISABLE"
                    }

                    if ($sourceLogin.DenyWindowsLogin) {
                        $outsql += "DENY CONNECT SQL TO [$userName]"
                    }
                }

                # Server Roles: sysadmin, bulklogin, etc
                foreach ($role in $server.Roles) {
                    $roleName = $role.Name

                    # SMO changed over time
                    try {
                        $roleMembers = $role.EnumMemberNames()
                    } catch {
                        $roleMembers = $role.EnumServerRoleMembers()
                    }

                    if ($roleMembers -contains $userName) {
                        if (($server.VersionMajor -lt 11 -and [string]::IsNullOrEmpty($destinationVersion)) -or ($DestinationVersion -in "SQLServer2000", "SQLServer2005", "SQLServer2008/2008R2")) {
                            $outsql += "EXEC sys.sp_addsrvrolemember @rolename=N'$roleName', @loginame=N'$userName'"
                        } else {
                            $outsql += "ALTER SERVER ROLE [$roleName] ADD MEMBER [$userName]"
                        }
                    }
                }

                if ($ExcludeJobs -eq $false) {
                    $ownedJobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -eq $userName }

                    foreach ($ownedJob in $ownedJobs) {
                        $ownedJob = $ownedJob -replace ("'", "''")
                        $outsql += "$($eol)USE msdb$eol"
                        $outsql += "EXEC msdb.dbo.sp_update_job @job_name=N'$ownedJob', @owner_login_name=N'$userName'"
                    }
                }

                if ($server.VersionMajor -ge 9) {
                    # These operations are only supported by SQL Server 2005 and above.
                    # Securables: Connect SQL, View any database, Administer Bulk Operations, etc.

                    $perms = $server.EnumServerPermissions($userName)
                    $outsql += "$($eol)USE master$eol"
                    foreach ($perm in $perms) {
                        $permState = $perm.permissionstate
                        $permType = $perm.PermissionType
                        $grantor = $perm.grantor

                        if ($permState -eq "GrantWithGrant") {
                            $grantWithGrant = "WITH GRANT OPTION"
                            $permState = "GRANT"
                        } else {
                            $grantWithGrant = $null
                        }

                        $outsql += "$permState $permType TO [$userName] $grantWithGrant AS [$grantor]"
                    }

                    # Credential mapping. Credential removal not currently supported for Syncs.
                    $loginCredentials = $server.Credentials | Where-Object { $_.Identity -eq $sourceLogin.Name }
                    foreach ($credential in $loginCredentials) {
                        $credentialName = $credential.Name
                        $outsql += "PRINT '$userName is associated with the $credentialName credential'"
                    }
                }

                if ($ExcludeDatabase -eq $false) {
                    $dbs = $sourceLogin.EnumDatabaseMappings() | Sort-Object DBName

                    if ($Database) {
                        if ($Database[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Database') {
                            $dbs = $dbs | Where-Object { $_.DBName -in $Database.Name }
                        } else {
                            $dbs = $dbs | Where-Object { $_.DBName -in $Database }
                        }
                    }

                    # Adding database mappings and securables
                    foreach ($db in $dbs) {
                        $dbName = $db.dbname
                        $sourceDb = $server.Databases[$dbName]
                        $dbUserName = $db.username

                        $outsql += "$($eol)USE [$dbName]$eol"

                        $scriptOptions = New-DbaScriptingOption
                        $scriptVersion = $sourceDb.CompatibilityLevel
                        $scriptOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                        $scriptOptions.ContinueScriptingOnError = $false
                        $scriptOptions.IncludeDatabaseContext = $false
                        $scriptOptions.IncludeIfNotExists = $true

                        if ($ObjectLevel) {
                            # Exporting all permissions
                            $scriptOptions.AllowSystemObjects = $true
                            $scriptOptions.IncludeDatabaseRoleMemberships = $true

                            $exportSplat = @{
                                SqlInstance            = $server
                                Database               = $dbName
                                User                   = $dbUsername
                                ScriptingOptionsObject = $scriptOptions
                            }
                            # remove batch separator if the $BatchSeparator string is empty
                            if (-Not $BatchSeparator) {
                                $scriptOptions.NoCommandTerminator = $true
                                $exportSplat.ExcludeGoBatchSeparator = $true
                            }
                            try {
                                $userScript = Export-DbaUser @exportSplat -Passthru -EnableException
                                $outsql += $userScript
                            } catch {
                                Stop-Function -Message "Failed to extract permissions for user $dbUserName in database $dbName" -Continue -ErrorRecord $_
                            }
                        } else {
                            try {
                                $sql = $server.Databases[$dbName].Users[$dbUserName].Script($scriptOptions)
                                $outsql += $sql
                            } catch {
                                Write-Message -Level Warning -Message "User cannot be found in selected database"
                            }

                            # Skipping updating dbowner

                            # Database Roles: db_owner, db_datareader, etc
                            foreach ($role in $sourceDb.Roles) {
                                if ($role.EnumMembers() -contains $dbUserName) {
                                    $roleName = $role.Name
                                    if (($server.VersionMajor -lt 11 -and [string]::IsNullOrEmpty($destinationVersion)) -or ($DestinationVersion -in "SQLServer2000", "SQLServer2005", "SQLServer2008/2008R2")) {
                                        $outsql += "EXEC sys.sp_addrolemember @rolename=N'$roleName', @membername=N'$dbUserName'"
                                    } else {
                                        $outsql += "ALTER ROLE [$roleName] ADD MEMBER [$dbUserName]"
                                    }
                                }
                            }

                            # Connect, Alter Any Assembly, etc
                            $perms = $sourceDb.EnumDatabasePermissions($dbUserName)
                            foreach ($perm in $perms) {
                                $permState = $perm.PermissionState
                                $permType = $perm.PermissionType
                                $grantor = $perm.Grantor

                                if ($permState -eq "GrantWithGrant") {
                                    $grantWithGrant = "WITH GRANT OPTION"
                                    $permState = "GRANT"
                                } else {
                                    $grantWithGrant = $null
                                }

                                $outsql += "$permState $permType TO [$userName] $grantWithGrant AS [$grantor]"
                            }
                        }
                    }
                }
                $loginObject = [PSCustomObject]@{
                    Name     = $userName
                    Instance = $server.Name
                    Sql      = $outsql
                }
                $logonCollection.Add($loginObject) | Out-Null
                $outsql = @()
            }
        }
    }
    end {
        foreach ($login in $logonCollection) {
            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $($login.Instance) at $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
            }

            if ($BatchSeparator) {
                $sql = $login.SQL -join "$eol$BatchSeparator$eol"
                #add the final GO
                $sql += "$eol$BatchSeparator"
            } else {
                $sql = $login.SQL
            }



            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = $prefix + $sql
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                if ($instanceArray -notcontains $($login.Instance)) {
                    if ($null -ne $prefix) {
                        $sql = $prefix + $sql
                    }
                    $scriptPath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $login.Instance
                    $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append:$Append -NoClobber:$NoClobber
                    $instanceArray += $login.Instance
                    Get-ChildItem $scriptPath
                } else {
                    $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append
                }
            } else {
                $sql
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBsmb0W+DjPI9Mq
# 7ASMsBcOg7G/0JT1vHzHcMqFE4PQdaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBU+s7DAZaO55H0leN70O6BrNoN+6UyKRgC
# 2N+mqyPizDANBgkqhkiG9w0BAQEFAASCAQBCgd6S1d3KmfSnAcHWNjm/BSumYQ0h
# mVvlmCSqRmFdLXuZnxPJfKAgDw7alTr2LPFf5fKoBjr4H8jJahofKKMK3WAGknYl
# KIt4AmotZWVpK4ZSRcnDzM8xdqI1iHhVEDcDYGfJxfQh/Cqy1WL03FDZc6UN5MK0
# hrnLGUk8cw8jIzSnEXFml9RcWV9sFtLEFrQ9fIAWGC2PHCbyTmQWqCn67c7mTeVb
# AuRS8RJs0zSZ6NQEfMjwYblA8F3KQoJelFU/ZPZXLgbomccqSs02xXT42UfgyPEf
# VMXPYDf3QLvCQTsafy7R2O18Ajm5u8GFAFN8J3hJPZkLhy8trXFnY6NtoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI0M1owLwYJKoZIhvcNAQkEMSIEIMcf+TXU
# /iHhrAIdYUC+Irn4OxXBcO8HlWu4jg90hvLdMA0GCSqGSIb3DQEBAQUABIICACcC
# URYdJpGp3S5sF/9k/W/y18pnIgtlfl8+mWviLa55LVVm27EIgbG0HC0Plqj0ZMz7
# 9yJrrk9B35VrCXExhdd0lw/n0U8PJ4bvWtibGYm+8egbbncTD6iVr2hFGb6vloI1
# wBRyuwGyzCTLUdu1zcU+Hw4Hv3KQd56IhKlGmBh82hG+kLDqqeiMuEEmQvVJ/EUQ
# iXwVS/AFZ/M9RSBQoEWnPp0Hte62ZHyG5Nj0bKUYD7s7+dK1h0SQ5/UKlt0LyrgZ
# NLrEcHOIBeQj/cSZaZk5dbIr53Gz1t7tltIqSTiQEQVE35MgWAXl/LMhLRhmQzyO
# 9YJrEwzZk5ZBpfNPu9iGxtGNw9ESjNzCYjJKa3cZVei350YAQ1Soybvn/8YIRPNp
# M55JubCpPZvGcHfVxGYEx8giFWHf82htR1HieHxkgrrcNocQHM4H/0Wm37DqLWWP
# Ml5Efv/IBLpWEsVEHobeL0bFmN/kKZtmyA9IrtyMD5dGJUz5LPA1FXvCg/W0+cWB
# T6sR55jvr5Jv/sj+6wSsTsl607d+l7s+r/A2lNxdEwn8UQKDKz/r2UuYN2oRmAXz
# 9rnrXrtQtZO96LWStiq9/6IoPr+Jx8Y7Y4F4pIvxofBDd0JduyiKFAU5o1aF5JDH
# ShvCO9Eq/TIzIbhGwgbERtZx3jZlD2q9NXnX1YQf
# SIG # End signature block
