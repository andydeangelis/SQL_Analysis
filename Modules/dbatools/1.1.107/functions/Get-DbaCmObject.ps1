function Get-DbaCmObject {
    <#
    .SYNOPSIS
        Retrieves Wmi/Cim-Style information from computers.

    .DESCRIPTION
        This function centralizes all requests for information retrieved from Get-WmiObject or Get-CimInstance.
        It uses different protocols as available in this order:
        - Cim over WinRM
        - Cim over DCOM
        - Wmi
        - Wmi over PowerShell Remoting
        It remembers channels that didn't work and will henceforth avoid them. It remembers invalid credentials and will avoid reusing them.
        Much of its behavior can be configured using Test-DbaCmConnection.

    .PARAMETER ClassName
        The name of the class to retrieve.

    .PARAMETER Query
        The Wmi/Cim query to run against the server.

    .PARAMETER ComputerName
        The computer(s) to connect to. Defaults to localhost.

    .PARAMETER Credential
        Credentials to use. Invalid credentials will be stored in a credentials cache and not be reused.

    .PARAMETER Namespace
        The namespace of the class to use.

    .PARAMETER DoNotUse
        Connection Protocols that should not be used.

    .PARAMETER Force
        Overrides some checks that might otherwise halt execution as a precaution
        - Ignores timeout on bad connections

    .PARAMETER SilentlyContinue
        Use in conjunction with the -EnableException switch.
        By default, Get-DbaCmObject will throw a terminating exception when connecting to a target is impossible in exception enabled mode.
        Setting this switch will cause it write a non-terminating exception and continue with the next computer.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ComputerManagement, CIM
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCmObject

    .EXAMPLE
        PS C:\> Get-DbaCmObject win32_OperatingSystem

        Retrieves the common operating system information from the local computer.

    .EXAMPLE
        PS C:\> Get-DbaCmObject -Computername "sql2014" -ClassName Win32_OperatingSystem -Credential $cred -DoNotUse CimRM

        Retrieves the common operating system information from the server sql2014.
        It will use the Credentials stored in $cred to connect, unless they are known to not work, in which case they will default to windows credentials (unless another default has been set).
    #>
    [CmdletBinding(DefaultParameterSetName = "Class")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWMICmdlet", "", Justification = "Using Get-WmiObject is used as a fallback for gathering information")]
    param (
        [Parameter(Mandatory, ParameterSetName = "Class", Position = 0)]
        [Alias('Class')]
        [string]$ClassName,
        [Parameter(Mandatory, ParameterSetName = "Query")]
        [string]$Query,
        [Parameter(ValueFromPipeline)]
        [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$Namespace = "root\cimv2",
        [Sqlcollaborative.Dbatools.Connection.ManagementConnectionType[]]
        $DoNotUse = "None",
        [switch]$Force,
        [switch]$SilentlyContinue,
        [switch]$EnableException
    )

    begin {
        #region Configuration Values
        $disable_cache = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableCache

        Write-Message -Level Verbose -Message "Configuration loaded | Cache disabled: $disable_cache"
        #endregion Configuration Values

        $ParSet = $PSCmdlet.ParameterSetName
    }
    process {
        # uses cim commands
        :main foreach ($connectionObject in $ComputerName) {
            if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret input: $($connectionObject.Input)" -Category InvalidArgument -Target $connectionObject.Input -Continue -SilentlyContinue:$SilentlyContinue }

            # Since all connection caching runs using lower-case strings, making it lowercase here simplifies things.
            $computer = $connectionObject.Connection.ComputerName.ToLowerInvariant()

            Write-Message -Message "[$computer] Retrieving Management Information" -Level VeryVerbose -Target $computer

            $connection = $connectionObject.Connection

            # Ensure using the right credentials
            try { $cred = $connection.GetCredential($Credential) }
            catch {
                $message = "Bad credentials. "
                if ($Credential) { $message += "The credentials for $($Credential.UserName) are known to not work. " }
                else { $message += "The windows credentials are known to not work. " }
                if ($connection.EnableCredentialFailover -or $connection.OverrideExplicitCredential) { $message += "The connection is configured to use credentials that are known to be good, but none have been registered yet. " }
                elseif ($connection.Credentials) { $message += "Working credentials are known for $($connection.Credentials.UserName), however the connection is not configured to automatically use them. This can be done using 'Set-DbaCmConnection -ComputerName $connection -OverrideExplicitCredential' " }
                elseif ($connection.UseWindowsCredentials) { $message += "The windows credentials are known to work, however the connection is not configured to automatically use them. This can be done using 'Set-DbaCmConnection -ComputerName $connection -OverrideExplicitCredential' " }
                $message += $_.Exception.Message
                Stop-Function -Message $message -ErrorRecord $_ -Target $connection -Continue -OverrideExceptionMessage
            }

            # Flags-Enumerations cannot be added in PowerShell 4 or older.
            # Thus we create a string and convert it afterwards.
            $enabledProtocols = "None"
            if ($connection.CimRM -notlike "Disabled") { $enabledProtocols += ", CimRM" }
            if ($connection.CimDCOM -notlike "Disabled") { $enabledProtocols += ", CimDCOM" }
            if ($connection.Wmi -notlike "Disabled") { $enabledProtocols += ", Wmi" }
            if ($connection.PowerShellRemoting -notlike "Disabled") { $enabledProtocols += ", PowerShellRemoting" }
            [Sqlcollaborative.Dbatools.Connection.ManagementConnectionType]$enabledProtocols = $enabledProtocols

            # Create list of excluded connection types (Duplicates don't matter)
            $excluded = @()
            foreach ($item in $DoNotUse) { $excluded += $item }

            :sub while ($true) {
                try { $conType = $connection.GetConnectionType(($excluded -join ","), $Force) }
                catch {
                    if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                    Stop-Function -Message "[$computer] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: $enabledProtocols" -Target $computer -Category OpenError -Continue -ContinueLabel "main" -SilentlyContinue:$SilentlyContinue -ErrorRecord $_
                }

                switch ($conType.ToString()) {
                    #region CimRM
                    "CimRM" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM"
                        try {
                            if ($ParSet -eq "Class") { $connection.GetCimRMInstance($cred, $ClassName, $Namespace) }
                            else { $connection.QueryCimRMInstance($cred, $Query, "WQL", $Namespace) }

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM - Success"
                            $connection.ReportSuccess('CimRM')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        } catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM - Failed"
                            $errorItem = $_

                            switch ($_.Exception.InnerException.StatusCode) {
                                # Code Reference: https://msdn.microsoft.com/en-us/library/cc150671(v=vs.85).aspx
                                #region 1 = Generic runtime error
                                1 {
                                    # 0x8007052e, 0x80070005 : Authentication error, bad credential
                                    if (($errorItem.Exception.InnerException.MessageId -eq "HRESULT 0x8007052e") -or ($errorItem.Exception.InnerException.MessageId -eq "HRESULT 0x80070005")) {
                                        # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                        # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                        $connection.AddBadCredential($cred)
                                        if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                        Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                                    } elseif ($errorItem.Exception.InnerException.MessageId -eq "HRESULT 0x80041013") {
                                        if ($ParSet -eq "Class") { Stop-Function -Message "[$computer] Failed to access $class in namespace $Namespace" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -Exception $errorItem.Exception.InnerException }
                                        else { Stop-Function -Message "[$computer] Failed to execute $query in namespace $Namespace" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -Exception $errorItem.Exception.InnerException }
                                    } else {
                                        $connection.ReportFailure('CimRM')
                                        $excluded += "CimRM"
                                        continue sub
                                    }
                                }
                                #endregion 1 = Generic runtime error
                                #region 2 = Access to specific resource denied
                                2 { Stop-Function -Message "[$computer] Access to computer granted, but access to $Namespace\$ClassName denied" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 2 = Access to specific resource denied
                                #region 3 = Invalid Namespace
                                3 { Stop-Function -Message "[$computer] Invalid namespace: $Namespace" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 3 = Invalid Namespace
                                #region 4 - Invalid Parameter
                                4 { Stop-Function -Message "[$computer] Invalid parameters were specified" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 4 - Invalid Parameter
                                #region 5 = Invalid Class
                                5 { Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 5 = Invalid Class
                                #region 6 = Object not Found
                                6 { Stop-Function -Message "[$computer] The requested object of class $ClassName could not be found" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 6 = Object not Found
                                #region 7 = Operation not Supported
                                7 { Stop-Function -Message "[$computer] The operation against class $ClassName was not supported. This generally is a serverside WMI Provider issue (That is: It is specific to the application being managed via WMI)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 7 = Operation not Supported
                                #region 8 = Class has children
                                8 { Stop-Function -Message "[$computer] The operation against class $ClassName is refused as long as it contains instances (data)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 8 = Class has children
                                #region 9 = Class has instances
                                9 { Stop-Function -Message "[$computer] The operation against class $ClassName is refused as long as it contains instances (data)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 9 = Class has instances
                                #region 10 = Invalid Superclass
                                10 { Stop-Function -Message "[$computer] The operation against class $ClassName cannot be carried out since the specified superclass does not exist." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 10 = Invalid Superclass
                                #region 11 = Already Exists
                                11 { Stop-Function -Message "[$computer] The specified object in $ClassName already exists." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 11 = Already Exists
                                #region 12 = No Such Property
                                12 { Stop-Function -Message "[$computer] The specified property does not exist on $ClassName." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 12 = No Such Property
                                #region 13 = Type Mismatch
                                13 { Stop-Function -Message "[$computer] The input type is invalid." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 13 = Type Mismatch
                                #region 14 = Query Language not supported
                                14 { Stop-Function -Message "[$computer] Invalid query language. Please check your query string." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 14 = Query Language not supported
                                #region 15 = Invalid Query
                                15 { Stop-Function -Message "[$computer] Invalid query string. Please check your syntax." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 15 = Invalid Query
                                #region 16 = Method not available
                                16 { Stop-Function -Message "[$computer] The specified method on $ClassName is not available." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #region 16 = Method not available
                                #region 17 = Method not found
                                17 { Stop-Function -Message "[$computer] The specified method on $ClassName does not exist." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 17 = Method not found
                                #region 18 = Unexpected Response
                                18 { Stop-Function -Message "[$computer] An unexpected response has happened in this request" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 18 = Unexpected Response
                                #region 19 = Invalid Response Destination
                                19 { Stop-Function -Message "[$computer] The specified destination for this request is invalid." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 19 = Invalid Response Destination
                                #region 20 = Namespace not empty
                                20 { Stop-Function -Message "[$computer] The specified namespace $Namespace is not empty." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 20 = Namespace not empty

                                #region Default | 0 = Non-CIM Issue not covered by the framework
                                default {
                                    # 0 & ExtendedStatus = Weird issue beyond the scope of the CIM standard. Often a server-side issue
                                    if ($errorItem.Exception.InnerException.ErrorData.original_error -like "__ExtendedStatus") {
                                        Stop-Function -Message "[$computer] Something went wrong when looking for $ClassName, in $Namespace. This often indicates issues with the target system." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue
                                    } else {
                                        $connection.ReportFailure('CimRM')
                                        $excluded += "CimRM"
                                        continue sub
                                    }
                                }
                                #endregion Default | 0 = Non-CIM Issue not covered by the framework
                            }
                        }
                    }
                    #endregion CimRM

                    #region CimDCOM
                    "CimDCOM" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM"
                        try {
                            if ($ParSet -eq "Class") { $connection.GetCimDCOMInstance($cred, $ClassName, $Namespace) }
                            else { $connection.QueryCimDCOMInstance($cred, $Query, "WQL", $Namespace) }

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM - Success"
                            $connection.ReportSuccess('CimDCOM')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        } catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM - Failed"
                            $errorItem = $_

                            switch ($_.Exception.InnerException.StatusCode) {
                                # Code Reference: https://msdn.microsoft.com/en-us/library/cc150671(v=vs.85).aspx
                                #region 1 = Generic runtime error
                                1 {
                                    # 0x8007052e, 0x80070005 : Authentication error, bad credential
                                    if (($errorItem.Exception.InnerException.MessageId -eq "HRESULT 0x8007052e") -or ($errorItem.Exception.InnerException.MessageId -eq "HRESULT 0x80070005")) {
                                        # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                        # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                        $connection.AddBadCredential($cred)
                                        if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                        Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                                    } elseif ($errorItem.Exception.InnerException.MessageId -eq "HRESULT 0x80041013") {
                                        if ($ParSet -eq "Class") { Stop-Function -Message "[$computer] Failed to access $class in namespace $Namespace" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -Exception $errorItem.Exception.InnerException }
                                        else { Stop-Function -Message "[$computer] Failed to execute $query in namespace $Namespace" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -Exception $errorItem.Exception.InnerException }
                                    } else {
                                        $connection.ReportFailure('CimDCOM')
                                        $excluded += "CimDCOM"
                                        continue sub
                                    }
                                }
                                #endregion 1 = Generic runtime error
                                #region 2 = Access to specific resource denied
                                2 { Stop-Function -Message "[$computer] Access to computer granted, but access to $Namespace\$ClassName denied" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 2 = Access to specific resource denied
                                #region 3 = Invalid Namespace
                                3 { Stop-Function -Message "[$computer] Invalid namespace: $Namespace" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 3 = Invalid Namespace
                                #region 4 - Invalid Parameter
                                4 { Stop-Function -Message "[$computer] Invalid parameters were specified" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 4 - Invalid Parameter
                                #region 5 = Invalid Class
                                5 { Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 5 = Invalid Class
                                #region 6 = Object not Found
                                6 { Stop-Function -Message "[$computer] The requested object of class $ClassName could not be found." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 6 = Object not Found
                                #region 7 = Operation not Supported
                                7 { Stop-Function -Message "[$computer] The operation against class $ClassName was not supported. This generally is a serverside WMI Provider issue (That is: It is specific to the application being managed via WMI)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 7 = Operation not Supported
                                #region 8 = Class has children
                                8 { Stop-Function -Message "[$computer] The operation against class $ClassName is refused as long as it contains instances (data)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 8 = Class has children
                                #region 9 = Class has instances
                                9 { Stop-Function -Message "[$computer] The operation against class $ClassName is refused as long as it contains instances (data)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 9 = Class has instances
                                #region 10 = Invalid Superclass
                                10 { Stop-Function -Message "[$computer] The operation against class $ClassName cannot be carried out since the specified superclass does not exist." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 10 = Invalid Superclass
                                #region 11 = Already Exists
                                11 { Stop-Function -Message "[$computer] The specified object in $ClassName already exists." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 11 = Already Exists
                                #region 12 = No Such Property
                                12 { Stop-Function -Message "[$computer] The specified property does not exist on $ClassName." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 12 = No Such Property
                                #region 13 = Type Mismatch
                                13 { Stop-Function -Message "[$computer] The input type is invalid." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 13 = Type Mismatch
                                #region 14 = Query Language not supported
                                14 { Stop-Function -Message "[$computer] Invalid query language. Check your query string." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 14 = Query Language not supported
                                #region 15 = Invalid Query
                                15 { Stop-Function -Message "[$computer] Invalid query string, check your syntax." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 15 = Invalid Query
                                #region 16 = Method not available
                                16 { Stop-Function -Message "[$computer] The specified method on $ClassName is not available." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #region 16 = Method not available
                                #region 17 = Method not found
                                17 { Stop-Function -Message "[$computer] The specified method on $ClassName does not exist." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 17 = Method not found
                                #region 18 = Unexpected Response
                                18 { Stop-Function -Message "[$computer] An unexpected response has happened in this request" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 18 = Unexpected Response
                                #region 19 = Invalid Response Destination
                                19 { Stop-Function -Message "[$computer] The specified destination for this request is invalid." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 19 = Invalid Response Destination
                                #region 20 = Namespace not empty
                                20 { Stop-Function -Message "[$computer] The specified namespace $Namespace is not empty." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage }
                                #endregion 20 = Namespace not empty

                                #region Default | 0 = Non-CIM Issue not covered by the framework
                                default {
                                    # 0 & ExtendedStatus = Weird issue beyond the scope of the CIM standard. Often a server-side issue
                                    if ($errorItem.Exception.InnerException.ErrorData.original_error -like "__ExtendedStatus") {
                                        Stop-Function -Message "[$computer] Something went wrong when looking for $ClassName, in $Namespace. This often indicates issues with the target system." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $errorItem -SilentlyContinue:$SilentlyContinue
                                    } else {
                                        $connection.ReportFailure('CimDCOM')
                                        $excluded += "CimDCOM"
                                        continue sub
                                    }
                                }
                                #endregion Default | 0 = Non-CIM Issue not covered by the framework
                            }
                        }
                    }
                    #endregion CimDCOM

                    #region Wmi
                    "Wmi" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI"
                        try {
                            switch ($ParSet) {
                                "Class" {
                                    $parameters = @{
                                        ComputerName = $computer
                                        ClassName    = $ClassName
                                        ErrorAction  = 'Stop'
                                    }
                                    if ($cred) { $parameters["Credential"] = $cred }
                                    if (Test-Bound "Namespace") { $parameters["Namespace"] = $Namespace }

                                }
                                "Query" {
                                    $parameters = @{
                                        ComputerName = $computer
                                        Query        = $Query
                                        ErrorAction  = 'Stop'
                                    }
                                    if ($cred) { $parameters["Credential"] = $cred }
                                    if (Test-Bound "Namespace") { $parameters["Namespace"] = $Namespace }
                                }
                            }

                            Get-WmiObject @parameters

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI - Success"
                            $connection.ReportSuccess('Wmi')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        } catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI - Failed" -ErrorRecord $_

                            if ($_.CategoryInfo.Reason -eq "UnauthorizedAccessException") {
                                # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                $connection.AddBadCredential($cred)
                                if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            } elseif ($_.CategoryInfo.Category -eq "InvalidType") {
                                Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            } elseif ($_.Exception.ErrorCode -eq "ProviderLoadFailure") {
                                Stop-Function -Message "[$computer] Failed to access: $ClassName, in namespace: $Namespace - There was a provider error. This indicates a potential issue with WMI on the server side." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            } else {
                                $connection.ReportFailure('Wmi')
                                $excluded += "Wmi"
                                continue sub
                            }
                        }
                    }
                    #endregion Wmi

                    #region PowerShell Remoting
                    "PowerShellRemoting" {
                        try {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using PowerShell Remoting"
                            $scp_string = "Get-WmiObject -Class $ClassName -ErrorAction Stop"
                            if ($PSBoundParameters.ContainsKey("Namespace")) { $scp_string += " -Namespace $Namespace" }

                            $parameters = @{
                                ScriptBlock  = ([System.Management.Automation.ScriptBlock]::Create($scp_string))
                                ComputerName = $computer
                                Raw          = $true
                            }
                            if ($Credential) { $parameters["Credential"] = $Credential }
                            Invoke-Command2 @parameters

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using PowerShell Remoting - Success"
                            $connection.ReportSuccess('PowerShellRemoting')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        } catch {
                            # Will always consider authenticated, since any call with credentials to a server that doesn't exist will also carry invalid credentials error.
                            # There simply is no way to differentiate between actual authentication errors and server not reached
                            $connection.ReportFailure('PowerShellRemoting')
                            $excluded += "PowerShellRemoting"
                            continue sub
                        }
                    }
                    #endregion PowerShell Remoting
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD0xzWMJphzOb49
# a9THyMZ5EF3rUi+55/ef+0R9HLZkM6CCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBmnLk0IpVg6VKO7hA0fc3lz2FdA0cs9Xmp
# FSsv4djckjANBgkqhkiG9w0BAQEFAASCAQBurpnHMRH3YghHGzX99c5swgmlFTWm
# HAmsidMRZ0jD7x4XUe0a7DrgcvvfofqtMrbqnHhLaO2qFBuxE8Nx+mPQo6TU6TZr
# XvpypDi4GPv8P2E7Td2ZCp9rXyfpPoefHXFYKvG3uLC85o8Su7Pzyi5gHeFRQpl4
# WwS7UoIa2/xER4WRmP170nRbj1YmzgI6HW0IsmfSgn64ysmuoI1VZKNHOuVEGeoL
# +AHz48tlnesNCjVMQhKH25Dek1N7ZqphZuXAhEENRyzszosDPRMqVoEfGAJFizXl
# Op2YtB+Q+OdWB4Raur8PzowDCRXuSRewk5u68/qWSp/h5qKHUcA+jzb3oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDI1MlowLwYJKoZIhvcNAQkEMSIEIFti+0oh
# Avn2A1XpJdByX4FGlayHQ9/nZDF80/rFrVbOMA0GCSqGSIb3DQEBAQUABIICADRV
# oqcssuqzz1Nt8mrXn9dSS0zBIXC98kOL3gNwAU3ZpYQ3HOzRSCTwNzbxeD47N70Z
# XHh5GuNFKxeoGq/pJCUS8EIUBRAFriS2CanJGzCGOnwKJgNWi9Ch3k78h0CuG8Da
# mowGlfLs+FRZzc6AF2doL1mobco0/R/FiHXmB0ioODRjvoQZkeqi506E4XV09QnY
# t75QfdDnAu4LrH+LOQDK5A43iPXd9EW+YvUfJWejpl4cMk8Z0Yp+gbx+WVn2yjbg
# 8dlXBMge4geP5yDPucL9fiStYLMLMvhacNeCOqJHGezlh9ThTueM8Amo0u0ZkOOL
# dpVm+yRl6gUuMAq4gRUykmicYsEtVjBCK/ew4dnoNPSTpBdMVC0XJqVwrS3f5ZRO
# HS64S+k9RMKWLI/MUJpcf+GWrB6GjaBQbO0qTmTq2wSLOw3hmYKKpnjB3v2ziqIc
# cmreChym0ykc6inZ2mdYtUF9NEdY0GW64Pb5y6U36Qz+IP2PRRsQn7vEJ3JkBK6P
# OcA5Juowhew42zXeXpkfg1l988bniBZribg7jdrkQvdj8qSgEjvW5i8cNi8M0byH
# 03k3sGgKnR2DIztlf0HcYAxIPlh1HU4+i4ojjYn2LwqyFxFhEs2AhPf4Xa/IxznI
# bHxL6l8AZ/JgBvTmJ5AqCpSsUxWQeftC45maayEk
# SIG # End signature block
