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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUoHzsa5TFudVkDCBo+4395emR
# MxOgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFLRo755ZWSP9JBIKiYy0m22lKKBZMA0G
# CSqGSIb3DQEBAQUABIIBAJ2X6CkyYL64ydDRFOg8EPxHL3r4q4Tt584WDTl4eEyU
# Icu4BF+SmA3/wXAc+IFN2Gh0Xa1cxtUpc8d1c3o5I1RMaaP1iA3pnoM4oOCp6CgN
# QT7XlV/ifGh1IkA+Db5aszeJ2wcfvLJIbDPAb/O62YeKoKrkqLVjoIHomBYHuve+
# 1/1/W2nbfIewrIKZWRYrvXGYWgvDmf2B0T68bpiUCiYJm47Jhg4peTLTrGwbBgFH
# HhudGZqPg7WmOHbqt9B/j2LwZXoRRThzEEwT1CCU1HJOtpof7iuUJ3gLCcvpY1+e
# KMZrHItMMmpOLVj3ii6H1cLT+kNxo1DCcijnTz/DFvShggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzI1WjAvBgkqhkiG9w0BCQQxIgQg/OIZ2trvoyIk0w6lRhEz
# 7OKxtTpq8kyZoO9gNRA6MgQwDQYJKoZIhvcNAQEBBQAEggIAfVmYKvsra01Se0Qc
# FmA6uI2SHx2AWzuKQF0hTkB86ISYcSBjhtFs5gxHLNFAnRaF0Djl91CearTUdNcd
# D5eOqgCpRFq54GEN4iyn+Yn04Uze+KsKtaCRS11U9Nq0wbRmZ757TH/g7pybTxuH
# LzJmeUxP1kztyXid0u3lmdZ0ikhzNOFMMYYe84O+guj9PxZr0l8jz1116bDLlr78
# Zms9KvxmHnM2jE8jvLH7TG+CfSxB4nmGOvHA8DEJkD6YVrsrefgABPe9JKCvk2NL
# QsQzzoIB0tF6codzjYWk96abA4DQOKYaH1abkWr9SMQygRk8GraLzGRsUUQDG/QU
# RKff9kNrrh7As2TDYVBsTkxN5VA546DUrhH1j785/buOPqP794gB9gZ/KtHUJ9Wx
# FbeLxC4z3YbpoqmIjOgP1pEw5G34RLQPc506lCTsqdVoRH0adObMUhc66mo+Fpqx
# RDRQ35805GO8+xCkmgRnALtqoL2wBKslekDjEewitIOH1LT+yFgQz8pB05yXNl5y
# n3dfitOTj/ONvlQKTZ1EdqIlilh4v8L2YqqD3v3+6mChOk3x5d6eLZibUzhcq/Dr
# U1ItZ9TGc2+PgzZoov9n1InUpJTZcbOU7w6WJgPQGjPlglaEsvFqLVlw3yxxo3cL
# zTE1DfLLrDsq81S4AVfbB4Y48t8=
# SIG # End signature block
