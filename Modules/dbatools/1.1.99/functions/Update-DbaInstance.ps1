function Update-DbaInstance {
    <#
    .SYNOPSIS
        Invokes installation of SQL Server Service Packs and Cumulative Updates on local and remote servers.

    .DESCRIPTION
        Starts an automated process of updating SQL Server installation to a specific version defined in the parameters.
        The command will:

        * Search for SQL Server installations in a remote registry
        * Check if current settings are applicable to the current SQL Server versions
        * Search for a KB executable in a folder specified in -Path
        * Establish a PSRemote connection to the target machine if necessary
        * Extract KB to a temporary folder in a current user's profile
        * Run the installation from the temporary folder updating all instances on the computer at once
        * Remove temporary files
        * Restart the computer (if -Restart is specified)
        * Repeat for each consequent KB and computer

        The impact of this function is set to High, if you don't want to receive interactive prompts, set -Confirm to $false.

        When using CredSSP authentication, this function will try to configure CredSSP authentication for PowerShell Remoting sessions.
        If this is not desired (e.g.: CredSSP authentication is managed externally, or is already configured appropriately,)
        it can be disabled by setting the dbatools configuration option 'commands.initialize-credssp.bypass' value to $true.
        To be able to configure CredSSP, the command needs to be run in an elevated PowerShell session.

        Always backup databases and configurations prior to upgrade.

    .PARAMETER ComputerName
        Target computer with SQL instance or instances.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if update Repository is located on a network folder.

        Authentication will default to CredSSP if -Credential is used.
        For CredSSP see also additional information in DESCRIPTION.

    .PARAMETER Type
        Type of the update: All | ServicePack | CumulativeUpdate.
        Default: All
        Use -Version to limit upgrade to a certain Major version of SQL Server.

    .PARAMETER KB
        Install a specific update or list of updates. Can be a number of a string KBXXXXXXX.

    .PARAMETER Version
        A target version of the installation you want to reach. If not specified, a latest available version would be used by default.
        Can be defined using the following general pattern: <MajorVersion><SPX><CUX>.
        Any part of the pattern can be omitted if needed:
        2008R2SP1 - will update SQL 2008R2 to SP1
        2016CU3 - will update SQL 2016 to CU3 of current Service Pack installed
        SP0CU3 - will update all existing SQL Server versions to RTM CU3 without installing any service packs
        SP1CU7 - will update all existing SQL Server versions to SP1 and then (after restart if -Restart is specified) to SP1CU7
        CU7 - will update all existing SQL Server versions to CU7 of current Service Pack installed

    .PARAMETER Path
        Path to the folder(s) with SQL Server patches downloaded. It will be scanned recursively for available patches.
        Path should be available from both server with SQL Server installation and client that runs the command.
        All file names should match the pattern used by Microsoft: SQLServer####*-KB###-*x##*.exe
        If a file is missing in the repository, the installation will fail.
        Consider setting the following configuration if you want to omit this parameter: `Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates'`

    .PARAMETER Restart
        Restart computer automatically after a successful installation of a patch and wait until it comes back online.
        Using this parameter is the only way to chain-install more than 1 patch on a computer, since every single patch will require a restart of said computer.

    .PARAMETER Continue
        Continues a failed installation attempt when specified. Will abort a previously failed installation otherwise.

    .PARAMETER Authentication
        Chooses an authentication protocol for remote connections.
        Allowed values: 'Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos'.
        If the protocol fails to establish a connection and explicit -Credentials were used, a failback authentication method would be attempted that configures PSSessionConfiguration
        on the remote machine. This method, however, is considered insecure and would, therefore, prompt an additional confirmation when used.

        Defaults:
        * CredSSP when -Credential is specified - due to the fact that repository Path is usually a network share and credentials need to be passed to the remote host to avoid the double-hop issue.
        * Default when -Credential is not specified. Will likely fail if a network path is specified.

        For CredSSP see also additional information in DESCRIPTION.

    .PARAMETER InstanceName
        Only updates a specific instance(s).

    .PARAMETER Throttle
        Maximum number of computers updated in parallel. Once reached, the update operations will queue up.
        Default: 50

    .PARAMETER ArgumentList
        A list of extra arguments to pass to the execution file. Accepts one or more strings containing command line parameters.
        Example: ... -ArgumentList "/SkipRules=RebootRequiredCheck", "/Q"

    .PARAMETER Download
        Download missing KBs to the first folder specified in the -Path parameter.
        Files would be first downloaded to the local machine (TEMP folder), and then distributed onto remote machines if needed.
        If the Path is a network Path, the files would be downloaded straight to the network folder and executed from there.

    .PARAMETER NoPendingRenameCheck
        Disables pending rename validation when checking for a pending reboot.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ExtractPath
        Lets you specify a location to extract the update file to on the system requiring the update. e.g. C:\temp

    .LINK
        https://dbatools.io/Update-DbaInstance

    .NOTES
        Tags: Deployment, Install, Patching, Update
        Author: Kirill Kravtsov (@nvarscar) https://nvarscar.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Local Admin rights on destination computer(s).

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -Version SP3 -Path \\network\share

        Updates all applicable SQL Server installations on SQL1 to SP3.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Prompts for confirmation before the update.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1, SQL2 -Restart -Path \\network\share -Confirm:$false

        Updates all applicable SQL Server installations on SQL1 and SQL2 with the most recent patch.
        It will install latest ServicePack, restart the computers, install latest Cumulative Update, and finally restart the computer once again.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -Version 2012 -Type ServicePack -Path \\network\share

        Updates SQL Server 2012 on SQL1 with the most recent ServicePack found in your patch repository.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Prompts for confirmation before the update.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -KB 123456 -Restart -Path \\network\share -Confirm:$false

        Installs KB 123456 on SQL1 and restarts the computer.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName Server1 -Version SQL2012SP3, SQL2016SP2CU3 -Path \\network\share -Restart -Confirm:$false

        Updates SQL 2012 to SP3 and SQL 2016 to SP2CU3 on Server1. Each update will be followed by a restart.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName Server1 -Path \\network\share -Restart -Confirm:$false -ExtractPath "C:\temp"

        Updates all applicable SQL Server installations on Server1 with the most recent patch. Each update will be followed by a restart.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.
        Does not prompt for confirmation.
        Extracts the files in local driver on Server1 C:\temp.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName Server1 -Path \\network\share -ArgumentList "/SkipRules=RebootRequiredCheck"

        Updates all applicable SQL Server installations on Server1 with the most recent patch.
        Additional command line parameters would be passed to the executable.
        Binary files for the update will be searched among all files and folders recursively in \\network\share.

    .EXAMPLE
        PS C:\> Update-DbaInstance -ComputerName SQL1 -Version CU3 -Download -Path \\network\share -Confirm:$false

        Downloads an appropriate CU KB to \\network\share and installs it onto SQL1.
        Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Version')]
    Param (
        [parameter(ValueFromPipeline, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [Parameter(ParameterSetName = 'Version')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Version,
        [Parameter(ParameterSetName = 'Version')]
        [ValidateSet('All', 'ServicePack', 'CumulativeUpdate')]
        [string[]]$Type = @('All'),
        [Parameter(Mandatory, ParameterSetName = 'KB')]
        [ValidateNotNullOrEmpty()]
        [string[]]$KB,
        [Alias("Instance")]
        [string]$InstanceName,
        [string[]]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerUpdates'),
        [switch]$Restart,
        [switch]$Continue,
        [ValidateNotNull()]
        [int]$Throttle = 50,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = @('Credssp', 'Default')[$null -eq $Credential],
        [string]$ExtractPath,
        [string[]]$ArgumentList,
        [switch]$Download,
        [switch]$NoPendingRenameCheck = (Get-DbatoolsConfigValue -Name 'OS.PendingRename' -Fallback $false),
        [switch]$EnableException

    )
    begin {
        $notifiedCredentials = $false
        $notifiedUnsecure = $false
        #Validating parameters
        if ($PSCmdlet.ParameterSetName -eq 'Version') {
            foreach ($v in $Version) {
                if ($v -notmatch '^((SQL)?\d{4}(R2)?)?\s*(RTM|SP\d+)?\s*(CU\d+)?$') {
                    Stop-Function -Category InvalidArgument -Message "$Version is an incorrect Version value, please refer to Get-Help Update-DbaInstance -Parameter Version"
                    return
                }
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'KB') {
            $kbList = @()
            foreach ($kbItem in $KB) {
                if ($kbItem -match '^(KB)?(\d+)$') {
                    $kbList += $Matches[2]
                } else {
                    Stop-Function -Category InvalidArgument -Message "$kbItem is an incorrect KB value, please refer to Get-Help Update-DbaInstance -Parameter KB"
                    return
                }
            }
        }
        $actions = @()
        $actionTemplate = @{ }
        if ($InstanceName) { $actionTemplate.InstanceName = $InstanceName }
        if ($Continue) { $actionTemplate.Continue = $Continue }
        #Putting together list of actions based on current ParameterSet
        if ($PSCmdlet.ParameterSetName -eq 'Version') {
            if ($Type -contains 'All') { $typeList = @('ServicePack', 'CumulativeUpdate') }
            else { $typeList = $Type | Sort-Object -Descending }
            foreach ($ver in $Version) {
                $currentAction = $actionTemplate.Clone()
                if ($ver -and $ver -match '^(SQL)?(\d{4}(R2)?)?\s*(RTM|SP)?(\d+)?(CU)?(\d+)?') {
                    $majorV, $spV, $cuV = $Matches[2, 5, 7]
                    Write-Message -Level Debug -Message "Parsed Version as Major $majorV SP $spV CU $cuV"
                    # Add appropriate fields to the splat
                    # Add version to every field
                    if ($null -ne $majorV) {
                        $currentAction += @{
                            MajorVersion = $majorV
                        }
                        # When version is the only thing that is specified, we want all the types added
                        if ($null -eq $spV -and $null -eq $cuV) {
                            foreach ($currentType in $typeList) {
                                $actions += $currentAction.Clone() + @{ Type = $currentType }
                            }
                        }
                    }
                    #when SP# is specified
                    if ($null -ne $spV) {
                        $currentAction += @{
                            ServicePack = $spV
                        }
                        # ignore SP0 and trigger only when SP is in Type
                        if ($spV -ne '0' -and 'ServicePack' -in $typeList) {
                            $actions += $currentAction.Clone()
                        }
                    }
                    # When CU# is specified, but ignore CU0 and trigger only when CU is in Type
                    if ($null -ne $cuV -and $cuV -ne '0' -and 'CumulativeUpdate' -in $typeList) {
                        $actions += $currentAction.Clone() + @{ CumulativeUpdate = $cuV }
                    }
                } else {
                    Stop-Function -Category InvalidArgument -Message "$ver is an incorrect Version value, please refer to Get-Help Update-DbaInstance -Parameter Version"
                    return
                }
            }
            # If no version specified, simply apply latest $currentType
            if (!$Version) {
                foreach ($currentType in $typeList) {
                    $currentAction = $actionTemplate.Clone() + @{
                        Type = $currentType
                    }
                    $actions += $currentAction
                }
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'KB') {
            foreach ($kbItem in $kbList) {
                $currentAction = $actionTemplate.Clone() + @{
                    KB = $kbItem
                }
                $actions += $currentAction
            }
        }
        # debug message
        foreach ($a in $actions) {
            Write-Message -Level Debug -Message "Added installation action $($a | ConvertTo-Json -Depth 1 -Compress)"
        }
        # defining how to process the final results
        $outputHandler = {
            $_ | Select-DefaultView -Property ComputerName, MajorVersion, TargetLevel, KB, Successful, Restarted, InstanceName, Installer, Notes
            if ($_.Successful -eq $false) {
                Write-Message -Level Warning -Message "Update failed: $($_.Notes -join ' | ')"
            }
        }
        function Join-AdminUnc {
            <#
                .SYNOPSIS
                Internal function. Parses a path to make it an admin UNC.
            #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [DbaInstanceParameter]$ComputerName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Path

            )
            if ($Path.StartsWith("\\")) {
                return $filepath
            }

            $servername = $ComputerName.ComputerName
            $newpath = Join-Path "\\$servername\" $Path.replace(':', '$')
            return $newpath
        }
        function Copy-UncFile {
            <#

                SYNOPSIS
                Internal function. Uses PSDrive to copy file to the remote system.

                #>
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [DbaInstanceParameter]$ComputerName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Path,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Destination,

                [PSCredential]$Credential
            )
            if (([DbaInstanceParameter]$groupItem.ComputerName).IsLocalHost) {
                $remoteFolder = $Destination
            } else {
                $uncFileName = Join-AdminUnc -ComputerName $ComputerName -Path $Destination
                $driveSplat = @{
                    Name       = 'UpdateCopy'
                    Root       = $uncFileName
                    PSProvider = 'FileSystem'
                    Credential = $Credential
                }
                $null = New-PSDrive @driveSplat -ErrorAction Stop
                $remoteFolder = 'UpdateCopy:\'
            }
            try {
                Copy-Item -Path $Path -Destination $remoteFolder -ErrorAction Stop
            } finally {
                if (-Not ([DbaInstanceParameter]$groupItem.ComputerName).IsLocalHost) {
                    $null = Remove-PSDrive -Name UpdateCopy -Force
                }
            }
        }
        function Test-NetworkPath {
            <#

            SYNOPSIS
            Internal function. Tests if a path is a network path

            #>
            param (
                [Parameter(ValueFromPipeline)]
                [string]$Path
            )
            begin { $pathList = @() }
            process { $pathList += $Path -like '\\*' }
            end { return $pathList -contains $true }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        if ($Path) {
            $Path = $Path.TrimEnd("/\")
        }
        #Resolve all the provided names
        $resolvedComputers = @()
        $pathIsNetwork = $Path | Test-NetworkPath
        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            if (-not $computer.IsLocalHost -and -not $notifiedCredentials -and -not $Credential -and $pathIsNetwork) {
                Write-Message -Level Warning -Message "Explicit -Credential might be required when running agains remote hosts and -Path is a network folder"
                $notifiedCredentials = $true
            }
            if ($resolvedComputer = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential) {
                $resolvedComputers += $resolvedComputer.FullComputerName
            }
        }
        #Leave only unique computer names
        $resolvedComputers = $resolvedComputers | Sort-Object -Unique
        #Process planned actions and gather installation actions
        $installActions = @()
        $downloads = @()
        :computers foreach ($resolvedName in $resolvedComputers) {
            $activity = "Preparing to update SQL Server on $resolvedName"
            ## Find the current version on the computer
            Write-ProgressHelper -ExcludePercent -Activity $activity -StepNumber 0 -Message "Gathering all SQL Server instance versions"
            try {
                $components = Get-SQLInstanceComponent -ComputerName $resolvedName -Credential $Credential
            } catch {
                Stop-Function -Message "Error while looking for SQL Server installations on $resolvedName" -Continue -ErrorRecord $_
            }
            if (!$components) {
                Stop-Function -Message "No SQL Server installations found on $resolvedName" -Continue
            }
            Write-Message -Level Debug -Message "Found $(($components | Measure-Object).Count) existing SQL Server instance components: $(($components | ForEach-Object { "$($_.InstanceName)($($_.InstanceType) $($_.Version.NameLevel))" }) -join ',')"
            # Filter for specific instance name
            if ($InstanceName) {
                $components = $components | Where-Object { $_.InstanceName -eq $InstanceName }
            }
            try {
                $restartNeeded = Test-PendingReboot -ComputerName $resolvedName -Credential $Credential
            } catch {
                Stop-Function -Message "Failed to get reboot status from $resolvedName" -Continue -ErrorRecord $_
            }
            if ($restartNeeded -and (-not $Restart -or ([DbaInstanceParameter]$resolvedName).IsLocalHost)) {
                #Exit the actions loop altogether - nothing can be installed here anyways
                Stop-Function -Message "$resolvedName is pending a reboot. Reboot the computer before proceeding." -Continue
            }
            # test connection
            if ($Credential -and -not ([DbaInstanceParameter]$resolvedName).IsLocalHost) {
                $totalSteps += 1
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Testing $Authentication protocol"
                Write-Message -Level Verbose -Message "Attempting to test $Authentication protocol for remote connections"
                try {
                    $connectSuccess = Invoke-Command2 -ComputerName $resolvedName -Credential $Credential -Authentication $Authentication -ScriptBlock { $true } -Raw
                } catch {
                    $connectSuccess = $false
                }
                # if we use CredSSP, we might be able to configure it
                if (-not $connectSuccess -and $Authentication -eq 'Credssp') {
                    $totalSteps += 1
                    Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Configuring CredSSP protocol"
                    Write-Message -Level Verbose -Message "Attempting to configure CredSSP for remote connections"
                    try {
                        Initialize-CredSSP -ComputerName $resolvedName -Credential $Credential -EnableException $true
                        $connectSuccess = Invoke-Command2 -ComputerName $resolvedName -Credential $Credential -Authentication $Authentication -ScriptBlock { $true } -Raw
                    } catch {
                        $connectSuccess = $false
                        # tell the user why we could not configure CredSSP
                        Write-Message -Level Warning -Message $_
                    }
                }
                # in case we are still not successful, ask the user to use unsecure protocol once
                if (-not $connectSuccess -and -not $notifiedUnsecure) {
                    if ($PSCmdlet.ShouldProcess($resolvedName, "Primary protocol ($Authentication) failed, sending credentials via potentially unsecure protocol")) {
                        $notifiedUnsecure = $true
                    } else {
                        Stop-Function -Message "Failed to connect to $resolvedName through $Authentication protocol. No actions will be performed on that computer." -Continue -ContinueLabel computers
                    }
                }
            }
            $upgrades = @()
            :actions foreach ($actionItem in $actions) {
                # Clone action to use as a splat
                $currentAction = $actionItem.Clone()
                # Pass only relevant components
                if ($currentAction.MajorVersion) {
                    Write-Message -Level Debug -Message "Limiting components to version $($currentAction.MajorVersion)"
                    $selectedComponents = $components | Where-Object { $_.Version.NameLevel -contains $currentAction.MajorVersion }
                    $currentAction.Remove('MajorVersion')
                } else {
                    $selectedComponents = $components
                }
                Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Looking for a KB file for a chosen version"
                Write-Message -Level Debug -Message "Looking for appropriate KB file on $resolvedName with following params: $($currentAction | ConvertTo-Json -Depth 1 -Compress)"
                # get upgrade details for each component
                $upgradeDetails = Get-SqlInstanceUpdate @currentAction -ComputerName $resolvedName -Credential $Credential -Component $selectedComponents
                if ($upgradeDetails.Successful -contains $false) {
                    #Exit the actions loop altogether - upgrade cannot be performed
                    $upgradeDetails
                    Stop-Function -Message "Update cannot be applied to $resolvedName | $($upgradeDetails.Notes -join ' | ')" -Continue -ContinueLabel computers
                }

                foreach ($detail in $upgradeDetails) {
                    # search for installer for each target upgrade
                    $kbLookupParams = @{
                        ComputerName   = $resolvedName
                        Credential     = $Credential
                        Authentication = $Authentication
                        Architecture   = $detail.Architecture
                        MajorVersion   = $detail.MajorVersion
                        Path           = $Path
                        KB             = $detail.KB
                    }
                    try {
                        $installer = Find-SqlInstanceUpdate @kbLookupParams
                    } catch {
                        Stop-Function -Message "Failed to enumerate files in -Path" -ErrorRecord $_ -Continue
                    }
                    if ($installer) {
                        $detail.Installer = $installer.FullName
                    } elseif ($Download) {
                        $downloads += [PSCustomObject]@{ KB = $detail.KB; Architecture = $detail.Architecture }
                    } else {
                        Stop-Function -Message "Could not find installer for the SQL$($detail.MajorVersion) update KB$($detail.KB)" -Continue
                    }
                    # update components to mirror the updated version - will be used for multi-step upgrades
                    foreach ($component in $components) {
                        if ($component.Version.NameLevel -eq $detail.TargetVersion.NameLevel) {
                            $component.Version = $detail.TargetVersion
                        }
                    }
                    # finally, add the upgrade details to the upgrade list
                    $upgrades += $detail
                }
            }
            if ($upgrades) {
                Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Preparing installation"
                $chosenVersions = ($upgrades | ForEach-Object { "$($_.MajorVersion) to $($_.TargetLevel) (KB$($_.KB))" }) -join ', '
                if ($PSCmdlet.ShouldProcess($resolvedName, "Update $chosenVersions")) {
                    $installActions += [pscustomobject]@{
                        ComputerName = $resolvedName
                        Actions      = $upgrades
                    }
                }
            }
            Write-Progress -Activity $activity -Completed
        }
        # Download and distribute updates if needed
        $downloadedKbs = @()
        $mainPathIsNetwork = $Path[0] | Test-NetworkPath
        foreach ($kbItem in $downloads | Select-Object -Unique -Property KB, Architecture) {
            if ($mainPathIsNetwork) {
                $downloadPath = $Path[0]
            } else {
                $downloadPath = [System.IO.Path]::GetTempPath()
            }
            try {
                $downloadedKbs += [PSCustomObject]@{
                    FileItem     = Save-DbaKbUpdate -Name $kbItem.KB -Path $downloadPath -Architecture $kbItem.Architecture -EnableException
                    KB           = $kbItem.KB
                    Architecture = $kbItem.Architecture
                }
            } catch {
                Stop-Function -Message "Could not download installer for KB$($kbItem.KB)($($kbItem.Architecture)): $_" -Continue
            }
        }
        # if path is not on the network, upload the patch to each remote computer
        if ($downloadedKbs) {
            # find unique KB/Architecture combos without an Installer
            $groupedRequirements = $installActions | ForEach-Object { foreach ($action in $_.Actions | Where-Object { -Not $_.Installer }) { [PSCustomObject]@{ComputerName = $_.ComputerName; KB = $action.KB; Architecture = $action.Architecture } } } | Group-Object -Property KB, Architecture

            # for each such combo, .Installer paths need to be updated and, potentially, files copied
            foreach ($groupKB in $groupedRequirements) {
                $fileItem = ($downloadedKbs | Where-Object { $_.KB -eq $groupKB.Values[0] -and $_.Architecture -eq $groupKB.Values[1] }).FileItem
                $filePath = Join-Path $Path[0] $fileItem.Name
                foreach ($groupItem in $groupKB.Group) {
                    if (-Not $mainPathIsNetwork) {
                        # For each KB, copy the file to the remote (or local) server
                        try {
                            $null = Copy-UncFile -ComputerName $groupItem.ComputerName -Path $fileItem.FullName -Destination $Path[0] -Credential $Credential
                        } catch {
                            Stop-Function -Message "Could not move installer $($fileItem.FullName) to $($Path[0]) on $($groupItem.ComputerName): $_" -Continue
                        }
                    }
                    # Update appropriate action
                    $installAction = $installActions | Where-Object ComputerName -EQ $groupItem.ComputerName
                    $action = $installAction.Actions | Where-Object { $_.KB -eq $groupItem.KB -and $_.Architecture -eq $groupItem.Architecture }
                    $action.Installer = $filePath
                }

            }
            if (-Not $mainPathIsNetwork) {
                # remove temp files
                foreach ($downloadedKb in $downloadedKbs) {
                    $null = Remove-Item $downloadedKb.FileItem.FullName -Force
                }
            }
        }

        # Declare the installation script
        $installScript = {
            $updateSplat = @{
                ComputerName         = $_.ComputerName
                Action               = $_.Actions
                Restart              = $Restart
                Credential           = $Credential
                EnableException      = $EnableException
                ExtractPath          = $ExtractPath
                Authentication       = $Authentication
                ArgumentList         = $ArgumentList
                NoPendingRenameCheck = $NoPendingRenameCheck
            }
            Invoke-DbaAdvancedUpdate @updateSplat
        }
        # check how many computers we are looking at and decide upon parallelism
        if ($installActions.Count -eq 1) {
            $installActions | ForEach-Object -Process $installScript | ForEach-Object -Process $outputHandler
        } elseif ($installActions.Count -ge 2) {
            $installActions | Invoke-Parallel -ImportModules -ImportVariables -ScriptBlock $installScript -Throttle $Throttle | ForEach-Object -Process $outputHandler
        }
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUBUExiAKGEsoRjG6wqJqU7GNU
# Y4igghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFLRLTj5jFDaHCNnJeIcTosPT1ooqMA0G
# CSqGSIb3DQEBAQUABIIBAEQrmT1tz+3vbJPsqhlCJUt21G9pLsC61nuV59B6M+Y0
# pAP8MPeUHLoY/1GH+icL6MSZORjneqL4WhtzhOfIUef7/Hg7yUF5vK8781Eraasl
# vWU9J2HLlXTHCPrwFYIDXYC9hXyaqozcrgsXqUJtTl4d/auDHVRiXyQ7kEQ+hd/Z
# p4oylBauZUKi4T63TTRUr5g3lN3JLwCSiN75ueSqq8Kvzm2gpqjvPXfz+lYUeLdI
# sV/Zn38KiNitRER2NUOP5PzOzB7wCWuFKb6Z6FFE/4nskpayXTPvKz3AB4QH07Vf
# yX03rFQoKGkYR3Z7K5wVIBYeEorgiaiVURTMSYKITYKhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDMyWjAvBgkqhkiG9w0BCQQxIgQg/bz6wNWDjsM32Ib7uAwO
# ARWMo4OKBUfOtI87+CQCQ+YwDQYJKoZIhvcNAQEBBQAEggIAabdrHQA3isOL56JI
# KoC5DNNiyu1x0N795DCFrSlChB19nNNLaRvcXh2ubUoUjn8N3V5OrGhFRyZ/fvfw
# mWkAbZob3ImujVieMEWslT+KrSgdwB3joAXOWJUgOdKz8kckaBr0Gd0K4e7P0aiK
# IZesKSd2VByuk0Kl4KE5E7D3/6kDKuSSrBvuGMQSijxrJ7wie5KkiQVj4oWmDeR2
# NJ2LkGtAackAEKfNdhJaSjrDqH/lNp4+7RWIBxP/+j35f6om50cHqlQwBVu8OcfQ
# 7b0WX7as9Twt0ngOfLDNfiWH2gKxXZny4bQDOcc1GoGKbN0otl4j3TlSiuETgAib
# LR1yZjDwPumTKGy+bcRljoNR2tV7f6w51EuTZBg153z3D5OlUdEHn+V/X/PJ/vfh
# F0spmAOlkza13lFSWzNIBneOzbHBEHz2H/W3nQpYTT7zp76y3h4XQb9mEdP529M1
# Vo5TBwgugN+FmfCcxWlPMEVh6hXXj0SaidFUVZII7FNwx4auwGtJeoLfVrwgyn5e
# lrXiTSNK0vanD7UDp/VTJcI16fDMIo9JE+nX8F3Ki0pOOD9M0Qp1RiWzUIvdFKqN
# wAWFuqHCn6WV/jqpbxPp/BKfOQtqBmdHY8IW+8ztnxGQHV8qtfA2KLaFL+JqOXV6
# 2hSn1AY0AcZRBpw5x9RhfGjcvq0=
# SIG # End signature block
