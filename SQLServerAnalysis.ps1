#Requires -Version 5.1

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Basic', 'Advanced', 'DBA')]
    [string]
    $ScanType = 'Basic'
)

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
        $fullCommandLine = (Get-Location).Path + ($MyInvocation.Line).Replace(".\", "\")# + " -ScanType $ScanType"
        Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $fullCommandLine
        Exit
    }
}

# Import bundled modules
try {
    Write-Progress -id 0 -Activity "Importing required PowerShell modules..."
    Import-Module dbachecks, ImportExcel -Force -ErrorAction Stop
    Write-Progress -Id 0 -Completed "Completed importing modules."
}
catch {
    Write-Progress -id 0 -Activity "Installing required PowerShell modules..."
    Copy-Item "$PSScriptRoot\Modules\*" "C:\Windows\System32\WindowsPowerShell\v1.0\Modules" -Recurse -Confirm:$false -Force -Verbose
    Write-Progress -id 0 -Completed -Activity "Completed installing required modules."
    Import-Module dbachecks, ImportExcel    
}

# Get the current timestamp
$datetime = get-date -f MM-dd-yyyy_hh.mm.ss

Start-Transcript "$PSScriptRoot\tmp\ExecutionTranscript_$dateTime.log"

# Import functions
. "$PSScriptRoot\Functions\SQLAnalysisFunctions.ps1"

# Verify tmp directory
if (-not (Test-Path "$PSScriptRoot\tmp")) { mkdir "$PSScriptRoot\tmp" }

# Get Computer Information - We'll check if this is a cluster. If it is, get computer info from all nodes.
if (Get-DbaWsfcCluster -WarningAction SilentlyContinue) {
    Import-Module FailoverClusters
    Write-Progress -id 0 -Activity "Getting cluster information..."
    $isCluster = $true
    $clusterNodes = Get-DbaWsfcNode
    $clusterNodeInfo = [System.Collections.ArrayList]@()
        
    $clusterNodes | % {
        $systemInfo = Get-DbaComputerSystem -ComputerName $_.Name
        $osInfo = Get-DbaOperatingSystem -ComputerName $_.Name
        $pageFileInfo = Get-DbaPageFileSetting -ComputerName $_.Name | Select FileName, Status, SystemManaged, AllocatedBaseSize, InitialSize, MaximumSize

        # Get the operating system version. if it is 6.2 (Server 2012) or greater, get the initiator info.
        $osVersion = [system.convert]::ToDecimal("$([environment]::OSVersion.Version.Major).$([environment]::OSVersion.Version.Minor)")

        #if ($osVersion -gt 6.1) { $initiatorInfo = Get-InitiatorPort }

        $object = [pscustomobject]@{
            "Name"                      = (Get-DbaComputerSystem -ComputerName $_.Name).ComputerName
            "Domain"                    = $systemInfo.Domain
            "OSVersion"                 = $osInfo.OSVersion
            "DeviceManufacturer"        = $systemInfo.Manufacturer
            "Processor"                 = $systemInfo.ProcessorName
            "NumberOfProcessors"        = $systemInfo.NumberProcessors
            "NumberOfLogicalProcessors" = $systemInfo.NumberLogicalProcessors
            "HyperthreadingEnabled"     = $systemInfo.IsHyperThreading
            "TotalPhysicalMemoryGB"     = [math]::Round($systemInfo.TotalPhysicalMemory.Gigabyte)
            "PendingReboot"             = $systemInfo.PendingReboot
            "LastBootTime"              = ($osInfo.LastBootTime | Select Month, Day, Year, Hour, Minute, Second)
            "PageFileInfo"              = $pageFileInfo
            "RolesAndFeatures"          = (Get-WindowsFeature | Where-Object { $_.InstallState -eq 'Installed' } | Select Name, DisplayName, Description, FeatureType, Path)
        }

        $clusterNodeInfo = [System.Collections.ArrayList]$clusterNodeInfo + $object            
    }

    $clusterNodeInfo | ConvertTo-Json | Out-File "$PSScriptRoot\tmp\clusterNodeInfo.json"

    # If clustering is installed, get the cluster information.
    $clusterInfo = [System.Collections.ArrayList]@()
    $object = [pscustomobject]@{
        "ClusterName"          = (Get-DbaWsfcCluster).Fqdn
        "ClusterInfo"          = Get-DbaWsfcCluster
        "ClusterDisks"         = (Get-DbaWsfcDisk | Select ClusterName, ClusterFqdn, ResourceGroup, Disk, State, FileSystem, Path, Label, Size, Free)
        "ClusterNetworks"      = (Get-DbaWsfcNetwork | Select ClusterName, ClusterFqdn, Name, Address, AddressMask, IPv4Addresses)
        "ClusterResources"     = (Get-DbaWsfcResource | Select State, ClusterName, ClusterFqdn, Name, OwnerGroup, OwnerNode, Type, CoreResource, IsClusterSharedVolume, QuorumCapable, LocalQuorumCapable)
        "ClusterResourceTypes" = Get-DbaWsfcResourceType
        "ClusterRoles"         = (Get-DbaWsfcRole | Select ClusterName, ClusterFqdn, Name, AutoFailbackType, IsCore)        
    }
    $clusterInfo = [System.Collections.ArrayList]$clusterInfo + $object        
    $clusterInfo | ConvertTo-Json | Out-File "$PSScriptRoot\tmp\clusterInfo.json"

    # Find each clustered FCI instance in the cluster.
    [Array]$clusSqlInstArr = Get-Clusterresource `
    | Where-Object { $_.resourcetype -like 'sql server' } `
    | Get-Clusterparameter "instancename" `
    | Sort-Object objectname `
    | Select-Object -expandproperty value
 
    [Array]$clusSqlVsnArr = Get-Clusterresource `
    | Where-Object { $_.resourcetype -like 'sql server' } `
    | Get-Clusterparameter "virtualservername" `
    | Sort-Object objectname `
    | Select-Object -expandproperty value

    $clusteredInstances = @()
    if ($clusSqlInstArr -and $clusSqlVsnArr) {
        foreach ($i in 0..($clusSqlInstArr.count - 1)) { 
            $object = [pscustomobject]@{
                SqlVSN  = $clusSqlVsnArr[$i]
                SqlInst = $clusSqlInstArr[$i]
            }
            $clusteredInstances += $object
        }
    }
    
    # Find each SQL instance on each node that is not clustered.
    $instanceData = @()
    $clusterNodes | % {
        $object = Find-DbaInstance -ComputerName $_.Name | ? { ($_.InstanceName -notin $clusSqlInstArr) -and ($_.InstanceName -ne "SSRS") }
        $instanceData = [System.Array]$instanceData + $object
    }

    if ($clusteredInstances) {
        $clusteredInstances | % {
            $instance = $_
            $object = Find-DbaInstance -ComputerName $instance.SqlVSN | ? { ($_.InstanceName -eq $instance.SqlInst) -and ($_.InstanceName -ne "SSRS") }
            $instanceData = [System.Array]$instanceData + $object
        }
    }

    $instanceData | ConvertTo-Json | Out-file "$PSScriptRoot\tmp\instanceData.json"

    # Run all best practices checks in the dbachecks module.
    $fileName = (Get-Content "$PSScriptRoot\tmp\clusterInfo.json" | ConvertFrom-Json).ClusterName
    # Set the app.cluster parameter for the dbachecks module to run the HADR tests.
    Set-DbcConfig -Name app.cluster -Value $fileName

    Write-Progress -id 0 -Completed -Activity "Completed gathering cluster information."

    # Run the Test-Cluster cmdlet.
    $clusReport = Test-Cluster -Include "Cluster Configuration", "Inventory", "Network", "System Configuration" -WarningAction SilentlyContinue
    $clusReportArray = Convert-ClusterValidationReport -ValidationXmlPath $clusReport.FullName.Replace(".htm", ".xml")
    
    $resultsArray = @()

    $clusReportArray | % {
        $category = $_.category
        $results = $_.results
        $results | % {
            $message = ""
            $_.Message | % {
                if ($message -eq "") { $message = $_ }
                else { $message = $message + "`n" + $_ }
            }

            $object = [pscustomobject]@{
                Category = $category
                Test     = $_.Title
                Result   = $_.Result
                Message  = $message
            }

            $resultsArray = [System.Array]$resultsArray + $object
        }
    }

    # Since clustering is installed, get a new cluster validation report and add it to the Excel report.
    $clReportWorksheet = "ClusterValidationReport"
    $clReportTable = "ClusterValidationReport"

    $ct1 = New-ConditionalText -Range "C:C" -Text "Pass" -ConditionalTextColor Black -BackgroundColor Green
    $ct2 = New-ConditionalText -Range "C:C" -Text "Warn" -ConditionalTextColor Black -BackgroundColor Yellow
    $ct3 = New-ConditionalText -Range "C:C" -Text "Fail" -ConditionalTextColor Black -BackgroundColor Red

    $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-$ScanType-SQLServerConfigReport-$datetime.xlsx"
    $excel = $resultsArray | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $clReportWorksheet -FreezeTopRow -TableName $clReportTable -ConditionalText $ct1, $ct2, $ct3 -PassThru
    $excel.Save() ; $excel.Dispose()

    # Export the cluster information to the Cluster Overview sheet
    $clNodeWorksheet = "Cluster Overview"
    $clNodeTable = "ClusterOverview"

    $clusterInfoObject = [pscustomobject]@{
        "ClusterName"          = $clusterInfo.ClusterName
        "ClusterLogLevel"      = $clusterInfo.ClusterInfo.ClusterLogLevel
        "ClusterLogSize"       = $clusterInfo.ClusterInfo.ClusterLogSize
        "CrossSiteDelay"       = $clusterInfo.ClusterInfo.CrossSiteDelay
        "CrossSiteThreshold"   = $clusterInfo.ClusterInfo.CrossSiteThreshold
        "CrossSubnetDelay"     = $clusterInfo.ClusterInfo.CrossSubnetDelay
        "CrossSubnetThreshold" = $clusterInfo.ClusterInfo.CrossSubnetThreshold
        "QuorumPath"           = $clusterInfo.ClusterInfo.QuorumPath
        "QuorumType"           = $clusterInfo.ClusterInfo.QuorumType
        "SameSubnetDelay"      = $clusterInfo.ClusterInfo.SameSubnetDelay
        "SameSubnetThreshold"  = $clusterInfo.ClusterInfo.SameSubnetThreshold        
    }

    if ($clusterInfoObject) {
        $excel = $clusterInfoObject | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $clNodeWorksheet -FreezeTopRow -TableName $clNodeTable -PassThru
        $excel.Save() ; $excel.Dispose()
    }

    if ($clusterInfo.ClusterDisks) {
        $clStorageWorksheet = "Cluster Storage"
        $clStorageTable = "ClusterStorage"

        $excel = $clusterInfo.ClusterDisks | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $clStorageWorksheet -FreezeTopRow -TableName $clStorageTable -PassThru
        $excel.Save() ; $excel.Dispose()
    }

    if ($clusterInfo.ClusterResources) {
        $clResourcesWorksheet = "Cluster Resources"
        $clResourcesTable = "ClusterResources"

        $excel = $clusterInfo.ClusterResources | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $clResourcesWorksheet -FreezeTopRow -TableName $clResourcesTable -PassThru
        $excel.Save() ; $excel.Dispose()
    }

    if ($clusterInfo.ClusterRoles) {
        $clRolesWorksheet = "Cluster Roles"
        $clRolesTable = "ClusterRoles"

        $excel = $clusterInfo.ClusterRoles | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $clRolesWorksheet -FreezeTopRow -TableName $clRolesTable -PassThru
        $excel.Save() ; $excel.Dispose()
    }

    # Now, we package all the node info. Since the list of disks and roles are multi-demensional arrays, we'll need to create a custom object.
    $clusterNodeArray = [System.Collections.ArrayList]@()
    $clusterNodeInfo | % {
        $nodeObject = [PSCustomObject]@{
            Name                      = $_.Name
            Domain                    = $_.Domain
            OSVersion                 = $_.OSVersion
            DeviceManufacturer        = $_.DeviceManufacturer
            NumberOfProcessors        = $_.NumberOfProcessors
            NumberOfLogicalProcessors = $_.NumberOfLogicalProcessors
            HyperthreadingEnabled     = $_.HyperthreadingEnabled
            TotalPhysicalMemoryGB     = $_.TotalPhysicalMemoryGB
            PendingReboot             = $_.PendingReboot
            LastBootTime              = "$($_.LastBootTime.Month)/$($_.LastBootTime.Day)/$($_.LastBootTime.Year) - $($_.LastBootTime.Hour):$($_.LastBootTime.Minute):$($_.LastBootTime.Second)"
        }
        <#
        $diskInfo = Get-DbaDiskSpace -ComputerName $_.Name | Select ComputerName, Name, Label, Capacity, Free, PercentFree, BlockSize, Type, IsSqlDisk

        $diskCounter = 1

        $diskInfo | % {
            $nodeObject | Add-Member -MemberType NoteProperty -Name "Disk-$diskCounter" -Value ($_ | Out-String).Trim()
            $diskCounter++
        } #>

        $clusterNodeArray = [System.Collections.ArrayList]$clusterNodeArray + $nodeObject
        
    }

    $clNodeWorksheet = "Cluster Nodes"
    $clNodeTable = "ClusterNodes"

    $excel = $clusterNodeArray | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $clNodeWorksheet -FreezeTopRow -TableName $clNodeTable -PassThru
    $excel.Save() ; $excel.Dispose()
        
}
else {
    $clusterNodeInfo = [System.Collections.ArrayList]@()
    $isCluster = $false
    Write-Progress -id 0 -Activity "Gathering node information..."
    $systemInfo = Get-DbaComputerSystem
    $osInfo = Get-DbaOperatingSystem
    $pageFileInfo = Get-DbaPageFileSetting | Select FileName, Status, SystemManaged, AllocatedBaseSize, InitialSize, MaximumSize

    $object = [pscustomobject]@{
        "Name"                      = $systemInfo.ComputerName
        "Domain"                    = $systemInfo.Domain
        "OSVersion"                 = $osInfo.OSVersion
        "DeviceManufacturer"        = $systemInfo.Manufacturer
        "Processor"                 = $systemInfo.ProcessorName
        "NumberOfProcessors"        = $systemInfo.NumberProcessors
        "NumberOfLogicalProcessors" = $systemInfo.NumberLogicalProcessors
        "HyperthreadingEnabled"     = $systemInfo.IsHyperThreading
        "TotalPhysicalMemoryGB"     = [math]::Round($systemInfo.TotalPhysicalMemory.Gigabyte)
        "PendingReboot"             = $systemInfo.PendingReboot
        "LastBootTime"              = ($osInfo.LastBootTime | Select Month, Day, Year, Hour, Minute, Second)
        "PageFileInfo"              = $pageFileInfo
    }

    $clusterNodeInfo = [System.Collections.ArrayList]$clusterNodeInfo + $object
        
    $clusterNodeInfo | ConvertTo-Json | Out-File "$PSScriptRoot\tmp\clusterNodeInfo.json"

    $instanceData = Find-DbaInstance -ComputerName $systemInfo.ComputerName | ? { $_.InstanceName -ne "SSRS" }
    $instanceData | ConvertTo-Json | Out-file "$PSScriptRoot\tmp\instanceData.json"

    $fileName = $instanceData.ComputerName

    # Now, we package all the node info. Since the list of disks and roles are multi-demensional arrays, we'll need to create a custom object.
    $clusterNodeArray = [System.Collections.ArrayList]@()
    $clusterNodeInfo | % {
        $nodeObject = [PSCustomObject]@{
            Name                      = $_.Name
            Domain                    = $_.Domain
            OSVersion                 = $_.OSVersion
            DeviceManufacturer        = $_.DeviceManufacturer
            NumberOfProcessors        = $_.NumberOfProcessors
            NumberOfLogicalProcessors = $_.NumberOfLogicalProcessors
            HyperthreadingEnabled     = $_.HyperthreadingEnabled
            TotalPhysicalMemoryGB     = $_.TotalPhysicalMemoryGB
            PendingReboot             = $_.PendingReboot
            LastBootTime              = "$($_.LastBootTime.Month)/$($_.LastBootTime.Day)/$($_.LastBootTime.Year) - $($_.LastBootTime.Hour):$($_.LastBootTime.Minute):$($_.LastBootTime.Second)"
        }
        
        $clusterNodeArray = [System.Collections.ArrayList]$clusterNodeArray + $nodeObject
        
    }

    $clNodeWorksheet = "Server Node"
    $clNodeTable = "ServerNode"

    $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-$ScanType-SQLServerConfigReport-$datetime.xlsx"
    $excel = $clusterNodeArray | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $clNodeWorksheet -FreezeTopRow -TableName $clNodeTable -PassThru
    $excel.Save() ; $excel.Dispose()

    Write-Progress -id 0 -Completed -Activity "Completed gathering node information."
} # End if/else statement determining nodes

# Now that we have all the instance data, let's set the app.computername and app.sqlinstance DbcConfig settings.    
Set-DbcConfig -Name app.computername -Value $instanceData.ComputerName -Temporary | Out-Null
Set-DbcConfig -Name app.sqlinstance -Value $instanceData.sqlinstance -Temporary | Out-Null

Write-Progress -Id 0 -Activity "Gathering server and instance information..."

# For each instance, we're going to install some T-SQL stored procedures to better troubleshoot issues.
$spCounter = 1

$instanceData.sqlInstance | % {
    $sqlInstance = $_
    Write-Progress -id 2 -ParentId 0 -Activity "Installing stored procedures..." -Status "$($spCounter)/$(($instanceData.sqlInstance).Count)" -PercentComplete ($spCounter / $(($instanceData.sqlInstance).Count) * 100)
    $sqlSpInstall = $_ | Invoke-DbaQuery -File "$PSScriptRoot\SQLScripts\Install-Core-Blitz-No-Query-Store.sql" -Database master -EnableException
    $spCounter++
}
Write-Progress -id 2 -Completed -Activity "Completed SP deployment."

# Now, we are going to get all the SQL Server install/build information.
$instanceCounter = 1

$instanceData.sqlInstance | % {
    Write-Progress -id 2 -ParentId 0 -Activity "Getting SQL instance information..." -Status "$($instanceCounter)/$(($instanceData.sqlInstance).Count)" -PercentComplete ($instanceCounter / $(($instanceData.sqlInstance).Count) * 100)
    $sqlInfo = Connect-DbaInstance -SqlInstance $_ | Select *
    $instanceObject = [pscustomobject]@{
        ComputerName                                    = $sqlInfo.ComputerName
        Name                                            = $sqlInfo.Name
        Version                                         = $sqlInfo.Version
        ProductLevel                                    = $sqlInfo.ProductLevel
        Edition                                         = $sqlInfo.Edition
        HostOS                                          = $sqlInfo.HostDistribution
        Collation                                       = $sqlInfo.Collation
        ServiceAccount                                  = $sqlInfo.ServiceAccount
        HADRManagerStatus                               = $sqlInfo.HADRManagerStatus
        IsFullTextInstalled                             = $sqlInfo.IsFullTextInstalled
        LoginMode                                       = $sqlInfo.LoginMode
        NamedPipesEnabled                               = $sqlInfo.NamedPipesEnabled
        IsMemberOfWsfcCluster                           = $sqlInfo.IsMemberOfWsfcCluster
        IsConfigurationOnlyAvailabilityReplicaSupported = $sqlInfo.IsConfigurationOnlyAvailabilityReplicaSupported
        IsAvailabilityReplicaSeedingModeSupported       = $sqlInfo.IsAvailabilityReplicaSeedingModeSupported
        IsCrossPlatformAvailabilityGroupSupported       = $sqlInfo.IsCrossPlatformAvailabilityGroupSupported
        IsReadOnlyListWithLoadBalancingSupported        = $sqlInfo.IsReadOnlyListWithLoadBalancingSupported
    }

    $instanceWorksheet = "SQL Instances"
    $instanceTable = "SQLInstances"

    $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-$ScanType-SQLServerConfigReport-$datetime.xlsx"
    $excel = $instanceObject | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $instanceWorksheet -FreezeTopRow -TableName $instanceTable -PassThru
    $excel.Save() ; $excel.Dispose()

    $instanceCounter++
}
Write-Progress -id 2 -Completed -Activity "Completed instance information retrieval."

if ($ScanType -eq "Basic") {
    $testsToRun = Import-Csv "$PSScriptRoot\refData\DbcCheckList.csv" | ? { $_.TestCategory -eq "Basic" } | Sort-Object UniqueTag

    # Set optional tests based on ScanType
    Set-DbcConfig -Name skip.security.builtinadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.nonstandardport -Value $false -Temporary | Out-Null
}
elseif ($ScanType -eq "Advanced") {
    $testsToRun = Import-Csv "$PSScriptRoot\refData\DbcCheckList.csv" | ? { ($_.TestCategory -eq "Basic") -or ($_.TestCategory -eq "Advanced") } | Sort-Object UniqueTag

    # Set optional tests based on ScanType
    Set-DbcConfig -Name skip.security.agentserviceadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.builtinadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.engineserviceadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.fulltextserviceadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.guestuserconnect -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.localwindowsgroup -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.loginauditlevelfailed -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.loginauditlevelsuccessful -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.LoginMustChange -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.LoginPasswordExpiration -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.nonstandardport -Value $false -Temporary | Out-Null
}
else {
    $testsToRun = Import-Csv "$PSScriptRoot\refData\DbcCheckList.csv" | Sort-Object UniqueTag

    # Set optional tests based on ScanType
    Set-DbcConfig -Name skip.security.agentserviceadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.builtinadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.clrassembliessafe -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.engineserviceadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.fulltextserviceadmin -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.guestuserconnect -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.localwindowsgroup -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.loginauditlevelfailed -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.loginauditlevelsuccessful -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.LoginCheckPolicy -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.LoginMustChange -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.LoginPasswordExpiration -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.querystoredisabled -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.sadisabled -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.saexist -Value $false -Temporary | Out-Null
    Set-DbcConfig -Name skip.security.nonstandardport -Value $false -Temporary | Out-Null
}
Write-Host "The following tests will be run:" -ForegroundColor Cyan
$testsToRun.UniqueTag

# Now, we run the DbcChecks best practrices tests against each instance.
#$dbcTestGroups = Get-DbcCheck | Select Group -Unique | Sort-Object Group
$dbcTestGroups = $testsToRun | Select Group -Unique
$dbcCheckCounter = 1

$dbcTestGroups | % {
    $dbcTestGroup = $_.Group
    $groupTestsToRun = $testsToRun | ? { $_.Group -eq $dbcTestGroup }
    Write-Progress -id 1 -ParentId 0 -Activity "Running {$dbcTestGroup} checks..." -Status "$($dbcCheckCounter)/$($dbcTestGroups.Count)" -PercentComplete ($dbcCheckCounter / $($dbcTestGroups.Count) * 100)
    
    # Here, we run the HADR tests, but only if the node we are on is part of a cluster.
    if ($isCluster -and ($dbcTestGroup -eq "HADR")) {

        $groupTestsToRun | % {
            $dbaCheck = Invoke-DbcCheck -SqlInstance $instanceData.sqlinstance -Check $_.UniqueTag -Show None -PassThru | Convert-DbcResult | Set-DbcFile -FilePath "$PSScriptRoot\tmp" -FileName "$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" -FileType CSV -Append
        }

        if (Test-Path "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv") {
            $dbaChecksArray = Import-Csv "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" | Select Describe, ComputerName, Instance, Database, Result, Name, FailureMessage
            
            $validationWorksheet = "$dbcTestGroup"
            $validationTableName = "$dbcTestGroup"
            
            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-$ScanType-SQLServerConfigReport-$datetime.xlsx"
            $ct1 = New-ConditionalText -Range "E:E" -Text "Skipped" -ConditionalTextColor Black -BackgroundColor Yellow
            $ct2 = New-ConditionalText -Range "E:E" -Text "Failed" -ConditionalTextColor Black -BackgroundColor Red
            $ct3 = New-ConditionalText -Range "E:E" -Text "Passed" -ConditionalTextColor Black -BackgroundColor Green
            #$ct4 = New-ConditionalText -Range "C:C" -Text "Failed" -ConditionalTextColor Black -BackgroundColor Red
            $excel = ($dbaChecksArray | Sort-Object Describe) | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $validationWorksheet -FreezeTopRow -TableName $validationTableName -ConditionalText $ct1, $ct2, $ct3 -PassThru -Append
            $excel.Save() ; $excel.Dispose()
            
            Remove-Item -Path "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" -Confirm:$false -Force
        }
        
        $dbcCheckCounter++
    } # Run the Server checks.
    elseif ($dbcTestGroup -eq "Server") {
        $groupTestsToRun | % {
            $dbaCheck = Invoke-DbcCheck -SqlInstance $instanceData.ComputerName -Check $_.UniqueTag -Show None -PassThru | Convert-DbcResult | Set-DbcFile -FilePath "$PSScriptRoot\tmp" -FileName "$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" -FileType CSV -Append    
        }

        if (Test-Path "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv") {
            $dbaChecksArray = Import-Csv "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" | Select Describe, ComputerName, Instance, Database, Result, Name, FailureMessage
    
            $validationWorksheet = "Server"
            $validationTableName = "Server"
    
            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-$ScanType-SQLServerConfigReport-$datetime.xlsx"
            $ct1 = New-ConditionalText -Range "E:E" -Text "Skipped" -ConditionalTextColor Black -BackgroundColor Yellow
            $ct2 = New-ConditionalText -Range "E:E" -Text "Failed" -ConditionalTextColor Black -BackgroundColor Red
            $ct3 = New-ConditionalText -Range "E:E" -Text "Passed" -ConditionalTextColor Black -BackgroundColor Green
            #$ct4 = New-ConditionalText -Range "C:C" -Text "Failed" -ConditionalTextColor Black -BackgroundColor Red
            $excel = ($dbaChecksArray | Sort-Object Describe) | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $validationWorksheet -FreezeTopRow -TableName $validationTableName -ConditionalText $ct1, $ct2, $ct3 -PassThru
            $excel.Save() ; $excel.Dispose()

            Remove-Item -Path "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" -Confirm:$false -Force
        }
        $dbcCheckCounter++
    }
    elseif (($dbcTestGroup -ne "HADR") -and ($dbcTestGroup -ne "Server")) {
        $groupTestsToRun | % {
            $dbaCheck = Invoke-DbcCheck -SqlInstance $instanceData.sqlinstance -Check $_.UniqueTag -Show None -PassThru | Convert-DbcResult | Set-DbcFile -FilePath "$PSScriptRoot\tmp" -FileName "$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" -FileType CSV -Append    
        }

        if (Test-Path "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv") {
            $dbaChecksArray = Import-Csv "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" | Select Describe, ComputerName, Instance, Database, Result, Name, FailureMessage
        
            $validationWorksheet = "$dbcTestGroup"
            $validationTableName = "$dbcTestGroup"
        
            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-$ScanType-SQLServerConfigReport-$datetime.xlsx"
            $ct1 = New-ConditionalText -Range "E:E" -Text "Skipped" -ConditionalTextColor Black -BackgroundColor Yellow
            $ct2 = New-ConditionalText -Range "E:E" -Text "Failed" -ConditionalTextColor Black -BackgroundColor Red
            $ct3 = New-ConditionalText -Range "E:E" -Text "Passed" -ConditionalTextColor Black -BackgroundColor Green
            #$ct4 = New-ConditionalText -Range "C:C" -Text "Failed" -ConditionalTextColor Black -BackgroundColor Red
            $excel = ($dbaChecksArray | Sort-Object Describe) | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $validationWorksheet -FreezeTopRow -TableName $validationTableName -ConditionalText $ct1, $ct2, $ct3 -PassThru
            $excel.Save() ; $excel.Dispose()
        
            Remove-Item -Path "$PSScriptRoot\tmp\$($fileName)_dbaChecks_$dateTime-$dbcTestGroup.csv" -Confirm:$false -Force
        }
        $dbcCheckCounter++
    }
}

Write-Progress -Id 1 -Completed -Activity "Completed running main tests."

if (($ScanType -eq "Advanced") -or ($ScanType -eq "DBA")) {
    # Get database statistics from each instance.
    $dbLayoutCounter = 1

    $instanceData.sqlInstance | % {
        $sqlInstance = $_
        Write-Progress -Id 3 -ParentId 0 -Activity "Getting database file layout and latency for $sqlInstance" -PercentComplete ($dbLayoutCounter / $(($instanceData.sqlInstance).Count) * 100)
        $sqlStats = $_ | Invoke-DbaQuery -File "$PSScriptRoot\SQLScripts\CombinedSQLStats.sql" -EnableException

        $sqlStatsArray = @()

        $sqlStats | % {
            $object = [pscustomobject]@{
                SqlInstance                          = $sqlInstance
                Drive                                = $_.Drive
                'database_name'                      = $_.'database_name'
                'physical_name'                      = $_.'physical_name'
                'compatibility_level'                = $_.'compatibility_level'
                'file_size_MB'                       = $_.'file_size_mb'
                'file_size_usedMB'                   = $_.'file_size_usedMB'
                'recovery_model_desc'                = $_.'recovery_model_desc'
                'is_percent_growth'                  = $_.'is_percent_growth'
                'growth_in_increment_of'             = $_.'growth_in_increment_of'
                'next_auto_growth_size_MB'           = $_.'next_auto_growth_size_MB'
                'max_size'                           = $_.'max_size'
                AVGReadLatency_ms                    = $_.'AVGReadLatency_ms'
                AVGWriteLatency_ms                   = $_.'AVGWriteLatency_ms'
                'AVGTotalLatency_ms(Reads + Writes)' = $_.'AVGTotalLatency_ms(Reads + Writes)'
                AvgBytesPerRead                      = $_.'AvgBytesPerRead'
                AvgBytesPerWrite                     = $_.'AvgBytesPerWrite'
                AvgBytesPerTransfer                  = $_.'AvgBytesPerTransfer'
            }

            $sqlStatsArray = [System.Array]$sqlStatsArray + $object
        }

        $sqlStatsWorksheet = "DBStats"
        $sqlStatsTable = "DBStats"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-$ScanType-SQLServerConfigReport-$datetime.xlsx"

        $excel = $sqlStatsArray | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlStatsWorksheet -FreezeTopRow -TableName $sqlStatsTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()
        $dbLayoutCounter++
    }
    Write-Progress -Id 3 -Completed -Activity "Completed getting database file layout."

    # Get the backup history for the instance.
    $dbBackupCounter = 1

    $instanceData.sqlInstance | % {
        Write-Progress -Id 7 -ParentId 0 -Activity "Getting 30-day backup history from $_" -PercentComplete ($dbBackupCounter / $(($instanceData.sqlInstance).Count) * 100)

        # We'll use the '@HoursBack = 720' optional parameter to get the last 30 days of backups. Default is past 7 days (168 hours)
        #$sqlBackupData = $_ | Invoke-DbaQuery -Query "EXEC sp_BlitzBackups @HoursBack = 720" -EnableException
        $sqlBackupData = $_ | Get-DbaDbBackupHistory -Since (Get-Date).AddDays(-30) -IncludeCopyOnly -IncludeMirror | Select *

        if ($sqlBackupData) {
            Write-Host "Backup history data found on $_..." -ForegroundColor Yellow

            $sqlBackupWorksheet = "Backups"
            $sqlBackupTable = "Backups"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-$ScanType-SQLServerConfigReport-$datetime.xlsx"

            $excel = $sqlBackupData | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlBackupWorksheet -FreezeTopRow -TableName $sqlBackupTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $dbBackupCounter++
    }
    Write-Progress -Id 7 -Completed -Activity "Completed retrieving backup history."
}

Write-Progress -id 0 -Completed -Activity "Completed initial run."

if ($ScanType -eq "DBA") {
    # Now, we'll run the DBA specific scripts to get things like Deprecated Features, Active Queries, Top Queries by CPU, etc.
    Write-Progress -Id 0 -Activity "Running SQL scripts and data collections."

    Write-Host "Checking for deprecated features." -ForegroundColor Cyan
    # Get SQL deprecated features in use.
    $dbFeatureCounter = 1
    
    $instanceData | % {
        $sqlInstance = $_.sqlInstance
        Write-Progress -Id 4 -ParentId 0 -Activity "Get deprecated feature use from $_" -PercentComplete ($dbFeatureCounter / $(($instanceData.sqlInstance).Count) * 100)
        $deprecatedFeatures = Get-DbaDeprecatedFeature -SqlInstance $_
    
        if ($deprecatedFeatures) {
            Write-Host "Deprecated feature use detected on $_..." -ForegroundColor Yellow
            $deprecatedFeaturesWorksheet = "Deprecated Feature Use"
            $deprecatedFeaturesTable = "DepFeature"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"
    
            $excel = $deprecatedFeatures | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $deprecatedFeaturesWorksheet -FreezeTopRow -TableName $deprecatedFeaturesTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
    
        $dbFeatureCounter++
    }
    Write-Progress -Id 4 -Completed -Activity "Completed deprecated feature scan."

    # Get Local account privleges from all nodes found.
    $getPrivsArray = @()
    $getPrivsCounter = 1

    $instanceData.ComputerName | % {
        Write-Progress -id 100 -ParentId 0 -Activity "Getting Local Account Privleges for $_..." -Status "$($getPrivsCounter)/$($instanceData.ComputerName)" -PercentComplete ($getPrivsCounter / $($instanceData.ComputerName).Count * 100)
        $srvPrivs = Get-DbaPrivilege -ComputerName $_ | Select *
        $getPrivsArray = [System.Array]$getPrivsArray + $srvPrivs
        $getPrivsCounter++
    }

    if ($getPrivsArray) {
        $dbPrivsWorksheet = "LocalPrivleges"
        $dbPrivsTable = "LocalPrivleges"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"
        $excel = $getPrivsArray | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $dbPrivsWorksheet -FreezeTopRow -TableName $dbPrivsTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()
    }
    Write-Progress -Id 100 -Completed -Activity "Completed getting Local Account Privleges."

    # Get all existing maintenance plans
    $maintPlanCounter = 1
    $maintPlanResultArr = @()

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get maintenance plans from $_" -PercentComplete ($maintPlanCounter / $(($instanceData.sqlInstance).Count) * 100)
        $query = "select * from dbo.sysmaintplan_plans"
        $maintPlans = $_ | Invoke-DbaQuery -Query $query -Database MSDB
        $sqlInstance = $_

        if ($maintPlans) {

            $maintPlans | % {
                $maintPlanObject = [PSCustomObject]@{
                    Instance        = $sqlInstance
                    Name            = $_.name
                    id              = $_.id
                    Description     = $_.description
                    CreateDate      = $_.'create_date'
                    Owner           = $_.owner
                    VersionMajor    = $_.'version_major'
                    VersionMinor    = $_.'version_minor'
                    VersionBuild    = $_.'version_build'
                    VersionComments = $_.'version_comments'
                    FromMSX         = $_.'from_msx'
                    has_targets     = $_.'has_targets'
                }
                $maintPlanResultArr = [System.Array]$maintPlanResultArr + $maintPlanObject
            }
            $maintPlanWorksheet = "Maintenance Plans"
            $maintPlanTable = "MaintPlans"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $maintPlanResultArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $maintPlanWorksheet -FreezeTopRow -TableName $maintPlanTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $maintPlanCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed maintenance plan retrieval."

    # Get top 10 queries by CPU
    $dbTopCPUQueryCounter = 1
    $dbTopCPUArr = @()
    
    $instanceData | % {
        $sqlInstance = $_.sqlInstance
        Write-Host "Gathering Top worst performing queries by CPU from $sqlInstance." -ForegroundColor Yellow
        $activity = "Gathering Top worst performing queries by CPU from $sqlInstance"
        Write-Progress -id 1 -ParentId 0 -Activity $activity -PercentComplete ($dbTopCPUQueryCounter / $(($instanceData.sqlInstance).Count) * 100)
        $dbTopCPUQuery = Get-BlitzCacheResults -sqlInstance $sqlInstance -SortOrder "CPU"

        $dbTopCPUQuery | % {
            $dbTopCPUObject = [PSCustomObject]@{
                InstanceName             = $sqlInstance
                Database                 = $_.'Database Name'
                Cost                     = $_.Cost
                QueryText                = $_.QueryText
                QueryType                = $_.'Query Type'
                Warnings                 = $_.Warnings
                'Execution Count'        = $_.ExecutionCount
                'Executions / Minute'    = $_.'Executions / Minute'
                'Execution Weight'       = $_.'Execution Weight'
                '% Executions (Type)'    = $_.'% Executions (Type)'
                'Serial Desired Memory'  = $_.'Serial Desired Memory'
                'Serial Required Memory' = $_.'Serial Required Memory'
                'Total CPU (ms)'         = $_.'Total CPU (ms)'
                'Avg CPU (ms)'           = $_.'Avg CPU (ms)'
                'CPU Weight'             = $_.'CPU Weight'
                '% CPU (Type)'           = $_.'% CPU (Type)'
                'Total Duration (ms)'    = $_.'Total Duration (ms)'
                'Avg Duration (ms)'      = $_.'Avg Duration (ms)'
                'Duration Weight'        = $_.'Duration Weight'
                '% Duration (Type)'      = $_.'% Duration (Type)'
                'Total Reads'            = $_.'Total Reads'
                'Average Reads'          = $_.'Average Reads'
                'Read Weight'            = $_.'Read Weight'
                '% Reads (Type)'         = $_.'% Reads (Type)'
                'Total Writes'           = $_.'Total Writes'
                'Average Writes'         = $_.'Average Writes'
                'Write Weight'           = $_.'Write Weight'
                '% Writes (Type)'        = $_.'% Writes (Type)'
                'TotalReturnedRows'      = $_.'TotalReturnedRows'
                'AverageReturnedRows'    = $_.'AverageReturnedRows'
                'MinReturnedRows'        = $_.'MinReturnedRows'
                'MaxReturnedRows'        = $_.'MaxReturnedRows'
                'MinGrantKB'             = $_.'MinGrantKB'
                'MaxGrantKB'             = $_.'MaxGrantKB'
                'MinUsedGrantKB'         = $_.'MinUsedGrantKB'
                'MaxUsedGrantKB'         = $_.'MaxUsedGrantKB'
                'PercentMemoryGrantUsed' = $_.'PercentMemoryGrantUsed'
                'AvgMaxMemoryGrant'      = $_.'AvgMaxMemoryGrant'
                'MinSpills'              = $_.'MinSpills'
                'MaxSpills'              = $_.'MaxSpills'
                'TotalSpills'            = $_.'TotalSpills'
                'AvgSpills'              = $_.'AvgSpills'
                'NumberOfPlans'          = $_.'NumberOfPlans'
                'NumberOfDistinctPlans'  = $_.'NumberOfDistinctPlans'
                'Created At'             = $_.'Created At'
                'Last Execution'         = $_.'Last Execution'
                'StatementStartOffset'   = $_.'StatementStartOffset'
                'StatementEndOffset'     = $_.'StatementEndOffset'
                'PlanGenerationNum'      = $_.'PlanGenerationNum'
            }
            $dbTopCPUArr = [System.Array]$dbTopCPUArr + $dbTopCPUObject
        }

        # Export query cache results to spreadsheet.
        $sqlTopCPUQueryWorksheet = "Top By CPU"
        $sqlTopCPUQueryTable = "TopQueriesByCPU"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

        $excel = $dbTopCPUArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlTopCPUQueryWorksheet -FreezeTopRow -TableName $sqlTopCPUQueryTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()

        $dbTopCPUQueryCounter++
    }

    Write-Progress -Id 1 -Completed -Activity "Completed retrieving top worst query performers (CPU)."

    $dbTopReadsQueryCounter = 1
    $dbTopReadsArr = @()
    
    $instanceData | % {
        $sqlInstance = $_.sqlInstance
        Write-Host "Gathering Top worst performing queries by Reads from $sqlInstance." -ForegroundColor Yellow
        $activity = "Gathering Top worst performing queries by Reads from $sqlInstance"
        Write-Progress -id 1 -ParentId 0 -Activity $activity -PercentComplete ($dbTopReadsQueryCounter / $(($instanceData.sqlInstance).Count) * 100)
        $dbTopReadsQuery = Get-BlitzCacheResults -sqlInstance $sqlInstance -SortOrder "Reads"

        $dbTopReadsQuery | % {
            $dbTopReadsObject = [PSCustomObject]@{
                InstanceName             = $sqlInstance
                Database                 = $_.'Database Name'
                Cost                     = $_.Cost
                QueryText                = $_.QueryText
                QueryType                = $_.'Query Type'
                Warnings                 = $_.Warnings
                'Execution Count'        = $_.ExecutionCount
                'Executions / Minute'    = $_.'Executions / Minute'
                'Execution Weight'       = $_.'Execution Weight'
                '% Executions (Type)'    = $_.'% Executions (Type)'
                'Serial Desired Memory'  = $_.'Serial Desired Memory'
                'Serial Required Memory' = $_.'Serial Required Memory'
                'Total CPU (ms)'         = $_.'Total CPU (ms)'
                'Avg CPU (ms)'           = $_.'Avg CPU (ms)'
                'CPU Weight'             = $_.'CPU Weight'
                '% CPU (Type)'           = $_.'% CPU (Type)'
                'Total Duration (ms)'    = $_.'Total Duration (ms)'
                'Avg Duration (ms)'      = $_.'Avg Duration (ms)'
                'Duration Weight'        = $_.'Duration Weight'
                '% Duration (Type)'      = $_.'% Duration (Type)'
                'Total Reads'            = $_.'Total Reads'
                'Average Reads'          = $_.'Average Reads'
                'Read Weight'            = $_.'Read Weight'
                '% Reads (Type)'         = $_.'% Reads (Type)'
                'Total Writes'           = $_.'Total Writes'
                'Average Writes'         = $_.'Average Writes'
                'Write Weight'           = $_.'Write Weight'
                '% Writes (Type)'        = $_.'% Writes (Type)'
                'TotalReturnedRows'      = $_.'TotalReturnedRows'
                'AverageReturnedRows'    = $_.'AverageReturnedRows'
                'MinReturnedRows'        = $_.'MinReturnedRows'
                'MaxReturnedRows'        = $_.'MaxReturnedRows'
                'MinGrantKB'             = $_.'MinGrantKB'
                'MaxGrantKB'             = $_.'MaxGrantKB'
                'MinUsedGrantKB'         = $_.'MinUsedGrantKB'
                'MaxUsedGrantKB'         = $_.'MaxUsedGrantKB'
                'PercentMemoryGrantUsed' = $_.'PercentMemoryGrantUsed'
                'AvgMaxMemoryGrant'      = $_.'AvgMaxMemoryGrant'
                'MinSpills'              = $_.'MinSpills'
                'MaxSpills'              = $_.'MaxSpills'
                'TotalSpills'            = $_.'TotalSpills'
                'AvgSpills'              = $_.'AvgSpills'
                'NumberOfPlans'          = $_.'NumberOfPlans'
                'NumberOfDistinctPlans'  = $_.'NumberOfDistinctPlans'
                'Created At'             = $_.'Created At'
                'Last Execution'         = $_.'Last Execution'
                'StatementStartOffset'   = $_.'StatementStartOffset'
                'StatementEndOffset'     = $_.'StatementEndOffset'
                'PlanGenerationNum'      = $_.'PlanGenerationNum'
            }
            $dbTopReadsArr = [System.Array]$dbTopReadsArr + $dbTopReadsObject
        }

        # Export query cache results to sheet.
        $sqlTopReadsQueryWorksheet = "Top By Reads"
        $sqlTopReadsQueryTable = "TopByReads"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

        $excel = $dbTopReadsArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlTopReadsQueryWorksheet -FreezeTopRow -TableName $sqlTopReadsQueryTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()

        $dbTopReadsQueryCounter++
    }

    Write-Progress -Id 1 -Completed -Activity "Completed retrieving top worst query performers (Reads)."

    $dbTopWritesQueryCounter = 1
    $dbTopWritesArr = @()
    
    $instanceData | % {
        $sqlInstance = $_.sqlInstance
        Write-Host "Gathering Top worst performing queries by Writes from $sqlInstance." -ForegroundColor Yellow
        $activity = "Gathering Top worst performing queries by Writes from $sqlInstance"
        Write-Progress -id 1 -ParentId 0 -Activity $activity -PercentComplete ($dbTopWritesQueryCounter / $(($instanceData.sqlInstance).Count) * 100)
        $dbTopWritesQuery = Get-BlitzCacheResults -sqlInstance $sqlInstance -SortOrder "Writes"

        $dbTopWritesQuery | % {
            $dbTopWritesObject = [PSCustomObject]@{
                InstanceName             = $sqlInstance
                Database                 = $_.'Database Name'
                Cost                     = $_.Cost
                QueryText                = $_.QueryText
                QueryType                = $_.'Query Type'
                Warnings                 = $_.Warnings
                'Execution Count'        = $_.ExecutionCount
                'Executions / Minute'    = $_.'Executions / Minute'
                'Execution Weight'       = $_.'Execution Weight'
                '% Executions (Type)'    = $_.'% Executions (Type)'
                'Serial Desired Memory'  = $_.'Serial Desired Memory'
                'Serial Required Memory' = $_.'Serial Required Memory'
                'Total CPU (ms)'         = $_.'Total CPU (ms)'
                'Avg CPU (ms)'           = $_.'Avg CPU (ms)'
                'CPU Weight'             = $_.'CPU Weight'
                '% CPU (Type)'           = $_.'% CPU (Type)'
                'Total Duration (ms)'    = $_.'Total Duration (ms)'
                'Avg Duration (ms)'      = $_.'Avg Duration (ms)'
                'Duration Weight'        = $_.'Duration Weight'
                '% Duration (Type)'      = $_.'% Duration (Type)'
                'Total Reads'            = $_.'Total Reads'
                'Average Reads'          = $_.'Average Reads'
                'Read Weight'            = $_.'Read Weight'
                '% Reads (Type)'         = $_.'% Reads (Type)'
                'Total Writes'           = $_.'Total Writes'
                'Average Writes'         = $_.'Average Writes'
                'Write Weight'           = $_.'Write Weight'
                '% Writes (Type)'        = $_.'% Writes (Type)'
                'TotalReturnedRows'      = $_.'TotalReturnedRows'
                'AverageReturnedRows'    = $_.'AverageReturnedRows'
                'MinReturnedRows'        = $_.'MinReturnedRows'
                'MaxReturnedRows'        = $_.'MaxReturnedRows'
                'MinGrantKB'             = $_.'MinGrantKB'
                'MaxGrantKB'             = $_.'MaxGrantKB'
                'MinUsedGrantKB'         = $_.'MinUsedGrantKB'
                'MaxUsedGrantKB'         = $_.'MaxUsedGrantKB'
                'PercentMemoryGrantUsed' = $_.'PercentMemoryGrantUsed'
                'AvgMaxMemoryGrant'      = $_.'AvgMaxMemoryGrant'
                'MinSpills'              = $_.'MinSpills'
                'MaxSpills'              = $_.'MaxSpills'
                'TotalSpills'            = $_.'TotalSpills'
                'AvgSpills'              = $_.'AvgSpills'
                'NumberOfPlans'          = $_.'NumberOfPlans'
                'NumberOfDistinctPlans'  = $_.'NumberOfDistinctPlans'
                'Created At'             = $_.'Created At'
                'Last Execution'         = $_.'Last Execution'
                'StatementStartOffset'   = $_.'StatementStartOffset'
                'StatementEndOffset'     = $_.'StatementEndOffset'
                'PlanGenerationNum'      = $_.'PlanGenerationNum'
            }
            $dbTopWritesArr = [System.Array]$dbTopWritesArr + $dbTopWritesObject
        }

        # Export query cache results to sheet.
        $sqlTopWritesQueryWorksheet = "Top By Writes"
        $sqlTopWritesQueryTable = "TopByWrites"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

        $excel = $dbTopWritesArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlTopWritesQueryWorksheet -FreezeTopRow -TableName $sqlTopWritesQueryTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()

        $dbTopWritesQueryCounter++
    }

    Write-Progress -Id 1 -Completed -Activity "Completed retrieving top worst query performers (Writes)."

    $dbTopDurationQueryCounter = 1
    $dbTopDurationArr = @()
    
    $instanceData | % {
        $sqlInstance = $_.sqlInstance
        Write-Host "Gathering Top worst performing queries by Duration from $sqlInstance." -ForegroundColor Yellow
        $activity = "Gathering Top worst performing queries by Duration from $sqlInstance"
        Write-Progress -id 1 -ParentId 0 -Activity $activity -PercentComplete ($dbTopDurationQueryCounter / $(($instanceData.sqlInstance).Count) * 100)
        $dbTopDurationQuery = Get-BlitzCacheResults -sqlInstance $sqlInstance -SortOrder "Duration"

        $dbTopDurationQuery | % {
            $dbTopDurationObject = [PSCustomObject]@{
                InstanceName             = $sqlInstance
                Database                 = $_.'Database Name'
                Cost                     = $_.Cost
                QueryText                = $_.QueryText
                QueryType                = $_.'Query Type'
                Warnings                 = $_.Warnings
                'Execution Count'        = $_.ExecutionCount
                'Executions / Minute'    = $_.'Executions / Minute'
                'Execution Weight'       = $_.'Execution Weight'
                '% Executions (Type)'    = $_.'% Executions (Type)'
                'Serial Desired Memory'  = $_.'Serial Desired Memory'
                'Serial Required Memory' = $_.'Serial Required Memory'
                'Total CPU (ms)'         = $_.'Total CPU (ms)'
                'Avg CPU (ms)'           = $_.'Avg CPU (ms)'
                'CPU Weight'             = $_.'CPU Weight'
                '% CPU (Type)'           = $_.'% CPU (Type)'
                'Total Duration (ms)'    = $_.'Total Duration (ms)'
                'Avg Duration (ms)'      = $_.'Avg Duration (ms)'
                'Duration Weight'        = $_.'Duration Weight'
                '% Duration (Type)'      = $_.'% Duration (Type)'
                'Total Reads'            = $_.'Total Reads'
                'Average Reads'          = $_.'Average Reads'
                'Read Weight'            = $_.'Read Weight'
                '% Reads (Type)'         = $_.'% Reads (Type)'
                'Total Writes'           = $_.'Total Writes'
                'Average Writes'         = $_.'Average Writes'
                'Write Weight'           = $_.'Write Weight'
                '% Writes (Type)'        = $_.'% Writes (Type)'
                'TotalReturnedRows'      = $_.'TotalReturnedRows'
                'AverageReturnedRows'    = $_.'AverageReturnedRows'
                'MinReturnedRows'        = $_.'MinReturnedRows'
                'MaxReturnedRows'        = $_.'MaxReturnedRows'
                'MinGrantKB'             = $_.'MinGrantKB'
                'MaxGrantKB'             = $_.'MaxGrantKB'
                'MinUsedGrantKB'         = $_.'MinUsedGrantKB'
                'MaxUsedGrantKB'         = $_.'MaxUsedGrantKB'
                'PercentMemoryGrantUsed' = $_.'PercentMemoryGrantUsed'
                'AvgMaxMemoryGrant'      = $_.'AvgMaxMemoryGrant'
                'MinSpills'              = $_.'MinSpills'
                'MaxSpills'              = $_.'MaxSpills'
                'TotalSpills'            = $_.'TotalSpills'
                'AvgSpills'              = $_.'AvgSpills'
                'NumberOfPlans'          = $_.'NumberOfPlans'
                'NumberOfDistinctPlans'  = $_.'NumberOfDistinctPlans'
                'Created At'             = $_.'Created At'
                'Last Execution'         = $_.'Last Execution'
                'StatementStartOffset'   = $_.'StatementStartOffset'
                'StatementEndOffset'     = $_.'StatementEndOffset'
                'PlanGenerationNum'      = $_.'PlanGenerationNum'
            }
            $dbTopDurationArr = [System.Array]$dbTopDurationArr + $dbTopDurationObject
        }

        # Export query cache results to sheet.
        $sqlTopDurationQueryWorksheet = "Top By Duration"
        $sqlTopDurationQueryTable = "TopByDuration"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

        $excel = $dbTopDurationArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlTopDurationQueryWorksheet -FreezeTopRow -TableName $sqlTopDurationQueryTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()

        $dbTopDurationQueryCounter++
    }

    Write-Progress -Id 1 -Completed -Activity "Completed retrieving top worst query performers (Duration)."

    $dbTopExecutionsQueryCounter = 1
    $dbTopExecutionArr = @()
    
    $instanceData | % {
        $sqlInstance = $_.sqlInstance
        Write-Host "Gathering Top worst performing queries by Executions from $sqlInstance." -ForegroundColor Yellow
        $activity = "Gathering Top worst performing queries by Executions from $sqlInstance"
        Write-Progress -id 1 -ParentId 0 -Activity $activity -PercentComplete ($dbTopExecutionsQueryCounter / $(($instanceData.sqlInstance).Count) * 100)
        $dbTopExecutionsQuery = Get-BlitzCacheResults -sqlInstance $sqlInstance -SortOrder "Executions"

        $dbTopExecutionsQuery | % {
            $dbTopExecutionObject = [PSCustomObject]@{
                InstanceName             = $sqlInstance
                Database                 = $_.'Database Name'
                Cost                     = $_.Cost
                QueryText                = $_.QueryText
                QueryType                = $_.'Query Type'
                Warnings                 = $_.Warnings
                'Execution Count'        = $_.ExecutionCount
                'Executions / Minute'    = $_.'Executions / Minute'
                'Execution Weight'       = $_.'Execution Weight'
                '% Executions (Type)'    = $_.'% Executions (Type)'
                'Serial Desired Memory'  = $_.'Serial Desired Memory'
                'Serial Required Memory' = $_.'Serial Required Memory'
                'Total CPU (ms)'         = $_.'Total CPU (ms)'
                'Avg CPU (ms)'           = $_.'Avg CPU (ms)'
                'CPU Weight'             = $_.'CPU Weight'
                '% CPU (Type)'           = $_.'% CPU (Type)'
                'Total Duration (ms)'    = $_.'Total Duration (ms)'
                'Avg Duration (ms)'      = $_.'Avg Duration (ms)'
                'Duration Weight'        = $_.'Duration Weight'
                '% Duration (Type)'      = $_.'% Duration (Type)'
                'Total Reads'            = $_.'Total Reads'
                'Average Reads'          = $_.'Average Reads'
                'Read Weight'            = $_.'Read Weight'
                '% Reads (Type)'         = $_.'% Reads (Type)'
                'Total Writes'           = $_.'Total Writes'
                'Average Writes'         = $_.'Average Writes'
                'Write Weight'           = $_.'Write Weight'
                '% Writes (Type)'        = $_.'% Writes (Type)'
                'TotalReturnedRows'      = $_.'TotalReturnedRows'
                'AverageReturnedRows'    = $_.'AverageReturnedRows'
                'MinReturnedRows'        = $_.'MinReturnedRows'
                'MaxReturnedRows'        = $_.'MaxReturnedRows'
                'MinGrantKB'             = $_.'MinGrantKB'
                'MaxGrantKB'             = $_.'MaxGrantKB'
                'MinUsedGrantKB'         = $_.'MinUsedGrantKB'
                'MaxUsedGrantKB'         = $_.'MaxUsedGrantKB'
                'PercentMemoryGrantUsed' = $_.'PercentMemoryGrantUsed'
                'AvgMaxMemoryGrant'      = $_.'AvgMaxMemoryGrant'
                'MinSpills'              = $_.'MinSpills'
                'MaxSpills'              = $_.'MaxSpills'
                'TotalSpills'            = $_.'TotalSpills'
                'AvgSpills'              = $_.'AvgSpills'
                'NumberOfPlans'          = $_.'NumberOfPlans'
                'NumberOfDistinctPlans'  = $_.'NumberOfDistinctPlans'
                'Created At'             = $_.'Created At'
                'Last Execution'         = $_.'Last Execution'
                'StatementStartOffset'   = $_.'StatementStartOffset'
                'StatementEndOffset'     = $_.'StatementEndOffset'
                'PlanGenerationNum'      = $_.'PlanGenerationNum'
            }
            $dbTopExecutionArr = [System.Array]$dbTopExecutionArr + $dbTopExecutionObject
        }

        # Export query cache results to sheet.
        $sqlTopExecutionsQueryWorksheet = "Top By Executions"
        $sqlTopExecutionsQueryTable = "TopByExecutions"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

        $excel = $dbTopExecutionArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlTopExecutionsQueryWorksheet -FreezeTopRow -TableName $sqlTopExecutionsQueryTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()

        $dbTopExecutionsQueryCounter++
    }

    Write-Progress -Id 1 -Completed -Activity "Completed retrieving top worst query performers (Executions)."

    $dbTopMemoryGrantQueryCounter = 1
    $dbTopMemoryGrantArr = @()
    
    $instanceData | % {
        $sqlInstance = $_.sqlInstance
        Write-Host "Gathering Top worst performing queries by Memory Grant from $sqlInstance." -ForegroundColor Yellow
        $activity = "Gathering Top worst performing queries by Memory Grant from $sqlInstance"
        Write-Progress -id 1 -ParentId 0 -Activity $activity -PercentComplete ($dbTopMemoryGrantQueryCounter / $(($instanceData.sqlInstance).Count) * 100)
        $dbTopMemoryGrantQuery = Get-BlitzCacheResults -sqlInstance $sqlInstance -SortOrder "Memory Grant"

        $dbTopMemoryGrantQuery | % {
            $dbTopMemGrantQueryObject = [PSCustomObject]@{
                InstanceName             = $sqlInstance
                Database                 = $_.'Database Name'
                Cost                     = $_.Cost
                QueryText                = $_.QueryText
                QueryType                = $_.'Query Type'
                Warnings                 = $_.Warnings
                'Execution Count'        = $_.ExecutionCount
                'Executions / Minute'    = $_.'Executions / Minute'
                'Execution Weight'       = $_.'Execution Weight'
                '% Executions (Type)'    = $_.'% Executions (Type)'
                'Serial Desired Memory'  = $_.'Serial Desired Memory'
                'Serial Required Memory' = $_.'Serial Required Memory'
                'Total CPU (ms)'         = $_.'Total CPU (ms)'
                'Avg CPU (ms)'           = $_.'Avg CPU (ms)'
                'CPU Weight'             = $_.'CPU Weight'
                '% CPU (Type)'           = $_.'% CPU (Type)'
                'Total Duration (ms)'    = $_.'Total Duration (ms)'
                'Avg Duration (ms)'      = $_.'Avg Duration (ms)'
                'Duration Weight'        = $_.'Duration Weight'
                '% Duration (Type)'      = $_.'% Duration (Type)'
                'Total Reads'            = $_.'Total Reads'
                'Average Reads'          = $_.'Average Reads'
                'Read Weight'            = $_.'Read Weight'
                '% Reads (Type)'         = $_.'% Reads (Type)'
                'Total Writes'           = $_.'Total Writes'
                'Average Writes'         = $_.'Average Writes'
                'Write Weight'           = $_.'Write Weight'
                '% Writes (Type)'        = $_.'% Writes (Type)'
                'TotalReturnedRows'      = $_.'TotalReturnedRows'
                'AverageReturnedRows'    = $_.'AverageReturnedRows'
                'MinReturnedRows'        = $_.'MinReturnedRows'
                'MaxReturnedRows'        = $_.'MaxReturnedRows'
                'MinGrantKB'             = $_.'MinGrantKB'
                'MaxGrantKB'             = $_.'MaxGrantKB'
                'MinUsedGrantKB'         = $_.'MinUsedGrantKB'
                'MaxUsedGrantKB'         = $_.'MaxUsedGrantKB'
                'PercentMemoryGrantUsed' = $_.'PercentMemoryGrantUsed'
                'AvgMaxMemoryGrant'      = $_.'AvgMaxMemoryGrant'
                'MinSpills'              = $_.'MinSpills'
                'MaxSpills'              = $_.'MaxSpills'
                'TotalSpills'            = $_.'TotalSpills'
                'AvgSpills'              = $_.'AvgSpills'
                'NumberOfPlans'          = $_.'NumberOfPlans'
                'NumberOfDistinctPlans'  = $_.'NumberOfDistinctPlans'
                'Created At'             = $_.'Created At'
                'Last Execution'         = $_.'Last Execution'
                'StatementStartOffset'   = $_.'StatementStartOffset'
                'StatementEndOffset'     = $_.'StatementEndOffset'
                'PlanGenerationNum'      = $_.'PlanGenerationNum'
            }
            $dbTopMemoryGrantArr = [System.Array]$dbTopMemoryGrantArr + $dbTopMemGrantQueryObject
        }

        # Export query cache results to sheet.
        $sqlTopMemoryGrantQueryWorksheet = "Top By Memory Grants"
        $sqlTopMemoryGrantQueryTable = "TopByMemGrant"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

        $excel = $dbTopMemoryGrantArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlTopMemoryGrantQueryWorksheet -FreezeTopRow -TableName $sqlTopMemoryGrantQueryTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()

        $dbTopMemoryGrantQueryCounter++
    }

    Write-Progress -Id 1 -Completed -Activity "Completed retrieving top worst query performers (Memory Grant)."

    # Get top recent Compilations
    $dbTopRecentCompsQueryCounter = 1
    $dbTopRecentCompsArr = @()
    
    $instanceData | % {
        $sqlInstance = $_.sqlInstance
        Write-Host "Gathering Top worst performing queries by Recent Compilations from $sqlInstance." -ForegroundColor Yellow
        $activity = "Gathering Top worst performing queries by Recent Compilations from $sqlInstance"
        Write-Progress -id 1 -ParentId 0 -Activity $activity -PercentComplete ($dbTopRecentCompsQueryCounter / $(($instanceData.sqlInstance).Count) * 100)
        $dbTopRecentCompsQuery = Get-BlitzCacheResults -sqlInstance $sqlInstance -SortOrder "Recent Compilations"

        $dbTopRecentCompsQuery | % {
            $dbTopRecentCompsQueryObject = [PSCustomObject]@{
                InstanceName             = $sqlInstance
                Database                 = $_.'Database Name'
                Cost                     = $_.Cost
                QueryText                = $_.QueryText
                QueryType                = $_.'Query Type'
                Warnings                 = $_.Warnings
                'Execution Count'        = $_.ExecutionCount
                'Executions / Minute'    = $_.'Executions / Minute'
                'Execution Weight'       = $_.'Execution Weight'
                '% Executions (Type)'    = $_.'% Executions (Type)'
                'Serial Desired Memory'  = $_.'Serial Desired Memory'
                'Serial Required Memory' = $_.'Serial Required Memory'
                'Total CPU (ms)'         = $_.'Total CPU (ms)'
                'Avg CPU (ms)'           = $_.'Avg CPU (ms)'
                'CPU Weight'             = $_.'CPU Weight'
                '% CPU (Type)'           = $_.'% CPU (Type)'
                'Total Duration (ms)'    = $_.'Total Duration (ms)'
                'Avg Duration (ms)'      = $_.'Avg Duration (ms)'
                'Duration Weight'        = $_.'Duration Weight'
                '% Duration (Type)'      = $_.'% Duration (Type)'
                'Total Reads'            = $_.'Total Reads'
                'Average Reads'          = $_.'Average Reads'
                'Read Weight'            = $_.'Read Weight'
                '% Reads (Type)'         = $_.'% Reads (Type)'
                'Total Writes'           = $_.'Total Writes'
                'Average Writes'         = $_.'Average Writes'
                'Write Weight'           = $_.'Write Weight'
                '% Writes (Type)'        = $_.'% Writes (Type)'
                'TotalReturnedRows'      = $_.'TotalReturnedRows'
                'AverageReturnedRows'    = $_.'AverageReturnedRows'
                'MinReturnedRows'        = $_.'MinReturnedRows'
                'MaxReturnedRows'        = $_.'MaxReturnedRows'
                'MinGrantKB'             = $_.'MinGrantKB'
                'MaxGrantKB'             = $_.'MaxGrantKB'
                'MinUsedGrantKB'         = $_.'MinUsedGrantKB'
                'MaxUsedGrantKB'         = $_.'MaxUsedGrantKB'
                'PercentMemoryGrantUsed' = $_.'PercentMemoryGrantUsed'
                'AvgMaxMemoryGrant'      = $_.'AvgMaxMemoryGrant'
                'MinSpills'              = $_.'MinSpills'
                'MaxSpills'              = $_.'MaxSpills'
                'TotalSpills'            = $_.'TotalSpills'
                'AvgSpills'              = $_.'AvgSpills'
                'NumberOfPlans'          = $_.'NumberOfPlans'
                'NumberOfDistinctPlans'  = $_.'NumberOfDistinctPlans'
                'Created At'             = $_.'Created At'
                'Last Execution'         = $_.'Last Execution'
                'StatementStartOffset'   = $_.'StatementStartOffset'
                'StatementEndOffset'     = $_.'StatementEndOffset'
                'PlanGenerationNum'      = $_.'PlanGenerationNum'
            }
            $dbTopRecentCompsArr = [System.Array]$dbTopRecentCompsArr + $dbTopRecentCompsQueryObject
        }
        # Export query cache results to sheet.
        $sqlTopRecentCompsQueryWorksheet = "Top By Recent Compilations"
        $sqlTopRecentCompsQueryTable = "TopByRecentComps"

        $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

        $excel = $dbTopRecentCompsArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlTopRecentCompsQueryWorksheet -FreezeTopRow -TableName $sqlTopRecentCompsQueryTable -PassThru -Append
        $excel.Save() ; $excel.Dispose()

        $dbTopRecentCompsQueryCounter++
    }

    Write-Progress -Id 1 -Completed -Activity "Completed retrieving top worst query performers (Recent Compilations)."

    # Get currently running query data and associated statistics.
    $dbCurrentQueryCounter = 1

    $instanceData.sqlInstance | % {
        Write-Progress -Id 6 -ParentId 0 -Activity "Getting currently active queries from $_" -PercentComplete ($dbCurrentQueryCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting currently active queries from $_" -ForegroundColor Yellow
        $sqlQueryWho = $_ | Invoke-DbaQuery -File "$PSScriptRoot\SQLScripts\GetActiveQueries.sql" -EnableException
        $sqlInstance = $_
        $instanceRunningQueries = @()

        if ($sqlQueryWho) {
            Write-Host "Active query data found on $_..." -ForegroundColor Yellow
        
            $sqlQueryWho | % {
                $sqlQueryDataObject = [pscustomobject]@{
                    'InstanceName' = $sqlInstance
                    'status'       = $_.status
                    'command'      = $_.command
                    'cpu_time'     = $_.'cpu_time'
                    'elapsed_time' = $_.'total_elapsed_time'
                    'query_text'   = $_.text                
                }
                $instanceRunningQueries = [System.Array]$instanceRunningQueries + $sqlQueryDataObject
            }

            $sqlQueryWorksheet = "ActiveQueries"
            $sqlQueryTable = "ActiveQueries"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $instanceRunningQueries | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlQueryWorksheet -FreezeTopRow -TableName $sqlQueryTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        else {
            Write-Host "No Active query data found on $_..." -ForegroundColor Yellow
            
            $sqlQueryDataObject = [pscustomobject]@{
                'InstanceName' = $sqlInstance
                'status'       = "No Active queries found."
                'command'      = "N/A"
                'cpu_time'     = "N/A"
                'elapsed_time' = "N/A"
                'query_text'   = "No Active queries found."
            }
            $instanceRunningQueries = [System.Array]$instanceRunningQueries + $sqlQueryDataObject

            $sqlQueryWorksheet = "ActiveQueries"
            $sqlQueryTable = "ActiveQueries"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $instanceRunningQueries | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlQueryWorksheet -FreezeTopRow -TableName $sqlQueryTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $dbCurrentQueryCounter++
    }
    Write-Progress -Id 6 -Completed -Activity "Completed scanning for currently running queries."

    # Get any current SQL deadlocks
    $dbDeadlockCounter = 1
    $dbDeadlockArr = @()

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get lock and deadlock scan from $_" -PercentComplete ($dbDeadlockCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting locks and deadlocks from $_" -ForegroundColor Yellow
        $sqlLocks = $_ | Invoke-DbaQuery -Query "EXEC sp_BlitzLock"
        $sqlInstance = $_
    
        if ($sqlLocks) {
            Write-Host "SQL locks and deadlocks found on $_..." -ForegroundColor Yellow

            $sqlLocks | % {
                $sqlDeadlockObject = [PSCustomObject]@{
                    InstanceName              = $sqlInstance
                    DatabaseName              = $_.'database_name'
                    DeadlockType              = $_.'deadlock_type'
                    DeadlockGroup             = $_.'deadlock_group'
                    EventDate                 = $_.'event_date'
                    ObjectNames               = $_.'object_names'
                    IsolationLevel            = $_.isolation_Level
                    OwnerMode                 = $_.'owner_mode'
                    WaiterMode                = $_.'waiter_mode'
                    TransactionCount          = $_.'transaction_count'
                    LoginName                 = $_.'login_name'
                    HostName                  = $_.'host_name'
                    ClientApp                 = $_.'client_app'
                    WaitTime                  = $_.'wait_time'
                    Priority                  = $_.priority
                    LogUsed                   = $_.'log_used'
                    'last_tran_started'       = $_.'last_tran_started'
                    'last_batch_started'      = $_.'last_batch_started'
                    'last_batch_completed'    = $_.'last_batch_completed'
                    'transaction_name'        = $_.'transaction_name'
                    'owner_waiter_type'       = $_.'owner_waiter_type'
                    'owner_activity'          = $_.'owner_activity'
                    'owner_waiter_activity'   = $_.'owner_waiter_activity'
                    'owner_merging'           = $_.'owner_merging'
                    'owner_spilling'          = $_.'owner_spilling'
                    'owner_waiting_to_close'  = $_.'owner_waiting_to_close'
                    'waiter_waiter_type'      = $_.'waiter_waiter_type'
                    'waiter_owner_activity'   = $_.'waiter_owner_activity'
                    'waiter_waiter_activity'  = $_.'waiter_waiter_activity'
                    'waiter_merging'          = $_.'waiter_merging'
                    'waiter_spilling'         = $_.'waiter_spilling'
                    'waiter_waiting_to_close' = 'waiter_waiting_to_close'
                    Query                     = $_.query
                }

                $dbDeadlockArr = [System.Array]$dbDeadlockArr + $sqlDeadlockObject
            }

            $sqlLockWorksheet = "Locks And Deadlocks"
            $sqlLockTable = "LocksAndDeadlocks"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $dbDeadlockArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlLockWorksheet -FreezeTopRow -TableName $sqlLockTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        } 
        $dbDeadlockCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed lock and deadlock scan."

    # Get table and index compression (heap and clustered)
    $dbTableAndIndexCompressionCounter = 1

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get table data and index compression for heap and clustered indexes from $_" -PercentComplete ($dbTableAndIndexCompressionCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting table data and index compression for heap and clustered indexes from $_" -ForegroundColor Yellow
        $sqlIndexCompression = $_ | Invoke-DbaQuery -File "$PSScriptRoot\SQLScripts\TableDataAndIndexCompressionHeapAndClustered.sql" -EnableException
        $sqlInstance = $_
        $instanceClusteredIndexCompression = @()
    
        if ($sqlIndexCompression) {
            $sqlIndexCompression | % {
                $sqlCompressionDataObject = [pscustomobject]@{
                    'InstanceName' = $sqlInstance
                    'Table'        = $_.table
                    'index'        = $_.index
                    'partition'    = $_.partition
                    'compression'  = $_.compression                              
                }
                
                $instanceIndexCompression = [System.Array]$instanceIndexCompression + $sqlCompressionDataObject
            }

            $sqlCompressionWorksheet = "HeapClusteredIndexCompression"
            $sqlCompressionTable = "HeapClusteredIndexCompression"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $instanceIndexCompression | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlCompressionWorksheet -FreezeTopRow -TableName $sqlCompressionTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        else {
            $sqlCompressionDataObject = [pscustomobject]@{
                'InstanceName' = $sqlInstance
                'Table'        = "No heap or clustered indexes found."
                'index'        = "No heap or clustered indexes found."
                'partition'    = "No heap or clustered indexes found."
                'compression'  = "No heap or clustered indexes found."       
            }
                
            $instanceIndexCompression = [System.Array]$instanceIndexCompression + $sqlCompressionDataObject

            $sqlCompressionWorksheet = "HeapClusteredIndexCompression"
            $sqlCompressionTable = "HeapClusteredIndexCompression"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $instanceIndexCompression | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlCompressionWorksheet -FreezeTopRow -TableName $sqlCompressionTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $dbTableAndIndexCompressionCounter++
    }

    Write-Progress -Id 5 -Completed -Activity "Completed heap and clustered index compression scan."

    # Get non-clustered index compression
    $dbNonClusteredIndexCompressionCounter = 1

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get non-clustered indexes $_" -PercentComplete ($dbNonClusteredIndexCompressionCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting non-clustered indexes from $_" -ForegroundColor Yellow
        $sqlNonClusteredIndexCompression = $_ | Invoke-DbaQuery -File "$PSScriptRoot\SQLScripts\TableDataAndIndexCompressionHeapAndClustered.sql" -EnableException
        $sqlInstance = $_
        $instanceNonClusteredIndexCompression = @()
    
        if ($sqlNonClusteredIndexCompression) {
            $sqlNonClusteredIndexCompression | % {
                $sqlNonClusteredIndexObject = [pscustomobject]@{
                    'InstanceName' = $sqlInstance
                    'Table'        = $_.table
                    'index'        = $_.index
                    'partition'    = $_.partition
                    'compression'  = $_.compression                              
                }
                
                $instanceNonClusteredIndexCompression = [System.Array]$instanceNonClusteredIndexCompression + $sqlNonClusteredIndexObject
            }

            $sqlNonClusteredCompressionWorksheet = "NonClusteredIndexCompression"
            $sqlNonClusteredCompressionTable = "NonClusteredIndexCompression"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $instanceNonClusteredIndexCompression | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlNonClusteredCompressionWorksheet -FreezeTopRow -TableName $sqlNonClusteredCompressionTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        else {

            $sqlNonClusteredIndexObject = [pscustomobject]@{
                'InstanceName' = $sqlInstance
                'Table'        = "Non-clustered indexes not found."
                'index'        = "Non-clustered indexes not found."
                'partition'    = "Non-clustered indexes not found."
                'compression'  = "Non-clustered indexes not found."          
            }
                
            $instanceNonClusteredIndexCompression = [System.Array]$instanceNonClusteredIndexCompression + $sqlNonClusteredIndexObject
    
            $sqlNonClusteredCompressionWorksheet = "NonClusteredIndexCompression"
            $sqlNonClusteredCompressionTable = "NonClusteredIndexCompression"
    
            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"
    
            $excel = $instanceNonClusteredIndexCompression | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlNonClusteredCompressionWorksheet -FreezeTopRow -TableName $sqlNonClusteredCompressionTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $dbNonClusteredIndexCompressionCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed non-clustered index scan."

    # Get partitioned tables with non-aligned indexes
    $dbPartTabNonAlignedIndexCounter = 1

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get partitioned tables with non-aligned indexes from $_" -PercentComplete ($dbPartTabNonAlignedIndexCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting partitioned tables with non-aligned indexes from $_" -ForegroundColor Yellow
        $dbPartTabNonAlignedIndexes = $_ | Invoke-DbaQuery -File "$PSScriptRoot\SQLScripts\GetParitionedTablesWithNonAlignedIndexes.sql" -EnableException
        $sqlInstance = $_
        $instanceDbPartTabNonAlignedIndexes = @()
    
        if ($dbPartTabNonAlignedIndexes) {
            $dbPartTabNonAlignedIndexes | % {
                $dbPartTabNonAlignedIndexObject = [pscustomobject]@{
                    'InstanceName'      = $sqlInstance
                    'DBName'            = $_.DBName
                    'SchemaName'        = $_.SchemaName
                    'ObjectName'        = $_.'object_name'
                    'IndexName'         = $_.'index_name'
                    'TypeDesc'          = $_.'type_desc'
                    'DataSpaceName'     = $_.DataSpaceName
                    'DataSpaceTypeDesc' = $_.DataSpaceTypeDesc
                    'UserSeeks'         = $_.'user_seeks'
                    'UserScans'         = $_.'user_scans'
                    'UserLookups'       = $_.'user_lookups'
                    'UserUpdates'       = $_.'user_updates'
                    'LastUserSeek'      = $_.'last_user_seek'
                    'LastUserUpdate'    = $_.'last_user_update'
                }
                
                $instanceDbPartTabNonAlignedIndexes = [System.Array]$instanceDbPartTabNonAlignedIndexes + $dbPartTabNonAlignedIndexObject
            }

            $sqlNonClusteredCompressionWorksheet = "NonAlignedIndexes"
            $sqlNonClusteredCompressionTable = "NonAlignedIndexes"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $instanceDbPartTabNonAlignedIndexes | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlNonClusteredCompressionWorksheet -FreezeTopRow -TableName $sqlNonClusteredCompressionTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        else {

            $dbPartTabNonAlignedIndexObject = [pscustomobject]@{
                'InstanceName'      = $sqlInstance
                'DBName'            = "Instance has no non-aligned indexes."
                'SchemaName'        = "Instance has no non-aligned indexes."
                'ObjectName'        = "Instance has no non-aligned indexes."
                'IndexName'         = "Instance has no non-aligned indexes."
                'TypeDesc'          = "Instance has no non-aligned indexes."
                'DataSpaceName'     = "Instance has no non-aligned indexes."
                'DataSpaceTypeDesc' = "Instance has no non-aligned indexes."
                'UserSeeks'         = "Instance has no non-aligned indexes."
                'UserScans'         = "Instance has no non-aligned indexes."
                'UserLookups'       = "Instance has no non-aligned indexes."
                'UserUpdates'       = "Instance has no non-aligned indexes."
                'LastUserSeek'      = "Instance has no non-aligned indexes."
                'LastUserUpdate'    = "Instance has no non-aligned indexes."
            }
                
            $instanceDbPartTabNonAlignedIndexes = [System.Array]$instanceDbPartTabNonAlignedIndexes + $dbPartTabNonAlignedIndexObject

            $sqlNonClusteredCompressionWorksheet = "NonAlignedIndexes"
            $sqlNonClusteredCompressionTable = "NonAlignedIndexes"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $instanceDbPartTabNonAlignedIndexes | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlNonClusteredCompressionWorksheet -FreezeTopRow -TableName $sqlNonClusteredCompressionTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $dbPartTabNonAlignedIndexCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed getting partioned tables with non-aligned indexes scan."

    # Get priority boost settings
    $dbPriorityBoostCounter = 1

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get priority boost settings from $_" -PercentComplete ($dbPriorityBoostCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting priority boost settings from $_" -ForegroundColor Yellow
        $query = "SELECT name, value, value_in_use, [description], is_dynamic, is_advanced
        FROM sys.configurations WITH (NOLOCK)
        where [name]='priority boost'
        ORDER BY name OPTION (RECOMPILE);"

        $dbPriorityBoostSettings = $_ | Invoke-DbaQuery -Query $query
        $sqlInstance = $_
        
        if ($dbPriorityBoostSettings) {
            
            $priortyBoostObject = [pscustomobject]@{
                InstanceName = $sqlInstance
                Name         = $dbPriorityBoostSettings.Name
                Value        = $dbPriorityBoostSettings.value
                ValueInUse   = $dbPriorityBoostSettings.'value_in_use'
                Description  = $dbPriorityBoostSettings.description
                IsDynamic    = $dbPriorityBoostSettings.'is_dynamic'
                IsAdvanced   = $dbPriorityBoostSettings.'is_advanced'
            }

            $sqlPriorityBoostWorksheet = "PriorityBoostSetting"
            $sqlPriorityBoostTable = "PriorityBoostSetting"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $priortyBoostObject | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlPriorityBoostWorksheet -FreezeTopRow -TableName $sqlPriorityBoostTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $dbPriorityBoostCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed getting priority boost settings."

    # Get max full text crawl range
    $dbMaxFullTextCounter = 1

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get Max Full Text Crawl Range from $_" -PercentComplete ($dbMaxFullTextCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting Max Full Text Crawl Range from $_" -ForegroundColor Yellow
        $query = "SELECT name, value, value_in_use, [description], is_dynamic, is_advanced
        FROM sys.configurations WITH (NOLOCK)
        where [name]='max full-text crawl range'
        ORDER BY name OPTION (RECOMPILE);"

        $dbMaxFullTextSettings = $_ | Invoke-DbaQuery -Query $query
        $sqlInstance = $_
        
        if ($dbMaxFullTextSettings) {
            
            $maxFullTextObject = [pscustomobject]@{
                InstanceName = $sqlInstance
                Name         = $dbMaxFullTextSettings.Name
                Value        = $dbMaxFullTextSettings.value
                ValueInUse   = $dbMaxFullTextSettings.'value_in_use'
                Description  = $dbMaxFullTextSettings.description
                IsDynamic    = $dbMaxFullTextSettings.'is_dynamic'
                IsAdvanced   = $dbMaxFullTextSettings.'is_advanced'
            }

            $sqlMaxFullTextWorksheet = "MaxFullTextCrawlSetting"
            $sqlMaxFullTextTable = "MaxFullTextCrawlSetting"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $maxFullTextObject | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlMaxFullTextWorksheet -FreezeTopRow -TableName $sqlMaxFullTextTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $dbMaxFullTextCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed getting Max Full Text Crawl range."

    # Get missing T-Log backups
    $missingTlogBackupCounter = 1
    $missingTlogBackupArray = @()

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get missing T-Log backups from $_" -PercentComplete ($missingTlogBackupCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting missing T-Log backups from $_" -ForegroundColor Yellow
        $query = "SELECT D.[name] AS [database_name], D.[recovery_model_desc]
        FROM sys.databases D LEFT JOIN 
           (
           SELECT BS.[database_name], 
               MAX(BS.[backup_finish_date]) AS [last_log_backup_date]
           FROM msdb.dbo.backupset BS 
           WHERE BS.type = 'L'
           GROUP BY BS.[database_name]
           ) BS1 ON D.[name] = BS1.[database_name]
        WHERE D.[recovery_model_desc] <> 'SIMPLE'
           AND BS1.[last_log_backup_date] IS NULL
        ORDER BY D.[name];"

        $dbMissingTLogBackups = $_ | Invoke-DbaQuery -Query $query
        $sqlInstance = $_

        if ($dbMissingTLogBackups) {
            
            $dbMissingTLogBackups | % {
                
                $missingTLogBackupObject = [pscustomobject]@{
                    InstanceName  = $sqlInstance
                    Database      = $_.'database_name'
                    RecoveryModel = $_.'recovery_model_desc'
                }

                $missingTlogBackupArray = [System.Array]$missingTlogBackupArray + $missingTLogBackupObject
            }

            $sqlMissingTlogWorksheet = "MissingTLogBackups"
            $sqlMissingTlogTable = "MissingTLogBackups"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $missingTlogBackupArray | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $sqlMissingTlogWorksheet -FreezeTopRow -TableName $sqlMissingTlogTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $missingTlogBackupCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed getting missing T-Log backups."

    # Get node interleave settings
    $allNodeInterleaveSettings = @()
    
    $clusterNodeInfo | % {
        Write-Host "Getting node interleave settings from $($_.Name)" -ForegroundColor Yellow
        $interleaveSettings = Get-NodeInterleaveSettings -ComputerName $_.Name
        $interleaveSettings | % { $allNodeInterleaveSettings = [System.Array]$allNodeInterleaveSettings + $_ }
    }

    $interleaveSettingsWorksheet = "Interleave Settings"
    $interleaveSettingsTable = "InterleaveSettings"

    $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

    $excel = $allNodeInterleaveSettings | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $interleaveSettingsWorksheet -FreezeTopRow -TableName $interleaveSettingsTable -PassThru -Append
    $excel.Save() ; $excel.Dispose()

    # Get all Duplicate Indexes
    $duplicateIndexCounter = 1
    $duplicateIndexResultArr = @()

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get duplicate indexes from $_" -PercentComplete ($duplicateIndexCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting duplicate indexes from $_" -ForegroundColor Yellow
        $duplicateIndexes = $_ | Find-DbaDbDuplicateIndex
        $sqlInstance = $_

        if ($duplicateIndexes) {

            $duplicateIndexes | % {
                $duplicateIndexObject = [PSCustomObject]@{
                    InstanceName           = $sqlInstance
                    DatabaseName           = $_.DatabaseName
                    TableName              = $_.TableName
                    IndexName              = $_.IndexName
                    KeyColumns             = $_.KeyColumns
                    IncludeColumns         = $_.IncludeColumns
                    IndexType              = $_.IndexType
                    IndexSixeMB            = $_.IndexSizeMB
                    CompressionDescription = $_.CompressionDescription
                    RowCount               = $_.RowCount
                    IsDisabled             = $_.IsDisabled
                    IsFiltered             = $_.IsFiltered
                }
                $duplicateIndexResultArr = [System.Array]$duplicateIndexResultArr + $duplicateIndexObject
            }

            $dupIndexWorksheet = "Duplicate Indexes"
            $dupIndexTable = "DuplicateIndexes"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $duplicateIndexResultArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $dupIndexWorksheet -FreezeTopRow -TableName $dupIndexTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $duplicateIndexCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed getting duplicate indexes."
    <#
    # Get all disabled Indexes
    $disabledIndexCounter = 1
    $disabledIndexResultArr = @()

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get disabled indexes from $_" -PercentComplete ($disabledIndexCounter / $(($instanceData.sqlInstance).Count) * 100)
        
        $databases = Get-DbaDatabase -SqlInstance $_
        $sqlInstance = $_

        $databases | % {
            $disabledIndexes = $sqlInstance | Find-DbaDbDisabledIndex -Database $_.Name
            $disabledIndexesObject = [PSCustomObject]@{
                InstanceName = $sqlInstance
                Database     = $_.Name
            }
        }

        if ($disabledIndexes) {
            $disabledIndexWorksheet = "DisabledIndexes-$sqlInstance"[0..29] -join ""
            $disabledIndexTable = "DisabledIndexes$fragmentedIndexCounter"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $disabledIndexes | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $disabledIndexWorksheet -FreezeTopRow -TableName $disabledIndexTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $disabledIndexCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed getting disabled indexes."
#>
    # Get all R/W Indexes
    $rwIndexCounter = 1
    $rwIndexResultArr = @()

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Get read/write indexes from $_" -PercentComplete ($rwIndexCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting R/W indexes from $_" -ForegroundColor Yellow
        $query = "SELECT OBJECT_NAME(s.[object_id]) AS [ObjectName], i.name AS [IndexName], i.index_id,
        user_seeks + user_scans + user_lookups AS [Reads], s.user_updates AS [Writes],
        i.type_desc AS [IndexType], i.fill_factor AS [FillFactor], i.has_filter, i.filter_definition,
        s.last_user_scan, s.last_user_lookup, s.last_user_seek
        FROM sys.dm_db_index_usage_stats AS s WITH (NOLOCK)
        INNER JOIN sys.indexes AS i WITH (NOLOCK)
        ON s.[object_id] = i.[object_id]
        WHERE i.index_id = s.index_id
        AND s.database_id = DB_ID()
        ORDER BY user_seeks + user_scans + user_lookups DESC OPTION (RECOMPILE);"

        $databases = Get-DbaDatabase -SqlInstance $_
        $sqlInstance = $_

        $databases | % {
            $rwIndexes = $sqlInstance | Invoke-DbaQuery -Query $query -Database $_.Name
            $rwIndexes | % {
                $rwIndexObject = [PSCustomObject]@{
                    InstanceName   = $sqlInstance
                    Database       = $_.Name
                    ObjectName     = $_.objectname
                    IndexName      = $_.IndexName
                    IndexID        = $_.'index_id'
                    Reads          = $_.Reads
                    Writes         = $_.Writes
                    IndexType      = $_.IndexType
                    FillFactor     = $_.FillFactor
                    LastUserScan   = $_.'last_user_scan'
                    LastUserLookup = $_.'last_user_lookup'
                    LastUserSeek   = $_.'last_user_seek'
                }
                $rwIndexResultArr = [System.Array]$rwIndexResultArr + $rwIndexObject
            }
        }
        
        if ($rwIndexResultArr) {
            $rwIndexWorksheet = "RWIndexes"
            $rwIndexTable = "RWIndexes"

            $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

            $excel = $rwIndexResultArr | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $rwIndexWorksheet -FreezeTopRow -TableName $rwIndexTable -PassThru -Append
            $excel.Save() ; $excel.Dispose()
        }
        $disabledIndexCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed read/write indexes."

    # Get top waits
    $topWaitsCounter = 1
    $topWaitsResultArr = @()

    $instanceData.sqlInstance | % {
        Write-Progress -Id 5 -ParentId 0 -Activity "Getting top waits from $_" -PercentComplete ($topWaitsCounter / $(($instanceData.sqlInstance).Count) * 100)
        Write-Host "Getting top waits from $_" -ForegroundColor Yellow
        $query = ";WITH Waits
        AS (SELECT wait_type, CAST(wait_time_ms / 1000. AS DECIMAL(12, 2)) AS [wait_time_s],
            CAST(100. * wait_time_ms / SUM(wait_time_ms) OVER () AS decimal(12,2)) AS [pct],
            ROW_NUMBER() OVER (ORDER BY wait_time_ms DESC) AS rn
            FROM sys.dm_os_wait_stats WITH (NOLOCK)
            WHERE wait_type NOT IN (N'CLR_SEMAPHORE', N'LAZYWRITER_SLEEP', N'RESOURCE_QUEUE',N'SLEEP_TASK',
                                    N'SLEEP_SYSTEMTASK', N'SQLTRACE_BUFFER_FLUSH', N'WAITFOR', N'LOGMGR_QUEUE',
                                    N'CHECKPOINT_QUEUE', N'REQUEST_FOR_DEADLOCK_SEARCH', N'XE_TIMER_EVENT',
                                    N'BROKER_TO_FLUSH', N'BROKER_TASK_STOP', N'CLR_MANUAL_EVENT', N'CLR_AUTO_EVENT',
                                    N'DISPATCHER_QUEUE_SEMAPHORE' ,N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'XE_DISPATCHER_WAIT',
                                    N'XE_DISPATCHER_JOIN', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'ONDEMAND_TASK_QUEUE',
                                    N'BROKER_EVENTHANDLER', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP', N'DIRTY_PAGE_POLL',
                                    N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',N'SP_SERVER_DIAGNOSTICS_SLEEP')),
        Running_Waits 
        AS (SELECT W1.wait_type, wait_time_s, pct,
            SUM(pct) OVER(ORDER BY pct DESC ROWS UNBOUNDED PRECEDING) AS [running_pct]
            FROM Waits AS W1)
        SELECT wait_type, wait_time_s, pct, running_pct
        FROM Running_Waits
        WHERE running_pct - pct <= 99
        ORDER BY running_pct
        OPTION (RECOMPILE);
        go"

        $sqlInstance = $_

        $topWaits = $sqlInstance | Invoke-DbaQuery -Query $query
        
        if ($topWaits) {
            $topWaits | % {
                $topWaitsObject = [PSCustomObject]@{
                    InstanceName    = $sqlInstance
                    WaitType        = $_.'wait_type'
                    WaitTimeSeconds = $_.'wait_time_s'
                    Percent         = $_.pct
                    RunningPercent  = $_.'running_pct'
                }

                $topWaitsWorksheet = "TopWaits"
                $topWaitsTable = "TopWaits"

                $SQLServerConfigxlsxReportPath = "$PSScriptRoot\tmp\$fileName-DBAQueries-$datetime.xlsx"

                $excel = $topWaitsObject | Export-Excel -Path $SQLServerConfigxlsxReportPath -AutoSize -WorksheetName $topWaitsWorksheet -FreezeTopRow -TableName $topWaitsTable -PassThru -Append
                $excel.Save() ; $excel.Dispose()
            }
        }
        $topWaitsCounter++
    }
    Write-Progress -Id 5 -Completed -Activity "Completed getting top waits."
}

Write-Progress -Id 0 -Completed -Activity "Completed report run."
if (Test-Path "$PSScriptRoot\tmp\instanceData.json") { Remove-Item -Path "$PSScriptRoot\tmp\instanceData.json" -Force -Confirm:$false }
if (Test-Path "$PSScriptRoot\tmp\clusterNodeInfo.json") { Remove-Item -Path "$PSScriptRoot\tmp\clusterNodeInfo.json" -Force -Confirm:$false }
if (Test-Path "$PSScriptRoot\tmp\clusterInfo.json") { Remove-Item -Path "$PSScriptRoot\tmp\clusterInfo.json" -Force -Confirm:$false }
Stop-Transcript