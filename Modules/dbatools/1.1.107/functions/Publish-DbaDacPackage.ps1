function Publish-DbaDacPackage {
    <#
    .SYNOPSIS
        The Publish-DbaDacPackage command takes a dacpac or bacpac and publishes it to a database.

    .DESCRIPTION
        Publishes the dacpac taken from SSDT project or Export-DbaDacPackage. Changing the schema to match the dacpac and also to run any scripts in the dacpac (pre/post deploy scripts) or bacpac.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Only SQL authentication is supported. When not specified, uses Trusted Authentication.

    .PARAMETER Path
        Specifies the filesystem path to the DACPAC

    .PARAMETER PublishXml
        Specifies the publish profile which will include options and sqlCmdVariables.

    .PARAMETER Database
        Specifies the name of the database being published.

    .PARAMETER ConnectionString
        Specifies the connection string to the database you are upgrading. This is not required if SqlInstance is specified.

    .PARAMETER GenerateDeploymentReport
        If this switch is enabled, the publish XML report  will be generated.

    .PARAMETER Type
        Selecting the type of the export: Dacpac (default) or Bacpac.

    .PARAMETER DacOption
        Export options for a corresponding export type. Can be created by New-DbaDacOption -Type Dacpac | Bacpac

    .PARAMETER OutputPath
        Specifies the filesystem path (directory) where output files will be generated.

    .PARAMETER ScriptOnly
        If this switch is enabled the publish script will be generated.

    .PARAMETER IncludeSqlCmdVars
        If this switch is enabled, SqlCmdVars in publish.xml will have their values overwritten.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER DacFxPath
        Path to the dac dll. If this is omitted, then the version of dac dll which is packaged with dbatools is used.

    .NOTES
        Tags: Deployment, Dacpac, Bacpac
        Author: Richie lee (@richiebzzzt)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Deploying a dacpac uses the DacFx which historically needed to be installed on a machine prior to use. In 2016 the DacFx was supplied by Microsoft as a nuget package (Microsoft.Data.Tools.MSBuild) and this uses that nuget package.

    .LINK
        https://dbatools.io/Publish-DbaDacPackage

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Publish
        PS C:\> $options.DeployOptions.DropObjectsNotInSource = $true
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2016 -Database DB1 -DacOption $options -Path c:\temp\db.dacpac

        Uses DacOption object to set Deployment Options and updates DB1 database on sql2016 from the db.dacpac dacpac file, dropping objects that are missing from source.

    .EXAMPLE
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml -Confirm

        Updates WideWorldImporters on sql2017 from the sql2016-WideWorldImporters.dacpac using the sql2016-WideWorldImporters-publish.xml publish profile. Prompts for confirmation.

    .EXAMPLE
        PS C:\> New-DbaDacProfile -SqlInstance sql2016 -Database db2 -Path C:\temp
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database db2 | Publish-DbaDacPackage -PublishXml C:\temp\sql2016-db2-publish.xml -Database db1, db2 -SqlInstance sql2017

        Creates a publish profile at C:\temp\sql2016-db2-publish.xml, exports the .dacpac to $home\Documents\sql2016-db2.dacpac. Does not prompt for confirmation.
        then publishes it to the sql2017 server database db2

    .EXAMPLE
        PS C:\> $loc = "C:\Users\bob\source\repos\Microsoft.Data.Tools.Msbuild\lib\net46\Microsoft.SqlServer.Dac.dll"
        PS C:\> Publish-DbaDacPackage -SqlInstance "local" -Database WideWorldImporters -Path C:\temp\WideWorldImporters.dacpac -PublishXml C:\temp\WideWorldImporters.publish.xml -DacFxPath $loc -Confirm

        Publishes the dacpac using a specific dacfx library. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml -ScriptOnly

        Does not deploy the changes, but will generate the deployment script that would be executed against WideWorldImporters.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Obj', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Path,
        [Parameter(ParameterSetName = 'Xml')]
        [string]$PublishXml,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string[]]$Database,
        [string[]]$ConnectionString,
        [switch]$GenerateDeploymentReport,
        [Switch]$ScriptOnly,
        [ValidateSet('Dacpac', 'Bacpac')]
        [string]$Type = 'Dacpac',
        [string]$OutputPath = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [switch]$IncludeSqlCmdVars,
        [Parameter(ParameterSetName = 'Obj')]
        [Alias("Option")]
        [object]$DacOption,
        [switch]$EnableException,
        [String]$DacFxPath
    )

    begin {
        if ((Test-Bound -Not -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName ConnectionString)) {
            Stop-Function -Message "You must specify either SqlInstance or ConnectionString."
            return
        }
        if ($ConnectionString) {
            $ConnectionString = $ConnectionString | Convert-ConnectionString
        }
        if ($Type -eq 'Dacpac') {
            if ((Test-Bound -ParameterName ScriptOnly) -or (Test-Bound -ParameterName GenerateDeploymentReport)) {
                $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DatabaseScriptPath', 'MasterDbScriptPath', 'DeploymentReport', 'DeployOptions', 'SqlCmdVariableValues'
            } else {
                $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DeployOptions', 'SqlCmdVariableValues'
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($ScriptOnly -or $GenerateDeploymentReport) {
                Stop-Function -Message "ScriptOnly and GenerateDeploymentReport cannot be used in a Bacpac scenario." -ErrorRecord $_
                return
            }
            $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Bacpac', 'Result', 'DeployOptions'
        }

        function Get-ServerName ($connString) {
            $builder = New-Object System.Data.Common.DbConnectionStringBuilder
            $builder.set_ConnectionString($connString)
            $instance = $builder['data source']

            if (-not $instance) {
                $instance = $builder['server']
            }

            return $instance.ToString().Replace('\', '-').Replace('(', '').Replace(')', '')
        }

        if ((Test-Bound -Not -ParameterName 'DacfxPath') -and (-not $script:core)) {
            $dacfxPath = "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"

            if ((Test-Path $dacfxPath) -eq $false) {
                Stop-Function -Message 'No usable version of Dac Fx found.' -EnableException $EnableException
                return
            } else {
                try {
                    Add-Type -Path $dacfxPath
                    Write-Message -Level Verbose -Message "Dac Fx loaded."
                } catch {
                    Stop-Function -Message 'No usable version of Dac Fx found.' -EnableException $EnableException -ErrorRecord $_
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if (-not (Test-Path -Path $Path)) {
            Stop-Function -Message "$Path not found."
            return
        }

        # auto detect if a .bacpac was passed in, just in case the -Type param was not specified
        if (-not (Test-Bound Type) -and [IO.Path]::GetExtension($Path) -eq '.bacpac') {
            $Type = 'Bacpac'
        }

        #Check Option object types - should have a specific type
        if ($Type -eq 'Dacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.PublishOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.PublishOptions object type is expected for `"-Type Dacpac`" but $($DacOption.GetType()) was passed in."
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacImportOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacImportOptions object type is expected for `"-Type Bacpac`" but $($DacOption.GetType()) was passed in."
                return
            }
        }

        if (Test-Bound PublishXml) {
            if (-not (Test-Path -Path $PublishXml)) {
                Stop-Function -Message "$PublishXml not found."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace('"', "'") | Convert-ConnectionString
        }

        #Use proper class to load the object
        if ($Type -eq 'Dacpac') {
            try {
                $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($Path)
            } catch {
                Stop-Function -Message "Could not load Dacpac." -ErrorRecord $_
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            try {
                $bacPackage = [Microsoft.SqlServer.Dac.BacPackage]::Load($Path)
            } catch {
                Stop-Function -Message "Could not load Bacpac." -ErrorRecord $_
                return
            }
        }
        #Load XML profile when used
        if (Test-Bound PublishXml) {
            try {
                $options = New-DbaDacOption -Type $Type -Action Publish -PublishXml $PublishXml -EnableException
            } catch {
                Stop-Function -Message "Could not load profile." -ErrorRecord $_
                return
            }
        }
        #Create/re-use deployment options object
        else {
            if (-not (Test-Bound DacOption)) {
                $options = New-DbaDacOption -Type $Type -Action Publish
            } else {
                $options = $DacOption
            }
        }
        #Replace variables if defined
        if ($IncludeSqlCmdVars) {
            Get-SqlCmdVars -SqlCommandVariableValues $options.DeployOptions.SqlCommandVariableValues
        }

        foreach ($connString in $ConnectionString) {
            $connString = $connString | Convert-ConnectionString
            $cleaninstance = Get-ServerName $connString
            $instance = $cleaninstance.ToString().Replace('--', '\')

            # Fix for #7704 to take care that $cleaninstance can be used as a filename:
            $cleaninstance = $cleaninstance.Replace(':', '_')

            foreach ($dbName in $Database) {
                #Set deployment properties when specified
                if (Test-Bound -ParameterName ScriptOnly) {
                    $options.GenerateDeploymentScript = $true
                }
                if (Test-Bound -ParameterName GenerateDeploymentReport) {
                    $options.GenerateDeploymentReport = $GenerateDeploymentReport
                }
                #Set output file paths when needed
                $timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
                if ($options.GenerateDeploymentScript) {
                    $options.DatabaseScriptPath = Join-Path $OutputPath "$cleaninstance-$dbName`_DeployScript_$timeStamp.sql"
                    $options.MasterDbScriptPath = Join-Path $OutputPath "$cleaninstance-$dbName`_Master.DeployScript_$timeStamp.sql"
                }
                if ($connString -notmatch 'Database=') {
                    $connString = "$connString;Database=$dbName"
                }

                #Create services object
                try {
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connString
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
                }

                try {
                    $null = $output = Register-ObjectEvent -InputObject $dacServices -EventName "Message" -SourceIdentifier "msg" -ErrorAction SilentlyContinue -Action {
                        $EventArgs.Message.Message
                    }
                    #Perform proper action depending on the Type
                    if ($Type -eq 'Dacpac') {
                        if ($options.GenerateDeploymentScript) {
                            Write-Message -Level Verbose -Message "Generating the deployment script as requested by the caller."
                            if (!$options.DatabaseScriptPath) {
                                Stop-Function -Message "DatabaseScriptPath option should be specified when running with -ScriptOnly" -EnableException $true
                            }
                            if ($Pscmdlet.ShouldProcess($instance, "Generating script")) {
                                $result = $dacServices.Script($dacPackage, $dbName, $options)
                            }
                        } else {
                            if ($Pscmdlet.ShouldProcess($instance, "Executing Dacpac publish")) {
                                $result = $dacServices.Publish($dacPackage, $dbName, $options)
                            }
                        }
                    } elseif ($Type -eq 'Bacpac') {
                        if ($Pscmdlet.ShouldProcess($instance, "Executing Bacpac import")) {
                            $dacServices.ImportBacpac($bacPackage, $dbName, $options, $null)
                        }
                    }
                } catch [Microsoft.SqlServer.Dac.DacServicesException] {
                    Stop-Function -Message "Deployment failed" -ErrorRecord $_ -Continue
                } finally {
                    Unregister-Event -SourceIdentifier "msg"
                    if ($Pscmdlet.ShouldProcess($instance, "Generating deployment report and output")) {
                        if ($options.GenerateDeploymentReport) {
                            $deploymentReport = Join-Path $OutputPath "$cleaninstance-$dbName`_Result.DeploymentReport_$timeStamp.xml"
                            $result.DeploymentReport | Out-File $deploymentReport
                            Write-Message -Level Verbose -Message "Deployment Report - $deploymentReport."
                        }
                        if ($options.GenerateDeploymentScript) {
                            Write-Message -Level Verbose -Message "Database change script - $($options.DatabaseScriptPath)."
                            if ((Test-Path $options.MasterDbScriptPath)) {
                                Write-Message -Level Verbose -Message "Master database change script - $($result.MasterDbScript)."
                            }
                        }
                        $resultOutput = ($output.output -join [System.Environment]::NewLine | Out-String).Trim()
                        if ($resultOutput -match "Failed" -and ($options.GenerateDeploymentReport -or $options.GenerateDeploymentScript)) {
                            Write-Message -Level Warning -Message "Seems like the attempt to publish/script may have failed. If scripts have not generated load dacpac into Visual Studio to check SQL is valid."
                        }

                        # Fix for #7704 to take care that named pipe connections to the local host work:
                        $instance = $instance.Replace('NP:.', '.')

                        $server = [dbainstance]$instance
                        if ($Type -eq 'Dacpac') {
                            $output = [pscustomobject]@{
                                ComputerName         = $server.ComputerName
                                InstanceName         = $server.InstanceName
                                SqlInstance          = $server.FullName
                                Database             = $dbName
                                Result               = $resultOutput
                                Dacpac               = $Path
                                PublishXml           = $PublishXml
                                ConnectionString     = $connString
                                DatabaseScriptPath   = $options.DatabaseScriptPath
                                MasterDbScriptPath   = $options.MasterDbScriptPath
                                DeploymentReport     = $DeploymentReport
                                DeployOptions        = $options.DeployOptions | Select-Object -Property * -ExcludeProperty "SqlCommandVariableValues"
                                SqlCmdVariableValues = $options.DeployOptions.SqlCommandVariableValues.Keys
                            }
                        } elseif ($Type -eq 'Bacpac') {
                            $output = [pscustomobject]@{
                                ComputerName     = $server.ComputerName
                                InstanceName     = $server.InstanceName
                                SqlInstance      = $server.FullName
                                Database         = $dbName
                                Result           = $resultOutput
                                Bacpac           = $Path
                                ConnectionString = $connString
                                DeployOptions    = $options
                            }
                        }
                        $output | Select-DefaultView -Property $defaultColumns
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBFyDWtFOxvo3VL
# bEyigtqYpo3MjiZjWZuG/Ou6jwCG36CCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCA4bCZNlH/j4T99NJVuWgx9ztkyyqa4UcT0
# Qq9AHS/F3DANBgkqhkiG9w0BAQEFAASCAQAp1KpysDwY2+VSVDIybPb70BXc5IBS
# pQqD4XGAK9H6jPvwP8dg1vTMMq1h1q13gKkWMDOFm71tTphtKBl/42eFXA7I74ex
# X5eQ3VhtQ3NHoW/tvcJZpie7RO9Pc0CGxHAbco2DS6rWefSQrFiwzlIsnQr7gg1c
# mY6kLB5EyU2jjiKhfcIIqIhG8EA3o6z/qq2rDlO/QKlSH7zPpzFHB/f4yKf6Wfm4
# Aix/PIhUyUSrzkwh80McpFCvpEIwvF3QkXwIIV/CVIm6Cumx+CJhH1kxO/CN7hKc
# Pa134TASXKbuks6bCWvoYK3madcZYw+dKjbDUvysL6Hls/IM0BDm6fMYoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDM0MFowLwYJKoZIhvcNAQkEMSIEIJaqEjix
# FpkkxxYiciCQ3QP06ljww+1p6c6FA4sVI8K7MA0GCSqGSIb3DQEBAQUABIICAJwk
# OgZrrvKK0H4XN8X9guwgYOTRKSUzKh6RCJOASlaJ3XxEOXfO14Q51zXooLLTZhUE
# Jx8w1XmGE6+VEpDc8dtDCIRH6sJw9KrIrscl+7hug5ZhgQxfurYhFFlXUXn1cWUo
# b2s1wPEnnEAkNCTyagq4ctDKpBkquG6qObRW1E3w5kHZeX0JRCBG3Bni08inhoYC
# lWSIGoJxJgtDaOHhIUvt5XhTmZ6YKvtEXkNKlMStyo1eud8jjpAx8MdrqkEqgZP2
# ja5zs3UwatVwp/L39LaZScn15lFkPYzaYMj/IBiSFy4fjBg9/srK8YXE41S05LBz
# Td2l7zKnMdAzrEf/kVFpvUTlJjsG0eX0Lh1DfbRYm2cbYrtSw3QkYk+KRmabYlGH
# Cn1jmkxFMraba2WMZNQvKtuU0bsujrmKnnFCpr9014bExxhM3QinpFQyFzgbn0EB
# MxVcAdiMdEgi+e7i2oeXelFjr0nN/yCbwEfzEDk56AOzXh/CeV3ivoVmhEX4I21P
# QQZHYIEbrzSkXYD+pgFkHJs1DS/+aVDbYA81EXQquu4e+vnLKrRWwR37mN2KJydv
# S+Z6vEYqpzTG3NdgzBh/xU0UUl8eDutqmLJew0m6JCT1v+sv34CFnB4s8HvPbHXE
# iq6XsS5ShL10foZKRtNYpa16RDpfbCFTBNWSX5Gk
# SIG # End signature block
