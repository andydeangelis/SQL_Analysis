if (-not $ExecutionContext.SessionState.InvokeCommand.GetCommand('Register-ArgumentCompleter','Function,Cmdlet')) {

    #############################################################################
    #
    # TabExpansionPlusPlus
    #
    #

    <#
Copyright (c) 2013, Jason Shirk
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

    #>

    # Save off the previous tab completion so it can be restored if this module
    # is removed.
    $oldTabExpansion = $function:TabExpansion
    $oldTabExpansion2 = $function:TabExpansion2

    [bool]$updatedTypeData = $false


    #region Exported utility functions for completers

    #############################################################################
    #
    # Helper function to create a new completion results
    #
    function New-CompletionResult {
        param ([Parameter(ValueFromPipelineByPropertyName, Mandatory, ValueFromPipeline)]
            [ValidateNotNullOrEmpty()]
            [string]
            $CompletionText,

            [Parameter(Position = 1, ValueFromPipelineByPropertyName)]
            [string]
            $ToolTip,

            [Parameter(Position = 2, ValueFromPipelineByPropertyName)]
            [string]
            $ListItemText,

            [System.Management.Automation.CompletionResultType]
            $CompletionResultType = [System.Management.Automation.CompletionResultType]::ParameterValue,

            [switch]
            $NoQuotes = $false
        )

        process {
            $toolTipToUse = if ($ToolTip -eq '') { $CompletionText }
            else { $ToolTip }
            $listItemToUse = if ($ListItemText -eq '') { $CompletionText }
            else { $ListItemText }

            # If the caller explicitly requests that quotes
            # not be included, via the -NoQuotes parameter,
            # then skip adding quotes.

            if ($CompletionResultType -eq [System.Management.Automation.CompletionResultType]::ParameterValue -and -not $NoQuotes) {
                # Add single quotes for the caller in case they are needed.
                # We use the parser to robustly determine how it will treat
                # the argument.  If we end up with too many tokens, or if
                # the parser found something expandable in the results, we
                # know quotes are needed.

                $tokens = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput("echo $CompletionText", [ref]$tokens, [ref]$null)
                if ($tokens.Length -ne 3 -or
                    ($tokens[1] -is [System.Management.Automation.Language.StringExpandableToken] -and
                        $tokens[1].Kind -eq [System.Management.Automation.Language.TokenKind]::Generic)) {
                    $CompletionText = "'$CompletionText'"
                }
            }
            return New-Object System.Management.Automation.CompletionResult `
            ($CompletionText, $listItemToUse, $CompletionResultType, $toolTipToUse.Trim())
        }

    }

    #############################################################################
    #
    # .SYNOPSIS
    #
    #     This is a simple wrapper of Get-Command gets commands with a given
    #     parameter ignoring commands that use the parameter name as an alias.
    #
    function Get-CommandWithParameter {
        [CmdletBinding(DefaultParameterSetName = 'AllCommandSet')]
        param (
            [Parameter(ParameterSetName = 'AllCommandSet', ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [ValidateNotNullOrEmpty()]
            [string[]]
            ${Name},

            [Parameter(ParameterSetName = 'CmdletSet', ValueFromPipelineByPropertyName)]
            [string[]]
            ${Verb},

            [Parameter(ParameterSetName = 'CmdletSet', ValueFromPipelineByPropertyName)]
            [string[]]
            ${Noun},

            [Parameter(ValueFromPipelineByPropertyName)]
            [string[]]
            ${Module},

            [ValidateNotNullOrEmpty()]
            [Parameter(Mandatory)]
            [string]
            ${ParameterName})

        begin {
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Get-Command', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = { & $wrappedCmd @PSBoundParameters | Where-Object { $_.Parameters[$ParameterName] -ne $null } }
            $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
            $steppablePipeline.Begin($PSCmdlet)
        }
        process {
            $steppablePipeline.Process($_)
        }
        end {
            $steppablePipeline.End()
        }
    }

    #############################################################################
    #
    function Set-CompletionPrivateData {
        param (
            [ValidateNotNullOrEmpty()]
            [string]
            $Key,

            [object]
            $Value,

            [ValidateNotNullOrEmpty()]
            [int]
            $ExpirationSeconds = 604800
        )

        $Cache = [PSCustomObject]@{
            Value          = $Value
            ExpirationTime = (Get-Date).AddSeconds($ExpirationSeconds)
        }
        $completionPrivateData[$key] = $Cache
    }

    #############################################################################
    #
    function Get-CompletionPrivateData {
        param (
            [ValidateNotNullOrEmpty()]
            [string]
            $Key)

        if (!$Key)
        { return $completionPrivateData }

        $cacheValue = $completionPrivateData[$key]
        if ((Get-Date) -lt $cacheValue.ExpirationTime) {
            return $cacheValue.Value
        }
    }

    #############################################################################
    #
    function Get-CompletionWithExtension {
        param ([string]
            $lastWord,

            [string[]]
            $extensions)

        [System.Management.Automation.CompletionCompleters]::CompleteFilename($lastWord) |
            Where-Object {
            # Use ListItemText because it won't be quoted, CompletionText might be
            [System.IO.Path]::GetExtension($_.ListItemText) -in $extensions
        }
    }

    #############################################################################
    #
    function New-CommandTree {
        [CmdletBinding(DefaultParameterSetName = 'Default')]
        param (
            [Parameter(Mandatory, ParameterSetName = 'Default')]
            [Parameter(Mandatory, ParameterSetName = 'Argument')]
            [ValidateNotNullOrEmpty()]
            [string]
            $Completion,

            [Parameter(Position = 1, Mandatory, ParameterSetName = 'Default')]
            [Parameter(Position = 1, Mandatory, ParameterSetName = 'Argument')]
            [string]
            $Tooltip,

            [Parameter(ParameterSetName = 'Argument')]
            [switch]
            $Argument,

            [Parameter(Position = 2, ParameterSetName = 'Default')]
            [Parameter(Position = 1, ParameterSetName = 'ScriptBlockSet')]
            [scriptblock]
            $SubCommands,

            [Parameter(Mandatory, ParameterSetName = 'ScriptBlockSet')]
            [scriptblock]
            $CompletionGenerator
        )

        $actualSubCommands = $null
        if ($null -ne $SubCommands) {
            $actualSubCommands = [NativeCommandTreeNode[]](& $SubCommands)
        }

        switch ($PSCmdlet.ParameterSetName) {
            'Default' {
                New-Object NativeCommandTreeNode $Completion, $Tooltip, $actualSubCommands
                break
            }
            'Argument' {
                New-Object NativeCommandTreeNode $Completion, $Tooltip, $true
            }
            'ScriptBlockSet' {
                New-Object NativeCommandTreeNode $CompletionGenerator, $actualSubCommands
                break
            }
        }
    }

    #############################################################################
    #
    function Get-CommandTreeCompletion {
        param ($wordToComplete,

            $commandAst,

            [NativeCommandTreeNode[]]
            $CommandTree)

        $commandElements = $commandAst.CommandElements

        # Skip the first command element - it's the command name
        # Iterate through the remaining elements, stopping early
        # if we find the element that matches $wordToComplete.
        for ($i = 1; $i -lt $commandElements.Count; $i++) {
            if (!($commandElements[$i] -is [System.Management.Automation.Language.StringConstantExpressionAst])) {
                # Ignore arguments that are expressions.  In some rare cases this
                # could cause strange completions because the context is incorrect, e.g.:
                #    $c = 'advfirewall'
                #    netsh $c firewall
                # Here we would be in advfirewall firewall context, but we'd complete as
                # though we were in firewall context.
                continue
            }

            if ($commandElements[$i].Value -eq $wordToComplete) {
                $CommandTree = $CommandTree |
                    Where-Object { $_.Command -like "$wordToComplete*" -or $_.CompletionGenerator -ne $null }
                break
            }

            foreach ($subCommand in $CommandTree) {
                if ($subCommand.Command -eq $commandElements[$i].Value) {
                    if (!$subCommand.Argument) {
                        $CommandTree = $subCommand.SubCommands
                    }
                    break
                }
            }
        }

        if ($null -ne $CommandTree) {
            $CommandTree | ForEach-Object {
                if ($_.Command) {
                    $toolTip = if ($_.Tooltip) { $_.Tooltip }
                    else { $_.Command }
                    New-CompletionResult -CompletionText $_.Command -ToolTip $toolTip
                } else {
                    & $_.CompletionGenerator $wordToComplete $commandAst
                }
            }
        }
    }

    #endregion Exported utility functions for completers

    #region Exported functions

    #############################################################################
    #
    # .SYNOPSIS
    #     Register a ScriptBlock to perform argument completion for a
    #     given command or parameter.
    #
    # .DESCRIPTION
    #     Argument completion can be extended without needing to do any
    #     parsing in many cases. By registering a handler for specific
    #     commands and/or parameters, PowerShell will call the handler
    #     when appropriate.
    #
    #     There are 2 kinds of extensions - native and PowerShell. Native
    #     refers to commands external to PowerShell, e.g. net.exe. PowerShell
    #     completion covers any functions, scripts, or cmdlets where PowerShell
    #     can determine the correct parameter being completed.
    #
    #     When registering a native handler, you must specify the CommandName
    #     parameter. The CommandName is typically specified without any path
    #     or extension. If specifying a path and/or an extension, completion
    #     will only work when the command is specified that way when requesting
    #     completion.
    #
    #     When registering a PowerShell handler, you must specify the
    #     ParameterName parameter. The CommandName is optional - PowerShell will
    #     first try to find a handler based on the command and parameter, but
    #     if none is found, then it will try just the parameter name. This way,
    #     you could specify a handler for all commands that have a specific
    #     parameter.
    #
    #     A handler needs to return instances of
    #     System.Management.Automation.CompletionResult.
    #
    #     A native handler is passed 2 parameters:
    #
    #         param($wordToComplete, $commandAst)
    #
    #     $wordToComplete  - The argument being completed, possibly an empty string
    #     $commandAst      - The ast of the command being completed.
    #
    #     A PowerShell handler is passed 5 parameters:
    #
    #         param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    #
    #     $commandName        - The command name
    #     $parameterName      - The parameter name
    #     $wordToComplete     - The argument being completed, possibly an empty string
    #     $commandAst         - The parsed representation of the command being completed.
    #     $fakeBoundParameter - Like $PSBoundParameters, contains values for some of the parameters.
    #                           Certain values are not included, this does not mean a parameter was
    #                           not specified, just that getting the value could have had unintended
    #                           side effects, so no value was computed.
    #
    # .PARAMETER ParameterName
    #     The name of the parameter that the Completion parameter supports.
    #     This parameter is not supported for native completion and is
    #     mandatory for script completion.
    #
    # .PARAMETER CommandName
    #     The name of the command that the Completion parameter supports.
    #     This parameter is mandatory for native completion and is optional
    #     for script completion.
    #
    # .PARAMETER Completion
    #     A ScriptBlock that returns instances of CompletionResult. For
    #     native completion, the script block parameters are
    #
    #         param($wordToComplete, $commandAst)
    #
    #     For script completion, the parameters are:
    #
    #         param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    #
    # .PARAMETER Description
    #     A description of how the completion can be used.
    #
    function Register-ArgumentCompleter {
        [CmdletBinding(DefaultParameterSetName = "PowerShellSet")]
        param (
            [Parameter(ParameterSetName = "NativeSet", Mandatory)]
            [Parameter(ParameterSetName = "PowerShellSet")]
            [string[]]
            $CommandName = "",

            [Parameter(ParameterSetName = "PowerShellSet", Mandatory)]
            [string]
            $ParameterName = "",

            [Parameter(Mandatory)]
            [scriptblock]
            $ScriptBlock,

            [string]
            $Description,

            [Parameter(ParameterSetName = "NativeSet")]
            [switch]
            $Native)

        $fnDefn = $ScriptBlock.Ast -as [System.Management.Automation.Language.FunctionDefinitionAst]
        if (!$Description) {
            # See if the script block is really a function, if so, use the function name.
            $Description = if ($fnDefn -ne $null) { $fnDefn.Name }
            else { "" }
        }

        if ($MyInvocation.ScriptName -ne (& { $MyInvocation.ScriptName })) {
            # Make an unbound copy of the script block so it has access to TabExpansionPlusPlus when invoked.
            # We can skip this step if we created the script block (Register-ArgumentCompleter was
            # called internally).
            if ($fnDefn -ne $null) {
                $ScriptBlock = $ScriptBlock.Ast.Body.GetScriptBlock() # Don't reparse, just get a new ScriptBlock.
            } else {
                $ScriptBlock = $ScriptBlock.Ast.GetScriptBlock() # Don't reparse, just get a new ScriptBlock.
            }
        }

        foreach ($command in $CommandName) {
            if ($command -and $ParameterName) {
                $command += ":"
            }

            $key = if ($Native) { 'NativeArgumentCompleters' }
            else { 'CustomArgumentCompleters' }
            $tabExpansionOptions[$key]["${command}${ParameterName}"] = $ScriptBlock

            $tabExpansionDescriptions["${command}${ParameterName}$Native"] = $Description
        }
    }

    #############################################################################
    #
    # .SYNOPSIS
    #     Tests the registered argument completer
    #
    # .DESCRIPTION
    #     Invokes the registered parameteter completer for a specified command to make it easier to test
    #     a completer
    #
    # .EXAMPLE
    #  Test-ArgumentCompleter -CommandName Get-Verb -ParameterName Verb -WordToComplete Sta
    #
    # Test what would be completed if Get-Verb -Verb Sta<Tab> was typed at the prompt
    #
    # .EXAMPLE
    #  Test-ArgumentCompleter -NativeCommand Robocopy -WordToComplete /
    #
    # Test what would be completed if Robocopy /<Tab> was typed at the prompt
    #
    function Test-ArgumentCompleter {
        [CmdletBinding(DefaultParametersetName = 'PS')]
        param
        (
            [Parameter(Mandatory, Position = 1, ParameterSetName = 'PS')]
            [string]
            $CommandName
            ,

            [Parameter(Mandatory, Position = 2, ParameterSetName = 'PS')]
            [string]
            $ParameterName
            ,

            [Parameter(ParameterSetName = 'PS')]
            [System.Management.Automation.Language.CommandAst]
            $commandAst
            ,

            [Parameter(ParameterSetName = 'PS')]
            [Hashtable]
            $FakeBoundParameters = @{ }
            ,

            [Parameter(Mandatory, Position = 1, ParameterSetName = 'NativeCommand')]
            [string]
            $NativeCommand
            ,

            [Parameter(Position = 2, ParameterSetName = 'NativeCommand')]
            [Parameter(Position = 3, ParameterSetName = 'PS')]
            [string]
            $WordToComplete = ''

        )

        if ($PSCmdlet.ParameterSetName -eq 'NativeCommand') {
            $Tokens = $null
            $Errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($NativeCommand, [ref]$Tokens, [ref]$Errors)
            $commandAst = $ast.EndBlock.Statements[0].PipelineElements[0]
            $command = $commandAst.GetCommandName()
            $completer = $tabExpansionOptions.NativeArgumentCompleters[$command]
            if (-not $Completer) {
                throw "No argument completer registered for command '$Command' (from $NativeCommand)"
            }
            & $completer $WordToComplete $commandAst
        } else {
            $completer = $tabExpansionOptions.CustomArgumentCompleters["${CommandName}:$ParameterName"]
            if (-not $Completer) {
                throw "No argument completer registered for '${CommandName}:$ParameterName'"
            }
            & $completer $CommandName $ParameterName $WordToComplete $commandAst $FakeBoundParameters
        }
    }

    #############################################################################
    #
    # .SYNOPSIS
    # Retrieves a list of argument completers that have been loaded into the
    # PowerShell session.
    #
    # .PARAMETER Name
    # The name of the argument complete to retrieve. This parameter supports
    # wildcards (asterisk).
    #
    # .EXAMPLE
    # Get-ArgumentCompleter -Name *Azure*;
    function Get-ArgumentCompleter {
        [CmdletBinding()]
        param ([string[]]
            $Name = '*')

        if (!$updatedTypeData) {
            # Define the default display properties for the objects returned by Get-ArgumentCompleter
            [string[]]$properties = "Command", "Parameter"
            Update-TypeData -TypeName 'TabExpansionPlusPlus.ArgumentCompleter' -DefaultDisplayPropertySet $properties -Force
            $updatedTypeData = $true
        }

        function WriteCompleters {
            function WriteCompleter($command, $parameter, $native, $scriptblock) {
                foreach ($n in $Name) {
                    if ($command -like $n) {
                        $c = $command
                        if ($command -and $parameter) { $c += ':' }
                        $description = $tabExpansionDescriptions["${c}${parameter}${native}"]
                        $completer = [pscustomobject]@{
                            Command     = $command
                            Parameter   = $parameter
                            Native      = $native
                            Description = $description
                            ScriptBlock = $scriptblock
                            File        = if ($scriptblock.File) { Split-Path -Leaf -Path $scriptblock.File }
                        }

                        $completer.PSTypeNames.Add('TabExpansionPlusPlus.ArgumentCompleter')
                        Write-Output $completer

                        break
                    }
                }
            }

            foreach ($pair in $tabExpansionOptions.CustomArgumentCompleters.GetEnumerator()) {
                if ($pair.Key -match '^(.*):(.*)$') {
                    $command = $matches[1]
                    $parameter = $matches[2]
                } else {
                    $parameter = $pair.Key
                    $command = ""
                }

                WriteCompleter $command $parameter $false $pair.Value
            }

            foreach ($pair in $tabExpansionOptions.NativeArgumentCompleters.GetEnumerator()) {
                WriteCompleter $pair.Key '' $true $pair.Value
            }
        }

        WriteCompleters | Sort-Object -Property Native, Command, Parameter
    }

    #############################################################################
    #
    # .SYNOPSIS
    #     Register a ScriptBlock to perform argument completion for a
    #     given command or parameter.
    #
    # .DESCRIPTION
    #
    # .PARAMETER Option
    #
    #     The name of the option.
    #
    # .PARAMETER Value
    #
    #     The value to set for Option. Typically this will be $true.
    #
    function Set-TabExpansionOption {
        param (
            [ValidateSet('ExcludeHiddenFiles',
                'RelativePaths',
                'LiteralPaths',
                'IgnoreHiddenShares',
                'AppendBackslash')]
            [string]
            $Option,

            [object]
            $Value = $true)

        $tabExpansionOptions[$option] = $value
    }

    #endregion Exported functions

    #region Internal utility functions

    #############################################################################
    #
    # This function checks if an attribute argument's name can be completed.
    # For example:
    #     [Parameter(<TAB>
    #     [Parameter(Po<TAB>
    #     [CmdletBinding(DefaultPa<TAB>
    #
    function TryAttributeArgumentCompletion {
        param (
            [System.Management.Automation.Language.Ast]
            $ast,

            [int]
            $offset
        )

        $results = @()
        $matchIndex = -1

        try {
            # We want to find any NamedAttributeArgumentAst objects where the Ast extent includes $offset
            $offsetInExtentPredicate = {
                param ($ast)
                return $offset -gt $ast.Extent.StartOffset -and
                $offset -le $ast.Extent.EndOffset
            }
            $asts = $ast.FindAll($offsetInExtentPredicate, $true)

            $attributeType = $null
            $attributeArgumentName = ""
            $replacementIndex = $offset
            $replacementLength = 0

            $attributeArg = $asts | Where-Object { $_ -is [System.Management.Automation.Language.NamedAttributeArgumentAst] } | Select-Object -First 1
            if ($null -ne $attributeArg) {
                $attributeAst = [System.Management.Automation.Language.AttributeAst]$attributeArg.Parent
                $attributeType = $attributeAst.TypeName.GetReflectionAttributeType()
                $attributeArgumentName = $attributeArg.ArgumentName
                $replacementIndex = $attributeArg.Extent.StartOffset
                $replacementLength = $attributeArg.ArgumentName.Length
            } else {
                $attributeAst = $asts | Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] } | Select-Object -First 1
                if ($null -ne $attributeAst) {
                    $attributeType = $attributeAst.TypeName.GetReflectionAttributeType()
                }
            }

            if ($null -ne $attributeType) {
                $results = $attributeType.GetProperties('Public,Instance') |
                    Where-Object {
                    # Ignore TypeId (all attributes inherit it)
                    $_.Name -like "$attributeArgumentName*" -and $_.Name -ne 'TypeId'
                } |
                    Sort-Object -Property Name |
                    ForEach-Object {
                    $propType = [Microsoft.PowerShell.ToStringCodeMethods]::Type($_.PropertyType)
                    $propName = $_.Name
                    New-CompletionResult $propName -ToolTip "$propType $propName" -CompletionResultType Property
                }

                return [PSCustomObject]@{
                    Results           = $results
                    ReplacementIndex  = $replacementIndex
                    ReplacementLength = $replacementLength
                }
            }
        } catch { }
    }

    #############################################################################
    #
    # This function completes native commands options starting with - or --
    # works around a bug in PowerShell that causes it to not complete
    # native command options starting with - or --
    #
    function TryNativeCommandOptionCompletion {
        param (
            [System.Management.Automation.Language.Ast]
            $ast,

            [int]
            $offset
        )

        $results = @()
        $replacementIndex = $offset
        $replacementLength = 0
        try {
            # We want to find any Command element objects where the Ast extent includes $offset
            $offsetInOptionExtentPredicate = {
                param ($ast)
                return $offset -gt $ast.Extent.StartOffset -and
                $offset -le $ast.Extent.EndOffset -and
                $ast.Extent.Text.StartsWith('-')
            }
            $option = $ast.Find($offsetInOptionExtentPredicate, $true)
            if ($option -ne $null) {
                $command = $option.Parent -as [System.Management.Automation.Language.CommandAst]
                if ($command -ne $null) {
                    $nativeCommand = [System.IO.Path]::GetFileNameWithoutExtension($command.CommandElements[0].Value)
                    $nativeCompleter = $tabExpansionOptions.NativeArgumentCompleters[$nativeCommand]

                    if ($nativeCompleter) {
                        $results = @(& $nativeCompleter $option.ToString() $command)
                        if ($results.Count -gt 0) {
                            $replacementIndex = $option.Extent.StartOffset
                            $replacementLength = $option.Extent.Text.Length
                        }
                    }
                }
            }
        } catch { }

        return [PSCustomObject]@{
            Results           = $results
            ReplacementIndex  = $replacementIndex
            ReplacementLength = $replacementLength
        }
    }


    #endregion Internal utility functions

    #############################################################################
    #
    # This function is partly a copy of the V3 TabExpansion2, adding a few
    # capabilities such as completing attribute arguments and excluding hidden
    # files from results.
    #
    function global:TabExpansion2 {
        [CmdletBinding(DefaultParameterSetName = 'ScriptInputSet')]
        param (
            [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory, Position = 0)]
            [string]
            $inputScript,

            [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory, Position = 1)]
            [int]
            $cursorColumn,

            [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 0)]
            [System.Management.Automation.Language.Ast]
            $ast,

            [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 1)]
            [System.Management.Automation.Language.Token[]]
            $tokens,

            [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 2)]
            [System.Management.Automation.Language.IScriptPosition]
            $positionOfCursor,

            [Parameter(ParameterSetName = 'ScriptInputSet', Position = 2)]
            [Parameter(ParameterSetName = 'AstInputSet', Position = 3)]
            [Hashtable]
            $options = $null
        )

        if ($null -ne $options) {
            $options += $tabExpansionOptions
        } else {
            $options = $tabExpansionOptions
        }

        if ($psCmdlet.ParameterSetName -eq 'ScriptInputSet') {
            $results = [System.Management.Automation.CommandCompletion]::CompleteInput(
                <#inputScript#>                $inputScript,
                <#cursorColumn#>                $cursorColumn,
                <#options#>                $options)
        } else {
            $results = [System.Management.Automation.CommandCompletion]::CompleteInput(
                <#ast#>                $ast,
                <#tokens#>                $tokens,
                <#positionOfCursor#>                $positionOfCursor,
                <#options#>                $options)
        }

        if ($results.CompletionMatches.Count -eq 0) {
            # Built-in didn't succeed, try our own completions here.
            if ($psCmdlet.ParameterSetName -eq 'ScriptInputSet') {
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($inputScript, [ref]$tokens, [ref]$null)
            } else {
                $cursorColumn = $positionOfCursor.Offset
            }

            # workaround PowerShell bug that case it to not invoking native completers for - or --
            # making it hard to complete options for many commands
            $nativeCommandResults = TryNativeCommandOptionCompletion -ast $ast -offset $cursorColumn
            if ($null -ne $nativeCommandResults) {
                $results.ReplacementIndex = $nativeCommandResults.ReplacementIndex
                $results.ReplacementLength = $nativeCommandResults.ReplacementLength
                if ($results.CompletionMatches.IsReadOnly) {
                    # Workaround where PowerShell returns a readonly collection that we need to add to.
                    $collection = new-object System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]
                    $results.GetType().GetProperty('CompletionMatches').SetValue($results, $collection)
                }
                $nativeCommandResults.Results | ForEach-Object {
                    $results.CompletionMatches.Add($_)
                }
            }

            $attributeResults = TryAttributeArgumentCompletion $ast $cursorColumn
            if ($null -ne $attributeResults) {
                $results.ReplacementIndex = $attributeResults.ReplacementIndex
                $results.ReplacementLength = $attributeResults.ReplacementLength
                if ($results.CompletionMatches.IsReadOnly) {
                    # Workaround where PowerShell returns a readonly collection that we need to add to.
                    $collection = new-object System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]
                    $results.GetType().GetProperty('CompletionMatches').SetValue($results, $collection)
                }
                $attributeResults.Results | ForEach-Object {
                    $results.CompletionMatches.Add($_)
                }
            }
        }

        if ($options.ExcludeHiddenFiles) {
            foreach ($result in @($results.CompletionMatches)) {
                if ($result.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderItem -or
                    $result.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer) {
                    try {
                        $item = Get-Item -LiteralPath $result.CompletionText -ErrorAction Stop
                    } catch {
                        # If Get-Item w/o -Force fails, it is probably hidden, so exclude the result
                        $null = $results.CompletionMatches.Remove($result)
                    }
                }
            }
        }
        if ($options.AppendBackslash -and
            $results.CompletionMatches.ResultType -contains [System.Management.Automation.CompletionResultType]::ProviderContainer) {
            foreach ($result in @($results.CompletionMatches)) {
                if ($result.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer) {
                    $completionText = $result.CompletionText
                    $lastChar = $completionText[-1]
                    $lastIsQuote = ($lastChar -eq '"' -or $lastChar -eq "'")
                    if ($lastIsQuote) {
                        $lastChar = $completionText[-2]
                    }

                    if ($lastChar -ne '\') {
                        $null = $results.CompletionMatches.Remove($result)

                        if ($lastIsQuote) {
                            $completionText =
                            $completionText.Substring(0, $completionText.Length - 1) +
                            '\' + $completionText[-1]
                        } else {
                            $completionText = $completionText + '\'
                        }

                        $updatedResult = New-Object System.Management.Automation.CompletionResult `
                        ($completionText, $result.ListItemText, $result.ResultType, $result.ToolTip)
                        $results.CompletionMatches.Add($updatedResult)
                    }
                }
            }
        }

        if ($results.CompletionMatches.Count -eq 0) {
            # No results, if this module has overridden another TabExpansion2 function, call it
            # but only if it's not the built-in function (which we assume if function isn't
            # defined in a file.
            if ($oldTabExpansion2 -ne $null -and $oldTabExpansion2.File -ne $null) {
                return (& $oldTabExpansion2 @PSBoundParameters)
            }
        }

        return $results
    }


    #############################################################################
    #
    # Main
    #

    Add-Type @"
using System;
using System.Management.Automation;

public class NativeCommandTreeNode
{
    private NativeCommandTreeNode(NativeCommandTreeNode[] subCommands)
    {
        SubCommands = subCommands;
    }

    public NativeCommandTreeNode(string command, NativeCommandTreeNode[] subCommands)
        : this(command, null, subCommands)
    {
    }

    public NativeCommandTreeNode(string command, string tooltip, NativeCommandTreeNode[] subCommands)
        : this(subCommands)
    {
        this.Command = command;
        this.Tooltip = tooltip;
    }

    public NativeCommandTreeNode(string command, string tooltip, bool argument)
        : this(null)
    {
        this.Command = command;
        this.Tooltip = tooltip;
        this.Argument = true;
    }

    public NativeCommandTreeNode(ScriptBlock completionGenerator, NativeCommandTreeNode[] subCommands)
        : this(subCommands)
    {
        this.CompletionGenerator = completionGenerator;
    }

    public string Command { get; private set; }
    public string Tooltip { get; private set; }
    public bool Argument { get; private set; }
    public ScriptBlock CompletionGenerator { get; private set; }
    public NativeCommandTreeNode[] SubCommands { get; private set; }
}
"@

    # Custom completions are saved in this hashtable
    $tabExpansionOptions = @{
        CustomArgumentCompleters = @{ }
        NativeArgumentCompleters = @{ }
    }
    # Descriptions for the above completions saved in this hashtable
    $tabExpansionDescriptions = @{ }
    # And private data for the above completions cached in this hashtable
    $completionPrivateData = @{ }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUjTpbXYi0TIA7VIuilDWwM4wB
# skagghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFFdYD/fEBcozCqUH+thkVORXSmSzMA0G
# CSqGSIb3DQEBAQUABIIBAKaojxzlRD8X+0ZyOGWCaFJCwxUXwGJPQj5xavhgVI8V
# JpytN4wg3HwG5obPTEUL6ALVRiUSKx6wmwwDsAGPa1Y46UVLeVzxkqTNJ1jtyIGr
# 2lEK7eAouHKYrwK4hL+rNdzdPYPrwubB5BtuVk015P1c7wU9RRSLEh6kwhlhNeMU
# 412VwbLtaSR7U2lMz62fR1TqpJWaDtTwTLHb+ivrcTAexG6nFv9801/ku6GQ8vna
# cYL0T9BJnwrKqazYsmSD8i8hVWEr4qsAFWjnPhubP+VYcpFmWfAbjE2jbI1YJwtj
# 3xLjDzb4pqiBvwtgHtA0pWP4xI33rnR2mqQX5DMge3ShggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNTAwWjAvBgkqhkiG9w0BCQQxIgQgWYJYTLwmzCorqiAHghmo
# EaplNyEb5gPBmKgHRkuNya4wDQYJKoZIhvcNAQEBBQAEggIAVvKp44apWC2kKnLy
# v3ThHjHJTNGSRxgIslATEF0sHzQkvFpLZrsLeUDupe9v7Hrn2c72BSWnLzqLIZWu
# EA4sK+zUntUtcmCPLzfNOkK3pCz1p1Dxy5lQWA95duZMT6rJiUEAU/1PNJseAEGA
# CS4FmuuDBRl0r3y5eV0f62D37UH8ME3Zq7n0KqoTjAbIZflZcmgt4xHGth8/ZQ5K
# jCKBnw4PFYxpVwO2ZE+jQYXwVozc2ZvRoriUu6XyDMHukCtia6fLM9COwxRikYzS
# TyH8nB/ys7rt0NXXAl3vunsY/SUi4L+6JmdWzvfIzGsq/AaoC+koiYyFIT0w/md6
# Db8Bb0YqfTEariYtfCqjOpBuJIx5zVNrmnBGAYiKWPP3qlaNv9Rg/HYC0d39JaO1
# YavqmlKEYV4ZQrB12RRLvGxXbnRlqScXUB/tV6fiBgJeZjyM6yL33n0vm8VrNg8j
# 970+bYjKXaDQgXzvmH+haZg1CnydUypsPTCUNXcff6Ne2N8HYxMmXZ43Wzus7jK9
# DuuqY22mEcGao6+F1lsjzbqnVFw6P+ruCxAXIzTrrKNp7+/y3lryyWpjUid6ZlyV
# 7lY45KcZrzh4b8znkEU/yCUKqhXcxZlYci6VEMuT0hef5BtIGa5XCbQlHN2kqxHl
# K0Otd1sh53uQyElxTnV4P14By4A=
# SIG # End signature block
