if ($PSVersionTable.PSVersion.Major -lt 5) {

    <#
Copied from the Microsoft Module: Microsoft.PowerShell.Archive
Which ships with PowerShell Version 5 but will run under v3.
    #>



    function Compress-Archive {
        <#
            .SYNOPSIS
                Creates an archive, or zipped file, from specified files and folders.

            .DESCRIPTION
                The Compress-Archive cmdlet creates a zipped (or compressed) archive file from one or more specified files or folders. An archive file allows multiple files to be packaged, and optionally compressed, into a single zipped file for easier distribution and storage. An archive file can be compressed by using the compression algorithm specified by the CompressionLevel parameter.

                Because Compress-Archive relies upon the Microsoft .NET Framework API System.IO.Compression.ZipArchive to compress files, the maximum file size that you can compress by using Compress-Archive is currently 2 GB. This is a limitation of the underlying API.

            .PARAMETER Path
                Specifies the path or paths to the files that you want to add to the archive zipped file. This parameter can accept wildcard characters. Wildcard characters allow you to add all files in a folder to your zipped archive file. To specify multiple paths, and include files in multiple locations in your output zipped file, use commas to separate the paths.

            .PARAMETER LiteralPath
                Specifies the path or paths to the files that you want to add to the archive zipped file. Unlike the Path parameter, the value of LiteralPath is used exactly as it is typed. No characters are interpreted as wildcards. If the path includes escape characters, enclose each escape character in single quotation marks, to instruct Windows PowerShell not to interpret any characters as escape sequences. To specify multiple paths, and include files in multiple locations in your output zipped file, use commas to separate the paths.

            .PARAMETER DestinationPath
                Specifies the path to the archive output file. This parameter is required. The specified DestinationPath value should include the desired name of the output zipped file; it specifies either the absolute or relative path to the zipped file. If the file name specified in DestinationPath does not have a .zip file name extension, the cmdlet adds a .zip file name extension.

            .PARAMETER CompressionLevel
                Specifies how much compression to apply when you are creating the archive file. Faster compression requires less time to create the file, but can result in larger file sizes. The acceptable values for this parameter are:

                - Fastest. Use the fastest compression method available to decrease processing time; this can result in larger file sizes.
                - NoCompression. Do not compress the source files.
                - Optimal. Processing time is dependent on file size.

                If this parameter is not specified, the command uses the default value, Optimal.

            .PARAMETER Update
                Updates the specified archive by replacing older versions of files in the archive with newer versions of files that have the same names. You can also add this parameter to add files to an existing archive.

            .PARAMETER Force
                @{Text=}

            .PARAMETER Confirm
                Prompts you for confirmation before running the cmdlet.

            .PARAMETER WhatIf
                Shows what would happen if the cmdlet runs. The cmdlet is not run.

            .EXAMPLE
                Example 1: Create an archive file

                PS C:\>Compress-Archive -LiteralPath C:\Reference\Draftdoc.docx, C:\Reference\Images\diagram2.vsd -CompressionLevel Optimal -DestinationPath C:\Archives\Draft.Zip

                This command creates a new archive file, Draft.zip, by compressing two files, Draftdoc.docx and diagram2.vsd, specified by the LiteralPath parameter. The compression level specified for this operation is Optimal.

            .EXAMPLE
                Example 2: Create an archive with wildcard characters

                PS C:\>Compress-Archive -Path C:\Reference\* -CompressionLevel Fastest -DestinationPath C:\Archives\Draft

                This command creates a new archive file, Draft.zip, in the C:\Archives folder. Note that though the file name extension .zip was not added to the value of the DestinationPath parameter, Windows PowerShell appends this to the specified archive file name automatically. The new archive file contains every file in the C:\Reference folder, because a wildcard character was used in place of specific file names in the Path parameter. The specified compression level is Fastest, which might result in a larger output file, but compresses a large number of files faster.

            .EXAMPLE
                Example 3: Update an existing archive file

                PS C:\>Compress-Archive -Path C:\Reference\* -Update -DestinationPath C:\Archives\Draft.Zip

                This command updates an existing archive file, Draft.Zip, in the C:\Archives folder. The command is run to update Draft.Zip with newer versions of existing files that came from the C:\Reference folder, and also to add new files that have been added to C:\Reference since Draft.Zip was initially created.

            .EXAMPLE
                Example 4: Create an archive from an entire folder

                PS C:\>Compress-Archive -Path C:\Reference -DestinationPath C:\Archives\Draft

                This command creates an archive from an entire folder, C:\Reference. Note that though the file name extension .zip was not added to the value of the DestinationPath parameter, Windows PowerShell appends this to the specified archive file name automatically.
        #>
        [CmdletBinding(DefaultParameterSetName = "Path", SupportsShouldProcess, HelpUri = "http://go.microsoft.com/fwlink/?LinkID=393252")]
        param
        (
            [parameter (Mandatory, ParameterSetName = "Path", ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [parameter (Mandatory, ParameterSetName = "PathWithForce", ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [parameter (Mandatory, ParameterSetName = "PathWithUpdate", ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [ValidateNotNullOrEmpty()]
            [string[]]
            $Path,

            [parameter (Mandatory, ParameterSetName = "LiteralPath", ValueFromPipeline = $false, ValueFromPipelineByPropertyName)]
            [parameter (Mandatory, ParameterSetName = "LiteralPathWithForce", ValueFromPipeline = $false, ValueFromPipelineByPropertyName)]
            [parameter (Mandatory, ParameterSetName = "LiteralPathWithUpdate", ValueFromPipeline = $false, ValueFromPipelineByPropertyName)]
            [ValidateNotNullOrEmpty()]
            [Alias("PSPath")]
            [string[]]
            $LiteralPath,

            [parameter (Mandatory,
                Position = 1,
                ValueFromPipeline = $false,
                ValueFromPipelineByPropertyName = $false)]
            [ValidateNotNullOrEmpty()]
            [string]
            $DestinationPath,

            [parameter (
                mandatory = $false,
                ValueFromPipeline = $false,
                ValueFromPipelineByPropertyName = $false)]
            [ValidateSet("Optimal", "NoCompression", "Fastest")]
            [string]
            $CompressionLevel = "Optimal",

            [parameter(Mandatory, ParameterSetName = "PathWithUpdate", ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
            [parameter(Mandatory, ParameterSetName = "LiteralPathWithUpdate", ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
            [switch]
            $Update = $false,

            [parameter(Mandatory, ParameterSetName = "PathWithForce", ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
            [parameter(Mandatory, ParameterSetName = "LiteralPathWithForce", ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
            [switch]
            $Force = $false
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

            $inputPaths = @()
            $destinationParentDir = [system.IO.Path]::GetDirectoryName($DestinationPath)
            if ($null -eq $destinationParentDir) {
                $errorMessage = ($LocalizedData.InvalidDestinationPath -f $DestinationPath)
                ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
            }

            if ($destinationParentDir -eq [string]::Empty) {
                $destinationParentDir = '.'
            }

            $achiveFileName = [system.IO.Path]::GetFileName($DestinationPath)
            $destinationParentDir = GetResolvedPathHelper $destinationParentDir $false $PSCmdlet

            if ($destinationParentDir.Count -gt 1) {
                $errorMessage = ($LocalizedData.InvalidArchiveFilePathError -f $DestinationPath, "DestinationPath", "DestinationPath")
                ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
            }

            IsValidFileSystemPath $destinationParentDir | Out-Null
            $DestinationPath = Join-Path -Path $destinationParentDir -ChildPath $achiveFileName

            # GetExtension API does not validate for the actual existance of the path.
            $extension = [system.IO.Path]::GetExtension($DestinationPath)

            # If user does not specify .Zip extension, we append it.
            If ($extension -eq [string]::Empty) {
                $DestinationPathWithOutExtension = $DestinationPath
                $DestinationPath = $DestinationPathWithOutExtension + $zipFileExtension
                $appendArchiveFileExtensionMessage = ($LocalizedData.AppendArchiveFileExtensionMessage -f $DestinationPathWithOutExtension, $DestinationPath)
                Write-Verbose $appendArchiveFileExtensionMessage
            } else {
                # Invalid file extension is specified for the zip file to be created.
                if ($extension -ne $zipFileExtension) {
                    $errorMessage = ($LocalizedData.InvalidZipFileExtensionError -f $extension, $zipFileExtension)
                    ThrowTerminatingErrorHelper "NotSupportedArchiveFileExtension" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $extension
                }
            }

            $archiveFileExist = Test-Path -LiteralPath $DestinationPath -PathType Leaf

            if ($archiveFileExist -and ($Update -eq $false -and $Force -eq $false)) {
                $errorMessage = ($LocalizedData.ZipFileExistError -f $DestinationPath)
                ThrowTerminatingErrorHelper "ArchiveFileExists" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
            }

            # If archive file already exists and if -Update is specified, then we check to see
            # if we have write access permission to update the existing archive file.
            if ($archiveFileExist -and $Update -eq $true) {
                $item = Get-Item -Path $DestinationPath
                if ($item.Attributes.ToString().Contains("ReadOnly")) {
                    $errorMessage = ($LocalizedData.ArchiveFileIsReadOnly -f $DestinationPath)
                    ThrowTerminatingErrorHelper "ArchiveFileIsReadOnly" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidOperation) $DestinationPath
                }
            }

            $isWhatIf = $psboundparameters.ContainsKey("WhatIf")
            if (!$isWhatIf) {
                $preparingToCompressVerboseMessage = ($LocalizedData.PreparingToCompressVerboseMessage)
                Write-Verbose $preparingToCompressVerboseMessage

                $progressBarStatus = ($LocalizedData.CompressProgressBarText -f $DestinationPath)
                ProgressBarHelper "Compress-Archive" $progressBarStatus 0 100 100 1
            }
        }
        PROCESS {
            if ($PsCmdlet.ParameterSetName -eq "Path" -or
                $PsCmdlet.ParameterSetName -eq "PathWithForce" -or
                $PsCmdlet.ParameterSetName -eq "PathWithUpdate") {
                $inputPaths += $Path
            }

            if ($PsCmdlet.ParameterSetName -eq "LiteralPath" -or
                $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce" -or
                $PsCmdlet.ParameterSetName -eq "LiteralPathWithUpdate") {
                $inputPaths += $LiteralPath
            }
        }
        END {
            # If archive file already exists and if -Force is specified, we delete the
            # existing artchive file and create a brand new one.
            if (($PsCmdlet.ParameterSetName -eq "PathWithForce" -or
                    $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce") -and $archiveFileExist) {
                Remove-Item -Path $DestinationPath -Force -ErrorAction Stop
            }

            # Validate Source Path depeding on parameter set being used.
            # The specified source path conatins one or more files or directories that needs
            # to be compressed.
            $isLiteralPathUsed = $false
            if ($PsCmdlet.ParameterSetName -eq "LiteralPath" -or
                $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce" -or
                $PsCmdlet.ParameterSetName -eq "LiteralPathWithUpdate") {
                $isLiteralPathUsed = $true
            }

            ValidateDuplicateFileSystemPath $PsCmdlet.ParameterSetName $inputPaths
            $resolvedPaths = GetResolvedPathHelper $inputPaths $isLiteralPathUsed $PSCmdlet
            IsValidFileSystemPath $resolvedPaths | Out-Null

            $sourcePath = $resolvedPaths;

            # CSVHelper: This is a helper function used to append comma after each path specifid by
            # the $sourcePath array. The comma saperated paths are displayed in the -WhatIf message.
            $sourcePathInCsvFormat = CSVHelper $sourcePath
            if ($pscmdlet.ShouldProcess($sourcePathInCsvFormat)) {
                try {
                    # StopProcessing is not avaliable in Script cmdlets. However the pipleline execution
                    # is terminated when ever 'CTRL + C' is entered by user to terminate the cmdlet execution.
                    # The finally block is executed whenever pipleline is terminated.
                    # $isArchiveFileProcessingComplete variable is used to track if 'CTRL + C' is entered by the
                    # user.
                    $isArchiveFileProcessingComplete = $false

                    $numberOfItemsArchived = CompressArchiveHelper $sourcePath $DestinationPath $CompressionLevel $Update

                    $isArchiveFileProcessingComplete = $true
                } finally {
                    # The $isArchiveFileProcessingComplete would be set to $false if user has typed 'CTRL + C' to
                    # terminate the cmdlet execution or if an unhandled exception is thrown.
                    # $numberOfItemsArchived contains the count of number of files or directories add to the archive file.
                    # If the newly created archive file is empty then we delete it as its not usable.
                    if (($isArchiveFileProcessingComplete -eq $false) -or
                        ($numberOfItemsArchived -eq 0)) {
                        $DeleteArchiveFileMessage = ($LocalizedData.DeleteArchiveFile -f $DestinationPath)
                        Write-Verbose $DeleteArchiveFileMessage

                        # delete the partial archive file created.
                        if (Test-Path $DestinationPath) {
                            Remove-Item -LiteralPath $DestinationPath -Force -Recurse -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU15pU+7Qx8kXADN8lJSi26USR
# 88ugghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFI5z6PGMR8l+nd0y8f03HydIJ5krMA0G
# CSqGSIb3DQEBAQUABIIBAKuAMjOhPPCqkOCTCS3h1xhzxKJ4rzmVlOD5L3eTLixp
# ktBS3N6qQ74LElPY50JcIofieCpUcRo5wwP7lZh9JY9M56QQY/9UKSkTpO6T+7HZ
# 7M01UFOdHXJIja5yGu7rXx4VJ3JiPbVbjv1hRdtmGv6AGpSqnbWPssPDFA9zCbY1
# 2WGk+nMwauJCY9KnAPzHwWh0Y3JMx/QDe0MCRSbI/kvjiXeLnb1OTfEg3bOmUOcW
# ZA9AU4Blb0njcT+NGv4rZquEilteGlXHXhAbOYN/1/AiXjOITVWVu9ax808KpJCF
# HUpJe9QShPG7fsH+s9iR4tzoJem7/rEcMKhHAwdRZDKhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNTAwWjAvBgkqhkiG9w0BCQQxIgQgm2bhcXzfnxDmwrGtY5Ob
# kiDcVqKtMcYU5qx87hWbbsgwDQYJKoZIhvcNAQEBBQAEggIAXrgV522m6YED6M1w
# A0jUxCHnHaJJFG9A0LKmaMtRtPZdd7Oi6tTKHkQxyogksvnsbFrsOJW6YsE8B69f
# ncgdZf3eY1IAsfHTKcqInEk0RDto3fpjnur+MgT7Zijz5FdqcsFOndltaK4GXpF6
# V8+bM1pojrWcqKI0qEiHe4PzschyubVM3ozbYTVAoCNbFMi7hZXCc0YAC7f/FSOi
# g5n29enlQmC7aswotpRVVmKDMbuekDoTLnPaSZMM0LDMZUY+Bzb/V+toQuw1Q/y6
# IN7P3oX5gkaydZcM/DhZU4aOQRM2Y9JzCRg8VO0fOGv4hsmvfGuKm3OyToUBDuem
# YTLipZ0TjofenGvpj6KcYZrL+XKLxTh7Dzh9kvtocwUWmmaxka2OTvX9AJUIq0qd
# M3m3USzWSeeIAxn43Tg3aUzwxDEJABoC6V70w5QCpuWWPMwLuNcIZYbbL8zBKTTA
# It5aHqagpTvpeYJaGn/rsngJfkHnQ6JOfi7RwwoZ04mra6tFu3DoV3MpRERZHByw
# yiCD3GXA1xTRoUnFnnnUZpcU7eRYgzQwm+nts+0PtYJ/prP83rXLfPHcvwQkBhWZ
# kr9Emk08dRUWhYEHinYqeljLo0viqaMy8bZPCFbit/j/kWUJ6UQxp5h40w57rqf2
# 3ok/BvvA6hK6bL2rUZmzA4+njH8=
# SIG # End signature block
