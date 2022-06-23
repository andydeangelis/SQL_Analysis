function Export-DbaUser {
    <#
    .SYNOPSIS
        Exports users creation and its permissions to a T-SQL file or host.

    .DESCRIPTION
        Exports users creation and its permissions to a T-SQL file or host. Export includes user, create and add to role(s), database level permissions, object level permissions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2000 and above supported.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all InputObject will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER User
        Export only the specified database user(s). If not specified will export all users from the database(s)

    .PARAMETER DestinationVersion
        To say to which version the script should be generated. If not specified will use database compatibility level

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

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER InputObject
        Allows database objects to be piped in from Get-DbaDatabase

    .PARAMETER NoClobber
        Do not overwrite file

    .PARAMETER Append
        Append to file

    .PARAMETER Passthru
        Output script to console, useful with | clip

    .PARAMETER Template
        Script user as a templated string that contains tokens {templateUser} and {templateLogin} instead of username and login

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ScriptingOptionsObject
        A Microsoft.SqlServer.Management.Smo.ScriptingOptions object with the options that you want to use to generate the t-sql script.
        You can use the New-DbaScriptingOption to generate it.

    .PARAMETER ExcludeGoBatchSeparator
        If specified, will NOT script the 'GO' batch separator.

    .NOTES
        Tags: User, Export
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaUser

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sql2005 -FilePath C:\temp\sql2005-users.sql

        Exports SQL for the users in server "sql2005" and writes them to the file "C:\temp\sql2005-users.sql"

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a $scred -FilePath C:\temp\users.sql -Append

        Authenticates to sqlserver2014a using SQL Authentication. Exports all users to C:\temp\users.sql, and appends to the file if it exists. If not, the file will be created.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a -User User1, User2 -FilePath C:\temp\users.sql

        Exports ONLY users User1 and User2 from sqlserver2014a to the file C:\temp\users.sql

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a -User User1, User2 -Path C:\temp

        Exports ONLY users User1 and User2 from sqlserver2014a to the folder C:\temp. One file per user will be generated

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -User User1 -FilePath C:\temp\users.sql -DestinationVersion SQLServer2016

        Exports user User1 from sqlserver2008 to the file C:\temp\users.sql with syntax to run on SQL Server 2016

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file.

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptDrops = $false
        PS C:\> $options.WithDependencies = $true
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql -ScriptingOptionsObject $options

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file.
        It will not script drops but will script dependencies.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql -ExcludeGoBatchSeparator

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file without the 'GO' batch separator.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1 -User user1 -Template -PassThru

        Exports user1 from database db1, replacing loginname and username with {templateLogin} and {templateUser} correspondingly.


    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [OutputType([String])]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$User,
        [ValidateSet('SQLServer2000', 'SQLServer2005', 'SQLServer2008/2008R2', 'SQLServer2012', 'SQLServer2014', 'SQLServer2016', 'SQLServer2017', 'SQLServer2019')]
        [string]$DestinationVersion,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [Alias("NoOverwrite")]
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$Passthru,
        [switch]$Template,
        [switch]$EnableException,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject = $null,
        [switch]$ExcludeGoBatchSeparator
    )

    begin {
        $null = Test-ExportDirectory -Path $Path

        $outsql = $script:pathcollection = $instanceArray = @()
        $GenerateFilePerUser = $false

        $versions = @{
            'SQLServer2000'        = 'Version80'
            'SQLServer2005'        = 'Version90'
            'SQLServer2008/2008R2' = 'Version100'
            'SQLServer2012'        = 'Version110'
            'SQLServer2014'        = 'Version120'
            'SQLServer2016'        = 'Version130'
            'SQLServer2017'        = 'Version140'
            'SQLServer2019'        = 'Version150'
        }

        $versionName = @{
            'Version80'  = 'SQLServer2000'
            'Version90'  = 'SQLServer2005'
            'Version100' = 'SQLServer2008/2008R2'
            'Version110' = 'SQLServer2012'
            'Version120' = 'SQLServer2014'
            'Version130' = 'SQLServer2016'
            'Version140' = 'SQLServer2017'
            'Version150' = 'SQLServer2019'
        }

        $eol = [System.Environment]::NewLine

    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        # To keep the filenames generated and re-use (append) if needed
        $usersProcessed = @{ }

        foreach ($db in $InputObject) {

            if ([string]::IsNullOrEmpty($destinationVersion)) {
                #Get compatibility level for scripting the objects
                $scriptVersion = $db.CompatibilityLevel
            } else {
                $scriptVersion = $versions[$destinationVersion]
            }
            $versionNameDesc = $versionName[$scriptVersion.ToString()]

            #If not passed create new ScriptingOption. Otherwise use the one that was passed
            if ($null -eq $ScriptingOptionsObject) {
                $ScriptingOptionsObject = New-DbaScriptingOption
                $ScriptingOptionsObject.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                $ScriptingOptionsObject.AllowSystemObjects = $false
                $ScriptingOptionsObject.IncludeDatabaseRoleMemberships = $true
                $ScriptingOptionsObject.ContinueScriptingOnError = $false
                $ScriptingOptionsObject.IncludeDatabaseContext = $false
                $ScriptingOptionsObject.IncludeIfNotExists = $true
            }

            Write-Message -Level Verbose -Message "Validating users on database $db"

            if ($User) {
                $users = $db.Users | Where-Object { $User -contains $_.Name -and $_.IsSystemObject -eq $false -and $_.Name -notlike "##*" }
            } else {
                $users = $db.Users
            }

            # Generate the file path
            if (Test-Bound -ParameterName FilePath -Not) {
                $GenerateFilePerUser = $true
            } else {
                # Generate a new file name with passed/default path
                $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $db.Parent.Name -Unique
            }

            # Store roles between users so if we hit the same one we don't create it again
            $roles = @()
            $stepCounter = 0
            foreach ($dbuser in $users) {

                if ($GenerateFilePerUser) {
                    if ($null -eq $usersProcessed[$dbuser.Name]) {
                        # If user and not specific output file, create file name without database name.
                        $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $("$($db.Parent.Name)-$($dbuser.Name)") -Unique
                        $usersProcessed[$dbuser.Name] = $FilePath
                    } else {
                        $Append = $true
                        $FilePath = $usersProcessed[$dbuser.Name]
                    }
                }

                Write-ProgressHelper -TotalSteps $users.Count -Activity "Exporting from $($db.Name)" -StepNumber ($stepCounter++) -Message "Generating script ($FilePath) for user $dbuser"

                #setting database
                if (((Test-Bound ScriptingOptionsObject) -and $ScriptingOptionsObject.IncludeDatabaseContext) -or - (Test-Bound ScriptingOptionsObject -Not)) {
                    $useDatabase = "USE [" + $db.Name + "]"
                }

                try {
                    #Fixed Roles #Dependency Issue. Create Role, before add to role.
                    foreach ($rolePermission in ($db.Roles | Where-Object { $_.IsFixedRole -eq $false })) {
                        foreach ($rolePermissionScript in $rolePermission.Script($ScriptingOptionsObject)) {
                            if ($rolePermission.ToString() -notin $roles) {
                                $roles += , $rolePermission.ToString()
                                $outsql += "$($rolePermissionScript.ToString())"
                            }

                        }
                    }

                    #Database Create User(s) and add to Role(s)
                    foreach ($dbUserPermissionScript in $dbuser.Script($ScriptingOptionsObject)) {
                        if ($dbuserPermissionScript.Contains("sp_addrolemember")) {
                            $execute = "EXEC "
                        } else {
                            $execute = ""
                        }
                        $permissionScript = $dbUserPermissionScript.ToString()
                        if ($Template) {
                            $escapedUsername = [regex]::Escape($dbuser.Name)
                            $permissionScript = $permissionScript -replace "\`[$escapedUsername\`]", '[{templateUser}]'
                            $permissionScript = $permissionScript -replace "'$escapedUsername'", "'{templateUser}'"
                            if ($dbuser.Login) {
                                $escapedLogin = [regex]::Escape($dbuser.Login)
                                $permissionScript = $permissionScript -replace "\`[$escapedLogin\`]", '[{templateLogin}]'
                                $permissionScript = $permissionScript -replace "'$escapedLogin'", "'{templateLogin}'"
                            }

                        }
                        $outsql += "$execute$($permissionScript)"
                    }

                    #Database Permissions
                    foreach ($databasePermission in $db.EnumDatabasePermissions() | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and ($dbuser.Name -contains $_.Grantee) }) {
                        if ($databasePermission.PermissionState -eq "GrantWithGrant") {
                            $withGrant = " WITH GRANT OPTION"
                            $grantDatabasePermission = 'GRANT'
                        } else {
                            $withGrant = " "
                            $grantDatabasePermission = $databasePermission.PermissionState.ToString().ToUpper()
                        }
                        if ($Template) {
                            $grantee = "{templateUser}"
                        } else {
                            $grantee = $databasePermission.Grantee
                        }

                        $outsql += "$($grantDatabasePermission) $($databasePermission.PermissionType) TO [$grantee]$withGrant AS [$($databasePermission.Grantor)];"
                    }

                    #Database Object Permissions
                    # NB: This is a bit of a mess for a couple of reasons
                    # 1. $db.EnumObjectPermissions() doesn't enumerate all object types
                    # 2. Some (x)Collection types can have EnumObjectPermissions() called
                    #    on them directly (e.g. AssemblyCollection); others can't (e.g.
                    #    ApplicationRoleCollection). Those that can't we iterate the
                    #    collection explicitly and add each object's permission.

                    $perms = New-Object System.Collections.ArrayList

                    $null = $perms.AddRange($db.EnumObjectPermissions($dbuser.Name))

                    foreach ($item in $db.ApplicationRoles) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.Assemblies) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.Certificates) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.DatabaseRoles) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.FullTextCatalogs) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.FullTextStopLists) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.SearchPropertyLists) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.MessageTypes) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.RemoteServiceBindings) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.Routes) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.ServiceContracts) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.Services) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    if ($scriptVersion -ne "Version80") {
                        foreach ($item in $db.AsymmetricKeys) {
                            $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                        }
                    }

                    foreach ($item in $db.SymmetricKeys) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.XmlSchemaCollections) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($objectPermission in $perms | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and $_.Grantee -eq $dbuser.Name }) {
                        switch ($objectPermission.ObjectClass) {
                            'ApplicationRole' {
                                $object = 'APPLICATION ROLE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'AsymmetricKey' {
                                $object = 'ASYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Certificate' {
                                $object = 'CERTIFICATE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'DatabaseRole' {
                                $object = 'ROLE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'FullTextCatalog' {
                                $object = 'FULLTEXT CATALOG::[{0}]' -f $objectPermission.ObjectName
                            }
                            'FullTextStopList' {
                                $object = 'FULLTEXT STOPLIST::[{0}]' -f $objectPermission.ObjectName
                            }
                            'MessageType' {
                                $object = 'Message Type::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ObjectOrColumn' {
                                if ($scriptVersion -ne "Version80") {
                                    $object = 'OBJECT::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                                    if ($null -ne $objectPermission.ColumnName) {
                                        $object += '([{0}])' -f $objectPermission.ColumnName
                                    }
                                }
                                #At SQL Server 2000 OBJECT did not exists
                                else {
                                    $object = '[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                                }
                            }
                            'RemoteServiceBinding' {
                                $object = 'REMOTE SERVICE BINDING::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Schema' {
                                $object = 'SCHEMA::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SearchPropertyList' {
                                $object = 'SEARCH PROPERTY LIST::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Service' {
                                $object = 'SERVICE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ServiceContract' {
                                $object = 'CONTRACT::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ServiceRoute' {
                                $object = 'ROUTE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SqlAssembly' {
                                $object = 'ASSEMBLY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SymmetricKey' {
                                $object = 'SYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'User' {
                                $object = 'USER::[{0}]' -f $objectPermission.ObjectName
                            }
                            'UserDefinedType' {
                                $object = 'TYPE::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                            }
                            'XmlNamespace' {
                                $object = 'XML SCHEMA COLLECTION::[{0}]' -f $objectPermission.ObjectName
                            }
                        }

                        if ($objectPermission.PermissionState -eq "GrantWithGrant") {
                            $withGrant = " WITH GRANT OPTION"
                            $grantObjectPermission = 'GRANT'
                        } else {
                            $withGrant = " "
                            $grantObjectPermission = $objectPermission.PermissionState.ToString().ToUpper()
                        }
                        if ($Template) {
                            $grantee = "{templateUser}"
                        } else {
                            $grantee = $databasePermission.Grantee
                        }

                        $outsql += "$grantObjectPermission $($objectPermission.PermissionType) ON $object TO [$grantee]$withGrant AS [$($objectPermission.Grantor)];"
                    }

                } catch {
                    Stop-Function -Message "This user may be using functionality from $($versionName[$db.CompatibilityLevel.ToString()]) that does not exist on the destination version ($versionNameDesc)." -Continue -InnerErrorRecord $_ -Target $db
                }

                if (@($outsql.Count) -gt 0) {
                    if ($ExcludeGoBatchSeparator) {
                        $sql = "$useDatabase $outsql"
                    } else {
                        if ($useDatabase) {
                            $sql = "$useDatabase$($eol)GO$eol" + ($outsql -join "$($eol)GO$eol")
                        } else {
                            $sql = $outsql -join "$($eol)GO$eol"
                        }
                        #add the final GO
                        $sql += "$($eol)GO"
                    }
                }

                if (-not $Passthru) {
                    # If generate a file per user, clean the collection to populate with next one
                    if ($GenerateFilePerUser) {
                        if (-not [string]::IsNullOrEmpty($sql)) {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            Get-ChildItem -Path $FilePath
                        }
                    } else {
                        $dbUserInstance = $dbuser.Parent.Parent.Name

                        if ($instanceArray -notcontains $($dbUserInstance)) {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            $instanceArray += $dbUserInstance
                        } else {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append
                        }
                    }
                    # Clear variables for next user
                    $outsql = @()
                    $sql = ""
                } else {
                    $sql
                }
            }
        }
        # Just a single file, output path once here
        if (-Not $GenerateFilePerUser -and $FilePath) {
            Get-ChildItem -Path $FilePath
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDBXipu3XeQPJRi
# FebkY5WLeTu3aEYZXaYPhhbxPChlP6CCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBOGqSpFbr+0YestlbtEkD4IXiGF49GQMH0
# wBYSP/cJZzANBgkqhkiG9w0BAQEFAASCAQBMxnmHQHvZSl7VhBBWAe1EgcICBq12
# WlQ2LIQlQ2Da3pgyIqbh3ZtlFyTiiLhi8HEj1yZrWzEp/IXtQFN9tFCKzslVg0YX
# NrvL3aAzjsYhLvytuxDPacYYd4+ITe3DVHSbtOKM8wJRG7rVNxurC6aUyOrOMyvP
# skDZ7Tl7Y9J1wf4SkupA2ZDVuXZjtZVNdyVs3hYXPD6UlgmIuJSm8oJImDCsQmpY
# yhSIViJkdFuGJ5zguAbTNMQD9BP4lu3iSiy1DcelALCN/U6PjL4fgGRY+WfhpQSc
# Vz3FuyrPfZFTYMvPIQzcDBaXxM2wC4ALJQeA3S622nmUCuxA6IoHXHNHoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI0NVowLwYJKoZIhvcNAQkEMSIEIGhwbF0+
# fOhvi7mAsc+AF0rcm3ZrrRzTU9VOa6lj45HPMA0GCSqGSIb3DQEBAQUABIICAKKb
# cGMZxdNmeyW12XYu1S2cEqovsh3q9nH90sBev0Q5ovpeyfoagLuqLeZaEq4EUXln
# i5N6BRuxxxEye2smuJ8U7VmiFGblnqM9Kv4xvKuIma/Hzi0d45EqIpSJxoezNXUJ
# hobHysaZ0d3S6kVdw+MMSnfgvly+Fk9qob/UBTk197g7B5NluckhVTL01I0qSLrF
# xS6dWOoTG5V9mzrM5y1Sp8Cb+1WZJGnSRElGv0YtOPWXdbKZOWsHWT0vtzHQf10g
# atylycUq1cKzlTnR5rtqAuLtUrrUagsyUrgu5oduZV1Eh2On2KM59T8e64jhWd1R
# iGFG3tH2l+Z0EMZaqPQnohCdzVcY9FMARI9QO6jmRXGeue+eQJcfuVS57A6pCU+h
# aNdMfwT+adxvB+fHDHngQkUZlxTE+tQacRptFyeCD/QKhnWNMnnm1fUXcQ32NNjN
# TnhGo2//9fQapXpukL+MqjO0ERBnLIcfIOl0r9KGE+BbVvmF6Htgwmn5mDvaRGZT
# VHoYpNHxgyeOR3dAYIBqOhxO+DlIql82mODpm2aM+KU3yxSErf1ZXnY25L/kXmUM
# aEBpdBFD4g40EcQfjEuMpuicqVN66RpY1IXFgKPPNFn7XlV07RFLe5ScjDQmW9pL
# XE+50RDgfZ8HL8GsSpG/kguCu7BmsgSsBFeDXWIK
# SIG # End signature block
