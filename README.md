# SQL_Analysis
 
 This package will analyze a SQL Server stand-alone instance, cluster or AOAG and return a report outlining best practices, areas of improvement, cluster reports and a slew of other information. This test suite is comprised of checks using the DbaTools/DbcChecks PowerShell modules, Blitz stored procedures by Brent Ozar, Maintenance Plan scripts by Ola Hallengren, along with SQL/Powershell scripts written by me.

# REQUIREMENTS

    - PowerShell 5.1
    - The user running the script must have local Administrator rights on the server (or servers if a cluster), and must have the sysadmin role in SQL.
    - All required modules are already packaged with the tool, so there is no need to install anything.

# USAGE

 Usage is simple. Copy (Download as zip) or clone the repository to the machine running SQL. If this is a SQL cluster, you only need to run the script on one node. There is no need to specify instance names, as the script will dynamically determine each instance on a server or in a cluster for you.

  There is an optional single parameter with three different available values that can be passed in the command line, resulting in different output data. Ideally, you would use the option that pertains to your comfort level.

    - (-ScanType) - This is the only parameter the script has, and it has three possible values:
      - Basic: Specifying this runs only basic checks against best practices, and it also gathers pertinent OS, cluster (if this is a cluster) and SQL engine data. This is a good starting point for those with minimal SQL Server experience.
      - Advanced: Specifying this runs most best practices tests. This is geared more towards senior level engineers and architects that have experience supporting SQL servers and clusters at a more in depth level.
      - DBA: Pretty much what it sounds like. This option will run all tests from both the Basic and Advanced switches. Additionally, the test also runs a host of custom SQL scripts to return things like duplicate indexes, longest running queries by CPU/Memory Grants/Execution Times/etc. When passing this parameter options, two reports will be created; one with all the best practices tests and server/cluster information and another with all the in depth SQL queries.

# EXAMPLES

 Basic Report:

  PS> .\SQLServerAnalysis.ps1
  
  or

  PS> .\SQLServerAnalysis.ps1 -ScanType Basic

 Advanced Report:

  PS> .\SQLServerAnalysis.ps1 -ScanType Advanced

 DBA Report:

  PS> .\SQLServerAnalysis.ps1 -ScanType DBA

# OUTPUT

 Depending on the option you select, either two or three files will be created. All tests create a base ExecutionTransaction log (for debugging if needed).  

 For the Basic option, the report file name is named as follows: 
  - SERVER(or CLUSTER)_Basic_SQLServerConfigReport_DATETIME.xlsx

 For the Advanced option, the report file name is named as follows: 
  - SERVER(or CLUSTER)_Advanced_SQLServerConfigReport_DATETIME.xlsx

 For the DBA option, two files will be created:
  - SERVER(or CLUSTER)_DBA_SQLServerConfigReport_DATETIME.xlsx
  - SERVER(or CLUSTER)_DBAQueries_DATETIME.xlsx

 Additionally, while each suite of tests or script outputs its results to a separate named worksheet (tab) in the XLSX file, if the server or cluster has multiple instances, all results for all instances are saved to the same tab. For example, if I have a cluster with two instances and I run the script to return the top 10 queries by Read, the results from both instances will be appended to the same worksheet. To combat this, all columns in all worksheets are already configured for sorting and filtering via dropdown boxes. This was the only way (for now) I could make things legible while also adhering to Excel's 31 character limit for worksheet names.


# TESTS

 The test available are a comprehensive scan of a SQL deployment measured against industry best practices. For tests where best practices are defined, the report will also color code items based on the test result (Green = OK, Yellow = Test Skipped, Red = You should look at this). Note that the tests run are dependant on the -ScanType parameter passed.

    - Cluster Validation Test - The scan will generate a new Cluster Validation Report (NOTE: The scan does not run Storage tests, as this could be disruptive)
    - Server/Cluster Node OS/HW Configuration
    - General SQL Overview Test
    - SQL Server Agent Configuration Test Topics
      - DatabaseMailEnabled
      - AgentServiceAccount
      - DbaOperator
      - FailsafeOperator
      - DatabaseMailProfile
      - AgentMailProfile
      - FailedJob
      - ValidJobOwner
      - AgentAlert
      - JobHistory
      - LongRunningJob
      - LastJobRunTime
    - Database Tests (These are run against each database in each instance)
      - DatabaseCollation
      - SuspectPage
      - TestLastBackup
      - TestLastBackupVerifyOnly
      - ValidDatabaseOwner
      - InvalidDatabaseOwner
      - LastGoodCheckDb
      - IdentityUsage
      - RecoveryModel
      - DuplicateIndex
      - UnusedIndex
      - DisabledIndex
      - DatabaseGrowthEvent
      - PageVerify
      - AutoClose
      - AutoShrink
      - LastFullBackup
      - LastDiffBackup
      - LastLogBackup
      - LogfilePercentUsed
      - VirtualLogFile
      - LogfileCount
      - LogfileSize
      - FutureFileGrowth
      - FileGroupBalanced
      - CertificateExpiration
      - AutoCreateStatistics
      - AutoUpdateStatistics
      - AutoUpdateStatisticsAsynchronously
      - DatafileAutoGrowthType
      - Trustworthy
      - OrphanedUser
      - PseudoSimple
      - CompatibilityLevel
      - FKCKTrusted
      - MaxDopDatabase
      - DatabaseStatus
      - DatabaseExists
      - ContainedDBAutoClose
      - CLRAssembliesSafe
      - GuestUserConnect
      - AsymmetricKeySize
      - SymmetricKeyEncryptionLevel
      - ContainedDBSQLAuth
      - QueryStoreEnabled
      - QueryStoreDisabled
    - Domain Information
      - DomainName
      - OrganizationalUnit
    - HADR Tests (in addition to Cluster Validation Report)
    - Instance Configuration Tests
      - InstanceConnection
      - SqlEngineServiceAccount
      - TempDbConfiguration
      - AdHocWorkload
      - BackupPathAccess
      - DefaultFilePath
      - DAC
      - NetworkLatency
      - LinkedServerConnection
      - MaxMemory
      - OrphanedFile
      - ServerNameMatch
      - MemoryDump
      - SupportedBuild
      - SaRenamed
      - SaDisabled
      - SaExist
      - DefaultBackupCompression
      - XESessionStopped
      - XESessionRunning
      - XESessionRunningAllowed
      - OLEAutomation
      - WhoIsActiveInstalled
      - ModelDbGrowth
      - ADUser
      - ErrorLog
      - ErrorLogCount
      - MaxDopInstance
      - TwoDigitYearCutoff
      - TraceFlagsExpected
      - TraceFlagsNotExpected
      - CLREnabled
      - CrossDBOwnershipChaining
      - AdHocDistributedQueriesEnabled
      - XpCmdShellDisabled
      - ScanForStartupProceduresDisabled
      - DefaultTrace
      - OLEAutomationProceduresDisabled
      - RemoteAccessDisabled
      - LatestBuild
      - BuiltInAdmin
      - LocalWindowsGroup
      - LoginAuditFailed
      - LoginAuditSuccessful
      - SqlAgentProxiesNoPublicRole
      - HideInstance
      - EngineServiceAdmin
      - AgentServiceAdmin
      - FullTextServiceAdmin
      - LoginCheckPolicy
      - LoginPasswordExpiration
      - LoginMustChange
      - SuspectPageLimit
      - SqlBrowserServiceAccount
    - Log Shipping
      - LogShippingPrimary
      - LogShippingSecondary
    - Server Tests
      - PowerPlan
      - SPN
      - DiskCapacity
      - PingComputer
      - CPUPrioritisation
      - DiskAllocationUnit
      - NonStandardPort
    - Database Statistics Script - Returns a per database/per file snapshot of database performance, including read/write/average latency to the file, growth settings, file and file group settings, and average transaction size  for read and write operations.
    - Deprecated Feature Use
    - Backup history for the last 30 days
    - SQL Agent Jobs and their configurations
    - SQL Agent Job history for the last 30 days
    - SQL Maintenance Plans
    - Top 10 worst performing queries based on CPU/Memory Grants/Execution Time/etc.
    - Currently running queries in the active query store
    - Current SQL blocks, locks and deadlocks
    - Table and index compression (heap and clustered indexes)
    - Non-clustered index compression
    - Paritioned Tables with non-aligned indexes