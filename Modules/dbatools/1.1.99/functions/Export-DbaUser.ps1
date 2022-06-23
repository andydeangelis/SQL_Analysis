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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUKmIZf2zVtKX5vvPpLhrmbsOU
# cWOgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFCYJIPBUnbywzZmOsEzTOZ1QyHcjMA0G
# CSqGSIb3DQEBAQUABIIBAIogOU15LTrdwl7Wk2frCgjGW+uCCAXBL96OtKAEKAx9
# IL+JYOwDpj9Y+mLsTl9ydRorXxlWpwzBl+1V2j2vUODYJQIFDFW0NTTm1rv2pjj+
# zvQboKHqoyTwpqrU/b1xUr5F4DIkDdhnqbUs1UZl4IgzONARW5xtlYPN6b7Q/5XP
# ugGrzO4g2L4899fkZpdnG+9PTrQePUbUU0crxiO/pfw8bGZoEa71qPz6x1ZfdAow
# ELITQ7B7UlV30/dSXERvC92Bv2XswctfeAKB/49NrDgVkfdclJPE1Z6Sc8KYAIB6
# 72OXLKpKOklP072IE2tRdcOiwarciTgK6oS7kZI3JeihggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzE5WjAvBgkqhkiG9w0BCQQxIgQgsB/FOTFOvDdGdcfIwyYZ
# ccmkCjCzl8lJT/Ote2I9Qe0wDQYJKoZIhvcNAQEBBQAEggIATNaiEOmtqolWETeM
# la4P6Ks359VPKcld/xoFsVaLL9hGe10w6IT11RY4iqUsgZwzLRCYNV89qaFDSzv3
# 6SpTECcqw5VwEs7ER57mEVp+OhUk/mGfOn+sphqo0kCLESfTChmnaWUw+AjrVSWX
# 2oYEHa0IH3LbodtR/OvniBpWGs9mXQE0KuEP+tCbTlK0Y5XgmrDZUgBHq1Sl7z8d
# n1NSFPHrduC8wLTO3jpCpw//cGQz0PqCDVXZsYq8NxNKwuFfhs6euHbr9+ZOX/NZ
# qt38G7TgLNDQnHyZI1EkueDl/UfQUBZ/nSf0Ol2GvTeqLMZjQlHnNz/N7otpUc7v
# mpPZgSv9hBIJXeo0THzOcufRZv30vii6js6B7Ui71e1aorldFXDcv4WBQy/ILX9X
# XJsV3s8glUlyZFR3fXJkWiZkHzR+NS8BeioWgsjM7II+5La4Bc4RiD2/IF1LqFJM
# eOWK2219rwcs8rk8zL77ODzU7Py6znOWkENSKZblZTzC5p1Zqct29+3kKf2tSGqz
# xgyT/w0HUQH/u8oqz4T8u5GmksQ4/lw/552hbr5ECAVHc91XahSFLyFdN3L0ATfs
# cisZNYdJUADbo7exm+oSb2HyFBfHRafiXQhdyERaEpLq6oQCM6+agUIPawAS0pXN
# iz1iQV5ZfWKQC3OCGK9+jXdgIHQ=
# SIG # End signature block
