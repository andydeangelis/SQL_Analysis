if ($PSVersionTable.PSVersion.Major -lt 5) {


    <#
Copied from the Microsoft Module: Microsoft.PowerShell.Archive
Which ships with PowerShell Version 5 but will run under v3.
    #>



    function Expand-Archive {
        <#
            .SYNOPSIS
                Extracts files from a specified archive (zipped) file.

            .DESCRIPTION
                The Expand-Archive cmdlet extracts files from a specified zipped archive file to a specified destination folder. An archive file allows multiple files to be packaged, and optionally compressed, into a single zipped file for easier distribution and storage.

            .PARAMETER Path
                Specifies the path to the archive file.

            .PARAMETER LiteralPath
                Specifies the path to an archive file. Unlike the Path parameter, the value of LiteralPath is used exactly as it is typed. Wildcard characters are not supported. If the path includes escape characters, enclose each escape character in single quotation marks, to instruct Windows PowerShell not to interpret any characters as escape sequences.

            .PARAMETER DestinationPath
                Specifies the path to the folder in which you want the command to save extracted files. Enter the path to a folder, but do not specify a file name or file name extension. This parameter is required.

            .PARAMETER Force
                Forces the command to run without asking for user confirmation.

            .PARAMETER Confirm
                Prompts you for confirmation before running the cmdlet.

            .PARAMETER WhatIf
                Shows what would happen if the cmdlet runs. The cmdlet is not run.

            .EXAMPLE
                Example 1: Extract the contents of an archive

                PS C:\>Expand-Archive -LiteralPath C:\Archives\Draft.Zip -DestinationPath C:\Reference

                This command extracts the contents of an existing archive file, Draft.zip, into the folder specified by the DestinationPath parameter, C:\Reference.

            .EXAMPLE
                Example 2: Extract the contents of an archive in the current folder

                PS C:\>Expand-Archive -Path Draft.Zip -DestinationPath C:\Reference

                This command extracts the contents of an existing archive file in the current folder, Draft.zip, into the folder specified by the DestinationPath parameter, C:\Reference.
        #>
        [CmdletBinding(
            DefaultParameterSetName = "Path",
            SupportsShouldProcess,
            HelpUri = "http://go.microsoft.com/fwlink/?LinkID=393253")]
        param
        (
            [parameter (
                Mandatory,
                Position = 0,
                ParameterSetName = "Path",
                ValueFromPipeline,
                ValueFromPipelineByPropertyName)]
            [ValidateNotNullOrEmpty()]
            [string]
            $Path,

            [parameter (
                Mandatory,
                ParameterSetName = "LiteralPath",
                ValueFromPipelineByPropertyName)]
            [ValidateNotNullOrEmpty()]
            [Alias("PSPath")]
            [string]
            $LiteralPath,

            [parameter (
                Position = 1,
                ValueFromPipeline = $false,
                ValueFromPipelineByPropertyName = $false)]
            [ValidateNotNullOrEmpty()]
            [string]
            $DestinationPath,

            [parameter (
                ValueFromPipeline = $false,
                ValueFromPipelineByPropertyName = $false)]
            [switch]
            $Force
        )

        BEGIN {
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Ignore
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Ignore

            $zipFileExtension = ".zip"

            $LocalizedData = ConvertFrom-StringData @'
    PathNotFoundError=The path '{0}' either does not exist or is not a valid file system path.
    ExpandArchiveInValidDestinationPath=The path '{0}' is not a valid file system directory path.
    InvalidZipFileExtensionError={0} is not a supported archive file format. {1} is the only supported archive file format.
    ArchiveFileIsReadOnly=The attributes of the archive file {0} is set to 'ReadOnly' hence it cannot be updated. If you intend to update the existing archive file, remove the 'ReadOnly' attribute on the archive file else use -Force parameter to override and create a new archive file.
    ZipFileExistError=The archive file {0} already exists. Use the -Update parameter to update the existing archive file or use the -Force parameter to overwrite the existing archive file.
    DuplicatePathFoundError=The input to {0} parameter contains a duplicate path '{1}'. Provide a unique set of paths as input to {2} parameter.
    ArchiveFileIsEmpty=The archive file {0} is empty.
    CompressProgressBarText=The archive file '{0}' creation is in progress...
    ExpandProgressBarText=The archive file '{0}' expansion is in progress...
    AppendArchiveFileExtensionMessage=The archive file path '{0}' supplied to the DestinationPath patameter does not include .zip extension. Hence .zip is appended to the supplied DestinationPath path and the archive file would be created at '{1}'.
    AddItemtoArchiveFile=Adding '{0}'.
    CreateFileAtExpandedPath=Created '{0}'.
    InvalidArchiveFilePathError=The archive file path '{0}' specified as input to the {1} parameter is resolving to multiple file system paths. Provide a unique path to the {2} parameter where the archive file has to be created.
    InvalidExpandedDirPathError=The directory path '{0}' specified as input to the DestinationPath parameter is resolving to multiple file system paths. Provide a unique path to the Destination parameter where the archive file contents have to be expanded.
    FileExistsError=Failed to create file '{0}' while expanding the archive file '{1}' contents as the file '{2}' already exists. Use the -Force parameter if you want to overwrite the existing directory '{3}' contents when expanding the archive file.
    DeleteArchiveFile=The partially created archive file '{0}' is deleted as it is not usable.
    InvalidDestinationPath=The destination path '{0}' does not contain a valid archive file name.
    PreparingToCompressVerboseMessage=Preparing to compress...
    PreparingToExpandVerboseMessage=Preparing to expand...
'@

            #region Utility Functions
            function GetResolvedPathHelper {
                param
                (
                    [string[]]
                    $path,

                    [boolean]
                    $isLiteralPath,

                    [System.Management.Automation.PSCmdlet]
                    $callerPSCmdlet
                )

                $resolvedPaths = @()

                # null and empty check are are already done on Path parameter at the cmdlet layer.
                foreach ($currentPath in $path) {
                    try {
                        if ($isLiteralPath) {
                            $currentResolvedPaths = Resolve-Path -LiteralPath $currentPath -ErrorAction Stop
                        } else {
                            $currentResolvedPaths = Resolve-Path -Path $currentPath -ErrorAction Stop
                        }
                    } catch {
                        $errorMessage = ($LocalizedData.PathNotFoundError -f $currentPath)
                        $exception = New-Object System.InvalidOperationException $errorMessage, $_.Exception
                        $errorRecord = CreateErrorRecordHelper "ArchiveCmdletPathNotFound" $null ([System.Management.Automation.ErrorCategory]::InvalidArgument) $exception $currentPath
                        $callerPSCmdlet.ThrowTerminatingError($errorRecord)
                    }

                    foreach ($currentResolvedPath in $currentResolvedPaths) {
                        $resolvedPaths += $currentResolvedPath.ProviderPath
                    }
                }

                $resolvedPaths
            }

            function Add-CompressionAssemblies {

                if ($PSEdition -eq "Desktop") {
                    Add-Type -AssemblyName System.IO.Compression
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                }
            }

            function IsValidFileSystemPath {
                param
                (
                    [string[]]
                    $path
                )

                $result = $true;

                # null and empty check are are already done on Path parameter at the cmdlet layer.
                foreach ($currentPath in $path) {
                    if (!([System.IO.File]::Exists($currentPath) -or [System.IO.Directory]::Exists($currentPath))) {
                        $errorMessage = ($LocalizedData.PathNotFoundError -f $currentPath)
                        ThrowTerminatingErrorHelper "PathNotFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $currentPath
                    }
                }

                return $result;
            }


            function ValidateDuplicateFileSystemPath {
                param
                (
                    [string]
                    $inputParameter,

                    [string[]]
                    $path
                )

                $uniqueInputPaths = @()

                # null and empty check are are already done on Path parameter at the cmdlet layer.
                foreach ($currentPath in $path) {
                    $currentInputPath = $currentPath.ToUpper()
                    if ($uniqueInputPaths.Contains($currentInputPath)) {
                        $errorMessage = ($LocalizedData.DuplicatePathFoundError -f $inputParameter, $currentPath, $inputParameter)
                        ThrowTerminatingErrorHelper "DuplicatePathFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $currentPath
                    } else {
                        $uniqueInputPaths += $currentInputPath
                    }
                }
            }

            function CompressionLevelMapper {
                param
                (
                    [string]
                    $compressionLevel
                )

                $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::Optimal

                # CompressionLevel format is already validated at the cmdlet layer.
                switch ($compressionLevel.ToString()) {
                    "Fastest" {
                        $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::Fastest
                    }
                    "NoCompression" {
                        $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::NoCompression
                    }
                }

                return $compressionLevelFormat
            }

            function CompressArchiveHelper {
                param
                (
                    [string[]]
                    $sourcePath,

                    [string]
                    $destinationPath,

                    [string]
                    $compressionLevel,

                    [bool]
                    $isUpdateMode
                )

                $numberOfItemsArchived = 0
                $sourceFilePaths = @()
                $sourceDirPaths = @()

                foreach ($currentPath in $sourcePath) {
                    $result = Test-Path -LiteralPath $currentPath -PathType Leaf
                    if ($result -eq $true) {
                        $sourceFilePaths += $currentPath
                    } else {
                        $sourceDirPaths += $currentPath
                    }
                }

                # The Soure Path contains one or more directory (this directory can have files under it) and no files to be compressed.
                if ($sourceFilePaths.Count -eq 0 -and $sourceDirPaths.Count -gt 0) {
                    $currentSegmentWeight = 100 / [double]$sourceDirPaths.Count
                    $previousSegmentWeight = 0
                    foreach ($currentSourceDirPath in $sourceDirPaths) {
                        $count = CompressSingleDirHelper $currentSourceDirPath $destinationPath $compressionLevel $true $isUpdateMode $previousSegmentWeight $currentSegmentWeight
                        $numberOfItemsArchived += $count
                        $previousSegmentWeight += $currentSegmentWeight
                    }
                }

                # The Soure Path contains only files to be compressed.
                elseIf ($sourceFilePaths.Count -gt 0 -and $sourceDirPaths.Count -eq 0) {
                    # $previousSegmentWeight is equal to 0 as there are no prior segments.
                    # $currentSegmentWeight is set to 100 as all files have equal weightage.
                    $previousSegmentWeight = 0
                    $currentSegmentWeight = 100

                    $numberOfItemsArchived = CompressFilesHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $previousSegmentWeight $currentSegmentWeight
                }
                # The Soure Path contains one or more files and one or more directories (this directory can have files under it) to be compressed.
                elseif ($sourceFilePaths.Count -gt 0 -and $sourceDirPaths.Count -gt 0) {
                    # each directory is considered as an individual segments & all the individual files are clubed in to a separate sgemnet.
                    $currentSegmentWeight = 100 / [double]($sourceDirPaths.Count + 1)
                    $previousSegmentWeight = 0

                    foreach ($currentSourceDirPath in $sourceDirPaths) {
                        $count = CompressSingleDirHelper $currentSourceDirPath $destinationPath $compressionLevel $true $isUpdateMode $previousSegmentWeight $currentSegmentWeight
                        $numberOfItemsArchived += $count
                        $previousSegmentWeight += $currentSegmentWeight
                    }

                    $count = CompressFilesHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $previousSegmentWeight $currentSegmentWeight
                    $numberOfItemsArchived += $count
                }

                return $numberOfItemsArchived
            }

            function CompressFilesHelper {
                param
                (
                    [string[]]
                    $sourceFilePaths,

                    [string]
                    $destinationPath,

                    [string]
                    $compressionLevel,

                    [bool]
                    $isUpdateMode,

                    [double]
                    $previousSegmentWeight,

                    [double]
                    $currentSegmentWeight
                )

                $numberOfItemsArchived = ZipArchiveHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $null $previousSegmentWeight $currentSegmentWeight

                return $numberOfItemsArchived
            }

            function CompressSingleDirHelper {
                param
                (
                    [string]
                    $sourceDirPath,

                    [string]
                    $destinationPath,

                    [string]
                    $compressionLevel,

                    [bool]
                    $useParentDirAsRoot,

                    [bool]
                    $isUpdateMode,

                    [double]
                    $previousSegmentWeight,

                    [double]
                    $currentSegmentWeight
                )

                [System.Collections.Generic.List[System.String]]$subDirFiles = @()

                if ($useParentDirAsRoot) {
                    $sourceDirInfo = New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $sourceDirPath
                    $sourceDirFullName = $sourceDirInfo.Parent.FullName

                    # If the directory is present at the drive level the DirectoryInfo.Parent include '\' example: C:\
                    # On the other hand if the directory exists at a deper level then DirectoryInfo.Parent
                    # has just the path (without an ending '\'). example C:\source
                    if ($sourceDirFullName.Length -eq 3) {
                        $modifiedSourceDirFullName = $sourceDirFullName
                    } else {
                        $modifiedSourceDirFullName = $sourceDirFullName + "\"
                    }
                } else {
                    $sourceDirFullName = $sourceDirPath
                    $modifiedSourceDirFullName = $sourceDirFullName + "\"
                }

                $dirContents = Get-ChildItem -LiteralPath $sourceDirPath -Recurse
                foreach ($currentContent in $dirContents) {
                    $isContainer = $currentContent -is [System.IO.DirectoryInfo]
                    if (!$isContainer) {
                        $subDirFiles.Add($currentContent.FullName)
                    } else {
                        # The currentContent points to a directory.
                        # We need to check if the directory is an empty directory, if so such a
                        # directory has to be explictly added to the archive file.
                        # if there are no files in the directory the GetFiles() API returns an empty array.
                        $files = $currentContent.GetFiles()
                        if ($files.Count -eq 0) {
                            $subDirFiles.Add($currentContent.FullName + "\")
                        }
                    }
                }

                $numberOfItemsArchived = ZipArchiveHelper $subDirFiles.ToArray() $destinationPath $compressionLevel $isUpdateMode $modifiedSourceDirFullName $previousSegmentWeight $currentSegmentWeight

                return $numberOfItemsArchived
            }

            function ZipArchiveHelper {
                param
                (
                    [System.Collections.Generic.List[System.String]]
                    $sourcePaths,

                    [string]
                    $destinationPath,

                    [string]
                    $compressionLevel,

                    [bool]
                    $isUpdateMode,

                    [string]
                    $modifiedSourceDirFullName,

                    [double]
                    $previousSegmentWeight,

                    [double]
                    $currentSegmentWeight
                )

                $numberOfItemsArchived = 0
                $fileMode = [System.IO.FileMode]::Create
                $result = Test-Path -LiteralPath $DestinationPath -PathType Leaf
                if ($result -eq $true) {
                    $fileMode = [System.IO.FileMode]::Open
                }

                Add-CompressionAssemblies

                try {
                    # At this point we are sure that the archive file has write access.
                    $archiveFileStreamArgs = @($destinationPath, $fileMode)
                    $archiveFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $archiveFileStreamArgs

                    $zipArchiveArgs = @($archiveFileStream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
                    $zipArchive = New-Object -TypeName System.IO.Compression.ZipArchive -ArgumentList $zipArchiveArgs

                    $currentEntryCount = 0
                    $progressBarStatus = ($LocalizedData.CompressProgressBarText -f $destinationPath)
                    $bufferSize = 4kb
                    $buffer = New-Object Byte[] $bufferSize

                    foreach ($currentFilePath in $sourcePaths) {
                        if ($modifiedSourceDirFullName -ne $null -and $modifiedSourceDirFullName.Length -gt 0) {
                            $index = $currentFilePath.IndexOf($modifiedSourceDirFullName, [System.StringComparison]::OrdinalIgnoreCase)
                            $currentFilePathSubString = $currentFilePath.Substring($index, $modifiedSourceDirFullName.Length)
                            $relativeFilePath = $currentFilePath.Replace($currentFilePathSubString, "").Trim()
                        } else {
                            $relativeFilePath = [System.IO.Path]::GetFileName($currentFilePath)
                        }

                        # Update mode is selected.
                        # Check to see if archive file already contains one or more zip files in it.
                        if ($isUpdateMode -eq $true -and $zipArchive.Entries.Count -gt 0) {
                            $entryToBeUpdated = $null

                            # Check if the file already exists in the archive file.
                            # If so replace it with new file from the input source.
                            # If the file does not exist in the archive file then default to
                            # create mode and create the entry in the archive file.

                            foreach ($currentArchiveEntry in $zipArchive.Entries) {
                                if ($currentArchiveEntry.FullName -eq $relativeFilePath) {
                                    $entryToBeUpdated = $currentArchiveEntry
                                    break
                                }
                            }

                            if ($entryToBeUpdated -ne $null) {
                                $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
                                $entryToBeUpdated.Delete()
                            }
                        }

                        $compression = CompressionLevelMapper $compressionLevel

                        # If a directory needs to be added to an archive file,
                        # by convention the .Net API's expect the path of the diretcory
                        # to end with '\' to detect the path as an directory.
                        if (!$relativeFilePath.EndsWith("\", [StringComparison]::OrdinalIgnoreCase)) {
                            try {
                                try {
                                    $currentFileStream = [System.IO.File]::Open($currentFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                                } catch {
                                    # Failed to access the file. Write a non terminating error to the pipeline
                                    # and move on with the remaining files.
                                    $exception = $_.Exception
                                    if ($null -ne $_.Exception -and
                                        $null -ne $_.Exception.InnerException) {
                                        $exception = $_.Exception.InnerException
                                    }
                                    $errorRecord = CreateErrorRecordHelper "CompressArchiveUnauthorizedAccessError" $null ([System.Management.Automation.ErrorCategory]::PermissionDenied) $exception $currentFilePath
                                    Write-Error -ErrorRecord $errorRecord
                                }

                                if ($null -ne $currentFileStream) {
                                    $srcStream = New-Object System.IO.BinaryReader $currentFileStream

                                    $currentArchiveEntry = $zipArchive.CreateEntry($relativeFilePath, $compression)

                                    # Updating  the File Creation time so that the same timestamp would be retained after expanding the compressed file.
                                    # At this point we are sure that Get-ChildItem would succeed.
                                    $currentArchiveEntry.LastWriteTime = (Get-Item -LiteralPath $currentFilePath).LastWriteTime

                                    $destStream = New-Object System.IO.BinaryWriter $currentArchiveEntry.Open()

                                    while ($numberOfBytesRead = $srcStream.Read($buffer, 0, $bufferSize)) {
                                        $destStream.Write($buffer, 0, $numberOfBytesRead)
                                        $destStream.Flush()
                                    }

                                    $numberOfItemsArchived += 1
                                    $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
                                }
                            } finally {
                                If ($null -ne $currentFileStream) {
                                    $currentFileStream.Dispose()
                                }
                                If ($null -ne $srcStream) {
                                    $srcStream.Dispose()
                                }
                                If ($null -ne $destStream) {
                                    $destStream.Dispose()
                                }
                            }
                        } else {
                            $currentArchiveEntry = $zipArchive.CreateEntry("$relativeFilePath", $compression)
                            $numberOfItemsArchived += 1
                            $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
                        }

                        if ($null -ne $addItemtoArchiveFileMessage) {
                            Write-Verbose $addItemtoArchiveFileMessage
                        }

                        $currentEntryCount += 1
                        ProgressBarHelper "Compress-Archive" $progressBarStatus $previousSegmentWeight $currentSegmentWeight $sourcePaths.Count  $currentEntryCount
                    }
                } finally {
                    If ($null -ne $zipArchive) {
                        $zipArchive.Dispose()
                    }

                    If ($null -ne $archiveFileStream) {
                        $archiveFileStream.Dispose()
                    }

                    # Complete writing progress.
                    Write-Progress -Activity "Compress-Archive" -Completed
                }

                return $numberOfItemsArchived
            }

            <############################################################################################
# ValidateArchivePathHelper: This is a helper function used to validate the archive file
# path & its file format. The only supported archive file format is .zip
############################################################################################>
            function ValidateArchivePathHelper {
                param
                (
                    [string]
                    $archiveFile
                )

                if ([System.IO.File]::Exists($archiveFile)) {
                    $extension = [system.IO.Path]::GetExtension($archiveFile)

                    # Invalid file extension is specifed for the zip file.
                    if ($extension -ne $zipFileExtension) {
                        $errorMessage = ($LocalizedData.InvalidZipFileExtensionError -f $extension, $zipFileExtension)
                        ThrowTerminatingErrorHelper "NotSupportedArchiveFileExtension" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $extension
                    }
                } else {
                    $errorMessage = ($LocalizedData.PathNotFoundError -f $archiveFile)
                    ThrowTerminatingErrorHelper "PathNotFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $archiveFile
                }
            }

            <############################################################################################
# ExpandArchiveHelper: This is a helper function used to expand the archive file contents
# to the specified directory.
############################################################################################>
            function ExpandArchiveHelper {
                param
                (
                    [string]
                    $archiveFile,

                    [string]
                    $expandedDir,

                    [ref]
                    $expandedItems,

                    [boolean]
                    $force,

                    [boolean]
                    $isVerbose,

                    [boolean]
                    $isConfirm
                )

                Add-CompressionAssemblies

                try {
                    # The existance of archive file has already been validated by ValidateArchivePathHelper
                    # before calling this helper function.
                    $archiveFileStreamArgs = @($archiveFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                    $archiveFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $archiveFileStreamArgs

                    $zipArchiveArgs = @($archiveFileStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
                    $zipArchive = New-Object -TypeName System.IO.Compression.ZipArchive -ArgumentList $zipArchiveArgs

                    if ($zipArchive.Entries.Count -eq 0) {
                        $archiveFileIsEmpty = ($LocalizedData.ArchiveFileIsEmpty -f $archiveFile)
                        Write-Verbose $archiveFileIsEmpty
                        return
                    }

                    $currentEntryCount = 0
                    $progressBarStatus = ($LocalizedData.ExpandProgressBarText -f $archiveFile)

                    # The archive entries can either be empty directories or files.
                    foreach ($currentArchiveEntry in $zipArchive.Entries) {
                        $currentArchiveEntryPath = Join-Path -Path $expandedDir -ChildPath $currentArchiveEntry.FullName
                        $extension = [system.IO.Path]::GetExtension($currentArchiveEntryPath)

                        # The current archive entry is an empty directory
                        # The FullName of the Archive Entry representing a directory would end with a trailing '\'.
                        if ($extension -eq [string]::Empty -and
                            $currentArchiveEntryPath.EndsWith("\", [StringComparison]::OrdinalIgnoreCase)) {
                            $pathExists = Test-Path -LiteralPath $currentArchiveEntryPath

                            # The current archive entry expects an empty directory.
                            # Check if the existing directory is empty. If its not empty
                            # then it means that user has added this directory by other means.
                            if ($pathExists -eq $false) {
                                New-Item $currentArchiveEntryPath -ItemType Directory -Confirm:$isConfirm | Out-Null

                                if (Test-Path -LiteralPath $currentArchiveEntryPath -PathType Container) {
                                    $addEmptyDirectorytoExpandedPathMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentArchiveEntryPath)
                                    Write-Verbose $addEmptyDirectorytoExpandedPathMessage

                                    $expandedItems.Value += $currentArchiveEntryPath
                                }
                            }
                        } else {
                            try {
                                $currentArchiveEntryFileInfo = New-Object -TypeName System.IO.FileInfo -ArgumentList $currentArchiveEntryPath
                                $parentDirExists = Test-Path -LiteralPath $currentArchiveEntryFileInfo.DirectoryName -PathType Container

                                # If the Parent directory of the current entry in the archive file does not exist, then create it.
                                if ($parentDirExists -eq $false) {
                                    New-Item $currentArchiveEntryFileInfo.DirectoryName -ItemType Directory -Confirm:$isConfirm | Out-Null

                                    if (!(Test-Path -LiteralPath $currentArchiveEntryFileInfo.DirectoryName -PathType Container)) {
                                        # The directory referred by $currentArchiveEntryFileInfo.DirectoryName was not successfully created.
                                        # This could be because the user has specified -Confirm paramter when Expand-Archive was invoked
                                        # and authorization was not provided when confirmation was prompted. In such a scenario,
                                        # we skip the current file in the archive and continue with the remaining archive file contents.
                                        Continue
                                    }

                                    $expandedItems.Value += $currentArchiveEntryFileInfo.DirectoryName
                                }

                                $hasNonTerminatingError = $false

                                # Check if the file in to which the current archive entry contents
                                # would be expanded already exists.
                                if ($currentArchiveEntryFileInfo.Exists) {
                                    if ($force) {
                                        Remove-Item -LiteralPath $currentArchiveEntryFileInfo.FullName -Force -ErrorVariable ev -Verbose:$isVerbose -Confirm:$isConfirm
                                        if ($ev -ne $null) {
                                            $hasNonTerminatingError = $true
                                        }

                                        if (Test-Path -LiteralPath $currentArchiveEntryFileInfo.FullName -PathType Leaf) {
                                            # The file referred by $currentArchiveEntryFileInfo.FullName was not successfully removed.
                                            # This could be because the user has specified -Confirm paramter when Expand-Archive was invoked
                                            # and authorization was not provided when confirmation was prompted. In such a scenario,
                                            # we skip the current file in the archive and continue with the remaining archive file contents.
                                            Continue
                                        }
                                    } else {
                                        # Write non-terminating error to the pipeline.
                                        $errorMessage = ($LocalizedData.FileExistsError -f $currentArchiveEntryFileInfo.FullName, $archiveFile, $currentArchiveEntryFileInfo.FullName, $currentArchiveEntryFileInfo.FullName)
                                        $errorRecord = CreateErrorRecordHelper "ExpandArchiveFileExists" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidOperation) $null $currentArchiveEntryFileInfo.FullName
                                        Write-Error -ErrorRecord $errorRecord
                                        $hasNonTerminatingError = $true
                                    }
                                }

                                if (!$hasNonTerminatingError) {
                                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($currentArchiveEntry, $currentArchiveEntryPath, $false)

                                    # Add the expanded file path to the $expandedItems array,
                                    # to keep track of all the expanded files created while expanding the archive file.
                                    # If user enters CTRL + C then at that point of time, all these expanded files
                                    # would be deleted as part of the clean up process.
                                    $expandedItems.Value += $currentArchiveEntryPath

                                    $addFiletoExpandedPathMessage = ($LocalizedData.CreateFileAtExpandedPath -f $currentArchiveEntryPath)
                                    Write-Verbose $addFiletoExpandedPathMessage
                                }
                            } finally {
                                If ($null -ne $destStream) {
                                    $destStream.Dispose()
                                }

                                If ($null -ne $srcStream) {
                                    $srcStream.Dispose()
                                }
                            }
                        }

                        $currentEntryCount += 1
                        # $currentSegmentWeight is Set to 100 giving equal weightage to each file that is getting expanded.
                        # $previousSegmentWeight is set to 0 as there are no prior segments.
                        $previousSegmentWeight = 0
                        $currentSegmentWeight = 100
                        ProgressBarHelper "Expand-Archive" $progressBarStatus $previousSegmentWeight $currentSegmentWeight $zipArchive.Entries.Count  $currentEntryCount
                    }
                } finally {
                    If ($null -ne $zipArchive) {
                        $zipArchive.Dispose()
                    }

                    If ($null -ne $archiveFileStream) {
                        $archiveFileStream.Dispose()
                    }

                    # Complete writing progress.
                    Write-Progress -Activity "Expand-Archive" -Completed
                }
            }

            <############################################################################################
# ProgressBarHelper: This is a helper function used to display progress message.
# This function is used by both Compress-Archive & Expand-Archive to display archive file
# creation/expansion progress.
############################################################################################>
            function ProgressBarHelper {
                param
                (
                    [string]
                    $cmdletName,

                    [string]
                    $status,

                    [double]
                    $previousSegmentWeight,

                    [double]
                    $currentSegmentWeight,

                    [int]
                    $totalNumberofEntries,

                    [int]
                    $currentEntryCount
                )

                if ($currentEntryCount -gt 0 -and
                    $totalNumberofEntries -gt 0 -and
                    $previousSegmentWeight -ge 0 -and
                    $currentSegmentWeight -gt 0) {
                    $entryDefaultWeight = $currentSegmentWeight / [double]$totalNumberofEntries

                    $percentComplete = $previousSegmentWeight + ($entryDefaultWeight * $currentEntryCount)
                    Write-Progress -Activity $cmdletName -Status $status -PercentComplete $percentComplete
                }
            }

            <############################################################################################
# CSVHelper: This is a helper function used to append comma after each path specifid by
# the SourcePath array. This helper function is used to display all the user supplied paths
# in the WhatIf message.
############################################################################################>
            function CSVHelper {
                param
                (
                    [string[]]
                    $sourcePath
                )

                # SourcePath has already been validated by the calling funcation.
                if ($sourcePath.Count -gt 1) {
                    $sourcePathInCsvFormat = "`n"
                    for ($currentIndex = 0; $currentIndex -lt $sourcePath.Count; $currentIndex++) {
                        if ($currentIndex -eq $sourcePath.Count - 1) {
                            $sourcePathInCsvFormat += $sourcePath[$currentIndex]
                        } else {
                            $sourcePathInCsvFormat += $sourcePath[$currentIndex] + "`n"
                        }
                    }
                } else {
                    $sourcePathInCsvFormat = $sourcePath
                }

                return $sourcePathInCsvFormat
            }

            <############################################################################################
# ThrowTerminatingErrorHelper: This is a helper function used to throw terminating error.
############################################################################################>
            function ThrowTerminatingErrorHelper {
                param
                (
                    [string]
                    $errorId,

                    [string]
                    $errorMessage,

                    [System.Management.Automation.ErrorCategory]
                    $errorCategory,

                    [object]
                    $targetObject,

                    [Exception]
                    $innerException
                )

                if ($innerException -eq $null) {
                    $exception = New-object System.IO.IOException $errorMessage
                } else {
                    $exception = New-Object System.IO.IOException $errorMessage, $innerException
                }

                $exception = New-Object System.IO.IOException $errorMessage
                $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $targetObject
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            <############################################################################################
# CreateErrorRecordHelper: This is a helper function used to create an ErrorRecord
############################################################################################>
            function CreateErrorRecordHelper {
                param
                (
                    [string]
                    $errorId,

                    [string]
                    $errorMessage,

                    [System.Management.Automation.ErrorCategory]
                    $errorCategory,

                    [Exception]
                    $exception,

                    [object]
                    $targetObject
                )

                if ($null -eq $exception) {
                    $exception = New-Object System.IO.IOException $errorMessage
                }

                $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $targetObject
                return $errorRecord
            }
            #endregion Utility Functions

            $isVerbose = $psboundparameters.ContainsKey("Verbose")
            $isConfirm = $psboundparameters.ContainsKey("Confirm")

            $isDestinationPathProvided = $true
            if ($DestinationPath -eq [string]::Empty) {
                $resolvedDestinationPath = $pwd
                $isDestinationPathProvided = $false
            } else {
                $destinationPathExists = Test-Path -Path $DestinationPath -PathType Container
                if ($destinationPathExists) {
                    $resolvedDestinationPath = GetResolvedPathHelper $DestinationPath $false $PSCmdlet
                    if ($resolvedDestinationPath.Count -gt 1) {
                        $errorMessage = ($LocalizedData.InvalidExpandedDirPathError -f $DestinationPath)
                        ThrowTerminatingErrorHelper "InvalidDestinationPath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
                    }

                    # At this point we are sure that the provided path resolves to a valid single path.
                    # Calling Resolve-Path again to get the underlying provider name.
                    $suppliedDestinationPath = Resolve-Path -Path $DestinationPath
                    if ($suppliedDestinationPath.Provider.Name -ne "FileSystem") {
                        $errorMessage = ($LocalizedData.ExpandArchiveInValidDestinationPath -f $DestinationPath)
                        ThrowTerminatingErrorHelper "InvalidDirectoryPath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
                    }
                } else {
                    $createdItem = New-Item -Path $DestinationPath -ItemType Directory -Confirm:$isConfirm -Verbose:$isVerbose -ErrorAction Stop
                    if ($createdItem -ne $null -and $createdItem.PSProvider.Name -ne "FileSystem") {
                        Remove-Item "$DestinationPath" -Force -Recurse -ErrorAction SilentlyContinue
                        $errorMessage = ($LocalizedData.ExpandArchiveInValidDestinationPath -f $DestinationPath)
                        ThrowTerminatingErrorHelper "InvalidDirectoryPath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
                    }

                    $resolvedDestinationPath = GetResolvedPathHelper $DestinationPath $true $PSCmdlet
                }
            }

            $isWhatIf = $psboundparameters.ContainsKey("WhatIf")
            if (!$isWhatIf) {
                $preparingToExpandVerboseMessage = ($LocalizedData.PreparingToExpandVerboseMessage)
                Write-Verbose $preparingToExpandVerboseMessage

                $progressBarStatus = ($LocalizedData.ExpandProgressBarText -f $DestinationPath)
                ProgressBarHelper "Expand-Archive" $progressBarStatus 0 100 100 1
            }
        }
        PROCESS {
            switch ($PsCmdlet.ParameterSetName) {
                "Path" {
                    $resolvedSourcePaths = GetResolvedPathHelper $Path $false $PSCmdlet

                    if ($resolvedSourcePaths.Count -gt 1) {
                        $errorMessage = ($LocalizedData.InvalidArchiveFilePathError -f $Path, $PsCmdlet.ParameterSetName, $PsCmdlet.ParameterSetName)
                        ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $Path
                    }
                }
                "LiteralPath" {
                    $resolvedSourcePaths = GetResolvedPathHelper $LiteralPath $true $PSCmdlet

                    if ($resolvedSourcePaths.Count -gt 1) {
                        $errorMessage = ($LocalizedData.InvalidArchiveFilePathError -f $LiteralPath, $PsCmdlet.ParameterSetName, $PsCmdlet.ParameterSetName)
                        ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $LiteralPath
                    }
                }
            }

            ValidateArchivePathHelper $resolvedSourcePaths

            if ($pscmdlet.ShouldProcess($resolvedSourcePaths)) {
                $expandedItems = @()

                try {
                    # StopProcessing is not avaliable in Script cmdlets. However the pipleline execution
                    # is terminated when ever 'CTRL + C' is entered by user to terminate the cmdlet execution.
                    # The finally block is executed whenever pipleline is terminated.
                    # $isArchiveFileProcessingComplete variable is used to track if 'CTRL + C' is entered by the
                    # user.
                    $isArchiveFileProcessingComplete = $false

                    # The User has not provided a destination path, hence we use '$pwd\ArchiveFileName' as the directory where the
                    # archive file contents would be expanded. If the path '$pwd\ArchiveFileName' already exists then we use the
                    # Windows default mechanism of appending a counter value at the end of the directory name where the contents
                    # would be expanded.
                    if (!$isDestinationPathProvided) {
                        $archiveFile = New-Object System.IO.FileInfo $resolvedSourcePaths
                        $resolvedDestinationPath = Join-Path -Path $resolvedDestinationPath -ChildPath $archiveFile.BaseName
                        $destinationPathExists = Test-Path -LiteralPath $resolvedDestinationPath -PathType Container

                        if (!$destinationPathExists) {
                            New-Item -Path $resolvedDestinationPath -ItemType Directory -Confirm:$isConfirm -Verbose:$isVerbose -ErrorAction Stop | Out-Null
                        }
                    }

                    ExpandArchiveHelper $resolvedSourcePaths $resolvedDestinationPath ([ref]$expandedItems) $Force $isVerbose $isConfirm

                    $isArchiveFileProcessingComplete = $true
                } finally {
                    # The $isArchiveFileProcessingComplete would be set to $false if user has typed 'CTRL + C' to
                    # terminate the cmdlet execution or if an unhandled exception is thrown.
                    if ($isArchiveFileProcessingComplete -eq $false) {
                        if ($expandedItems.Count -gt 0) {
                            # delete the expanded file/directory as the archive
                            # file was not completly expanded.
                            $expandedItems | ForEach-Object { Remove-Item $_ -Force -Recurse }
                        }
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAPL6Lm8kZByQ8G
# Ej5K0vWplBMteoG0X5xF5ofq6okuxqCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCAMAOft2M/yexohRBOR2mhCPFn0GnT216BK
# JxEO3AKlbDANBgkqhkiG9w0BAQEFAASCAQCOBsem4WS7rzExibUN5wmx73Ap2Nzo
# pe252hdvGeQ022as5J90ZTLfobTST0anNQG22endrXuKkOoEm0edNtop8yVW5/mR
# An1my2uJufbVpp5DUIbahPBMaudp2+kGqVVUmiDTlw7muVc4b0gIk8tSW9Gs4dQn
# yIz9cqvw6d+Fm4U3PBsKYuYmmFwZLiG5Gyuilt0vot3FohifJ6wq2l5xIEU0rhLA
# GoUJBUzS9NyDwpksJ4p2r2M1TNm13T6SO30hUzcqWgw4RTNLpJqntzCU1ERqd0pt
# 8UelTvJv1lPXRndcuMARccG1VAcPVwWUHkif3bYpJjKkHmtFkhTl5b19oYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDQ1NlowLwYJKoZIhvcNAQkEMSIEIO/JnDPM
# 1US1q12W1VhnySU/QAMR689TW2NeDLjVmBWLMA0GCSqGSIb3DQEBAQUABIICAIAd
# sdIiVJV1M6yWgFBkqym7TjYqo+C+Ad31MIanOoce/ic00MIVSpQ3xpMrXsvWg4Gj
# 1ZY5277F1kNZ4jkWWymJoBeZXnYKWVAikfzyuBOMTWXzOgLgMT+w5rAmIZnyqco+
# FzE1xANTXZ3RM+Smp/cPxOh7R+1z1kQ3DGPfowEB+r7AHlBFlZp88xCPssHNj5oP
# QJhSMKj9ePIXRndkYvijCKne0KRAPGPqphe1wKzkwUqa0GNfYuA5+5K+tUsj1svS
# dSKpjlnXAlhAOeuF7IPtLk2tQeOc6AcTabUTZ0pmDihdafKK2pSgZJ98sYmwNDVB
# A+5Pc32qTfAQAlwJyecrFBi6ojvvEaMkirKumxJkAUtV3FA3oZVGQFxmfrRcQTOL
# Ie7rKk9NgmcYEp/Zo6sek1Z8n5seDdP90BhvBRgoF0FMbiNfBHCn1kNC7h6gzuNl
# UNhLnW9Iej3HU4zpdMT3U44eiPl6ecjpNG+BlSCmTjO3pVpfgCf0JPxVfjE1dG/1
# sz1/oVDODqI6r3QCxieGm5yoq948uu/zY5OmoxZgCPinpHmX/Ba+dL7X8CGfMRb5
# DqbwjwJdRp6omM1HyoJz8RRY7Z5Uu08CDTRVxjRCPdD6wi8J9UoeHzxsnGtJq0gF
# /yoPTadNEaT84gzvUW+PxRrpx8ei97hvfscXn9ZR
# SIG # End signature block
