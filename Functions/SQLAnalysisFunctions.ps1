function Get-SQLServerAV {
    [cmdletbinding()]
    param(
        [string]$AVVendor,
        [array]$AVServices
    )

    Begin {
        $processes = Get-Process        
    }
    Process {
        $AVServices.Executable | % {
            $avExeSplit = $_.Split(".")
            $avProcName = $avExeSplit[0]
            if ($avProcName -in $processes.Name) { return $avProcName }
        }
    }
}

function Convert-ClusterValidationReport {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ValidationXmlPath
    )


    [xml]$xml = (Get-Content -Path $ValidationXmlPath)
    $channels = $xml.Report.Channel.Channel

    $validationResultArray = New-Object -TypeName System.Collections.ArrayList

    foreach ($channel in $channels) {
        if ($channel.Type -eq 'Summary') {
            $channelSummaryHash = [PSCustomObject]@{}
            $summaryArray = New-Object -TypeName System.Collections.ArrayList

            $channelId = $channel.id
            $channelName = $channel.ChannelName.'#cdata-section'        
        
            foreach ($summaryChannel in $channels.Where( { $_.SummaryChannel.Value.'#cdata-section' -eq $channelId })) {
                $channelTitle = $summaryChannel.Title.Value.'#cdata-section'
                $channelResult = $summaryChannel.Result.Value.'#cdata-section'
                $channelMessage = $summaryChannel.Message.'#cdata-section'
    
                $summaryHash = [PSCustomObject] @{
                    Title   = $channelTitle
                    Result  = $channelResult
                    Message = $channelMessage
                }
    
                $null = $summaryArray.Add($summaryHash)
            }
    
            $channelSummaryHash | Add-Member -MemberType NoteProperty -Name Category -Value $channelName
            $channelSummaryHash | Add-Member -MemberType NoteProperty -Name Results -Value $summaryArray
    
            $null = $validationResultArray.Add($channelSummaryHash)
        }

    }

    return $validationResultArray
}

Function Get-PageFileInfo {
    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $False, ValueFromPipeline = $True)]  
        [string[]]$ComputerName
    )
    
    Begin {
        $pageFileInfoArray = @()
    }
    Process {
        if ($ComputerName) {
            Foreach ($computer in $ComputerName) {
        
                $PageFileResults = Get-CimInstance -Class Win32_PageFileUsage -ComputerName $computer | Select-Object *
                
                $PageFileResults | % {
                    $systemManagedPageFileBool = $false
                    if ($_.AllocatedBaseSize -eq 0) { $systemManagedPageFileBool = $true }

                    $PageFileStats = [PSCustomObject]@{
                        FilePath              = $_.Description
                        "TotalSize(in MB)"    = $_.AllocatedBaseSize
                        "CurrentUsage(in MB)" = $_.CurrentUsage
                        "PeakUsage(in MB)"    = $_.PeakUsage
                        TempPageFileInUse     = $_.TempPageFile
                    }
                    
                    $pageFileInfoArray = [System.Array]$pageFileInfoArray + $PageFileStats                    
                }
            }
        }
        else {
            $PageFileResults = Get-CimInstance -Class Win32_PageFileUsage | Select-Object *
            
            $PageFileResults | % {
                $systemManagedPageFileBool = $false
                if ($_.AllocatedBaseSize -eq 0) { $systemManagedPageFileBool = $true }

                $PageFileStats = [PSCustomObject]@{
                    FilePath              = $_.Description
                    "TotalSize(in MB)"    = $_.AllocatedBaseSize
                    "CurrentUsage(in MB)" = $_.CurrentUsage
                    "PeakUsage(in MB)"    = $_.PeakUsage
                    TempPageFileInUse     = $_.TempPageFile
                }
                
                $pageFileInfoArray = [System.Array]$pageFileInfoArray + $PageFileStats                    
            }
        }
    }
    End {
        return $pageFileInfoArray
    }
}

function Get-BlitzCacheResults {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $False, ValueFromPipeline = $True)]  
        [string]$sqlInstance,
        [Parameter(Mandatory = $False, ValueFromPipeline = $True)]  
        [string]$SortOrder
    )

    # Get top 50 queries by CPU
    $sqlQuery = "EXEC sp_BlitzCache @SortOrder = '%SortOrder%', @Top = 10, @BringThePain =1,@ExportToExcel = 1;"
    $dbTopCPUQuery = Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sqlQuery.Replace("%SortOrder%", $SortOrder)
    $dbTopCPUQuery
    # Create a custom object so we can add a few columns.
    $dbTopCPUQuery | % {
        $dbTopCPUQueryObject = [pscustomobject]@{
            'InstanceName'            = $sqlInstance
            "DatabaseName"           = $_.'Database Name'
            "Cost"                   = $_.Cost
            "QueryText"              = $_.QueryText
            "QueryType"              = $_.'Query Type'
            "Warnings"               = $_.Warnings
            "ExecutionCount"         = $_.ExecutionCount
            "ExecutionsPerMinute"    = $_.'Executions / Minute'
            "ExecutionWeight"        = $_.'Execution Weight'
            "PercentExecutions-Type" = $_.'% Executions (Type)'
            "SerialDesiredMemory"    = $_.'Serial Desired Memory'
            "Serial Required Memory" = $_.'Serial Required Memory'
            "TotalCPUMS"             = $_.'Total CPU (ms)'
            "AvgCPUMS"               = $_.'Avg CPU (ms)'
            "CPUWeight"              = $_.'CPU Weight'
            "PercentCPU-Type"        = $_.'% CPU (Type)'
            "TotalDurationMS"        = $_.'Total Duration (ms)'
            "AvgDurationMS"          = $_.'Avg Duration (ms)'
            "DurationWeight"         = $_.'Duration Weight'
            "PercentDuration-Type"   = $_.'% Duration (Type)'
            "TotalReads"             = $_.'Total Reads'
            "AverageReads"           = $_.'Average Reads'
            "ReadWeight"             = $_.'Read Weight'
            "PercentReads-Type"      = $_.'% Reads (Type)'
            "TotalWrites"            = $_.'Total Writes'
            "AverageWrites"          = $_.'Average Writes'
            "WriteWeight"            = $_.'Write Weight'
            "PercentWrites-Type"     = $_.'% Writes (Type)'
            "TotalReturnedRows"      = $_.TotalReturnedRows
            "AverageReturnedRows"    = $_.AverageReturnedRows
            "MinReturnedRows"        = $_.MinReturnedRows
            "MaxReturnedRows"        = $_.MaxReturnedRows
            "MinGrantKB"             = $_.MinGrantKB
            "MaxGrantKB"             = $_.MaxGrantKB
            "MinUsedGrantKB"         = $_.MinUsedGrantKB
            "MaxUsedGrantKB"         = $_.MaxUsedGrantKB
            "PercentMemoryGrantUsed" = $_.PercentMemoryGrantUsed
            "AvgMaxMemoryGrant"      = $_.AvgMaxMemoryGrant
            "MinSpills"              = $_.MinSpills
            "MaxSpills"              = $_.MaxSpills
            "TotalSpills"            = $_.TotalSpills
            "AvgSpills"              = $_.AvgSpills
            "NumberOfPlans"          = $_.NumberOfPlans
            "NumberOfDistinctPlans"  = $_.NumberOfDistinctPlans
            "CreatedAt"              = $_.'Created At'
            "LastExecution"          = $_.'Last Execution'
            "StatementStartOffset"   = $_.StatementStartOffset
            "StatementEndOffset"     = $_.StatementEndOffset
            "PlanGenerationNum"      = $_.PlanGenerationNum
            "SETOptions"             = $_.'SET Options'
        }
        $dbTopCPUQueryArray = [System.Array]$dbTopCPUeQueryArray + $dbTopCPUQueryObject
    }

    return $dbTopCPUQueryArray
}

function get-WmiMemoryFormFactor {
    param ([uint16] $char)

    If ($char -ge 0 -and $char -le 22) {

        switch ($char) {
            0 { "00-Unknown" }
            1 { "01-Other" }
            2 { "02-SiP" }
            3 { "03-DIP" }
            4 { "04-ZIP" }
            5 { "05-SOJ" }
            6 { "06-Proprietary" }
            7 { "07-SIMM" }
            8 { "08-DIMM" }
            9 { "09-TSOPO" }
            10 { "10-PGA" }
            11 { "11-RIM" }
            12 { "12-SODIMM" }
            13 { "13-SRIMM" }
            14 { "14-SMD" }
            15 { "15-SSMP" }
            16 { "16-QFP" }
            17 { "17-TQFP" }
            18 { "18-SOIC" }
            19 { "19-LCC" }
            20 { "20-PLCC" }
            21 { "21-FPGA" }
            22 { "22-LGA" }
        }
    }

    else {
        "{0} - undefined value" -f $char
    }

    Return
}

# Helper function to return memory Interleave  Position

function get-WmiInterleavePosition {
    param ([uint32] $char)

    If ($char -ge 0 -and $char -le 2) {

        switch ($char) {
            0 { "00-Non-Interleaved" }
            1 { "01-First Position" }
            2 { "02-Second Position" }
        }
    }

    else {
        "{0} - undefined value" -f $char
    }

    Return
}


# Helper function to return Memory Tupe
function get-WmiMemoryType {
    param ([uint16] $char)

    If ($char -ge 0 -and $char -le 20) {

        switch ($char) {
            0 { "00-Unknown" }
            1 { "01-Other" }
            2 { "02-DRAM" }
            3 { "03-Synchronous DRAM" }
            4 { "04-Cache DRAM" }
            5 { "05-EDO" }
            6 { "06-EDRAM" }
            7 { "07-VRAM" }
            8 { "08-SRAM" }
            9 { "09-ROM" }
            10 { "10-ROM" }
            11 { "11-FLASH" }
            12 { "12-EEPROM" }
            13 { "13-FEPROM" }
            14 { "14-EPROM" }
            15 { "15-CDRAM" }
            16 { "16-3DRAM" }
            17 { "17-SDRAM" }
            18 { "18-SGRAM" }
            19 { "19-RDRAM" }
            20 { "20-DDR" }
        }

    }

    else {
        "{0} - undefined value" -f $char
    }

    Return
}

function Get-NodeInterleaveSettings {
    param(
        [string[]]$ComputerName
    )

    $interleaveArray = @()

    $ComputerName | % {
        $computer = $_
        # Get the object
        $memory = Get-WMIObject -ComputerName $computer Win32_PhysicalMemory

        Write-Host "System has $($memory.count) memory sticks." -ForegroundColor Yellow

        $memory | % {

            # Do some conversions
            $cap = $_.capacity / 1mb
            $ff = get-WmiMemoryFormFactor($_.FormFactor)
            $ilp = get-WmiInterleavePosition($_.InterleavePosition)
            $mt = get-WMIMemoryType($_.MemoryType)

            # get the details of each stick
            $interleaveObject = [pscustomobject]@{
                ComputerName         = $computer
                BankLabel            = $_.banklabel
                CapacityMB           = $cap
                Caption              = $_.Caption
                CreationClassName    = $_.creationclassname
                DataWidth            = $_.DataWidth
                Description          = $_.Description
                DeviceLocator        = $_.DeviceLocator
                FormFactor           = $ff
                HotSwappable         = $_.HotSwappable
                InstallDate          = $_.InstallDate
                InterleaveDataDepth  = $_.InterleaveDataDepth
                InterleavePosition   = $ilp
                Manufacturer         = $_.Manufacturer
                MemoryType           = $mt
                Model                = $_.Model
                Name                 = $_.Name
                OtherIdentifyingInfo = $_.OtherIdentifyingInfo
                PartNumber           = $_.PartNumber
                PositionInRow        = $_.PositionInRow
                PoweredOn            = $_.PoweredOn
                Removable            = $_.Removable
                Replaceable          = $_.Replaceable
                SerialNumber         = $_.SerialNumber
                SKU                  = $_.SKU 
                Speed                = $_.Speed 
                Status               = $_.Status
                Tag                  = $_.Tag
                TotalWidth           = $_.TotalWidth 
                TypeDetail           = $_.TypeDetail
                Version              = $_.Version
            }

            $interleaveArray = [System.Array]$interleaveArray + $interleaveObject
        }
    }

    return $interleaveArray
}