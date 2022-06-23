function Get-DbaWaitStatistic {
    <#
    .SYNOPSIS
        Displays wait statistics

    .DESCRIPTION
        This command is based off of Paul Randal's post "Wait statistics, or please tell me where it hurts"

        Returns:
        WaitType
        Category
        WaitSeconds
        ResourceSeconds
        SignalSeconds
        WaitCount
        Percentage
        AverageWaitSeconds
        AverageResourceSeconds
        AverageSignalSeconds
        URL

        Reference: https://www.sqlskills.com/blogs/paul/wait-statistics-or-please-tell-me-where-it-hurts/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Threshold
        Threshold, in percentage of all waits on the system. Default per Paul's post is 95%.

    .PARAMETER IncludeIgnorable
        Some waits are no big deal and can be safely ignored in most circumstances. If you've got weird issues with mirroring or AGs.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Waits, WaitStats
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWaitStatistic

    .EXAMPLE
        PS C:\> Get-DbaWaitStatistic -SqlInstance sql2008, sqlserver2012

        Check wait statistics for servers sql2008 and sqlserver2012

    .EXAMPLE
        PS C:\> Get-DbaWaitStatistic -SqlInstance sql2008 -Threshold 98 -IncludeIgnorable

        Check wait statistics on server sql2008 for thresholds above 98% and include wait stats that are most often, but not always, ignorable

    .EXAMPLE
        PS C:\> Get-DbaWaitStatistic -SqlInstance sql2008 | Select-Object *

        Shows detailed notes, if available, from Paul's post

    .EXAMPLE
        PS C:\> $output = Get-DbaWaitStatistic -SqlInstance sql2008 -Threshold 100 -IncludeIgnorable | Select-Object * | ConvertTo-DbaDataTable

        Collects all Wait Statistics (including ignorable waits) on server sql2008 into a Data Table.

    .EXAMPLE
        PS C:\> $output = Get-DbaWaitStatistic -SqlInstance sql2008
        PS C:\> foreach ($row in ($output | Sort-Object -Unique Url)) { Start-Process ($row).Url }

        Displays the output then loads the associated sqlskills website for each result. Opens one tab per unique URL.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$Threshold = 95,
        [switch]$IncludeIgnorable,
        [switch]$EnableException
    )

    begin {

        $details = [pscustomobject]@{
            CXPACKET                         = "This indicates parallelism, not necessarily that there's a problem. The coordinator thread in a parallel query always accumulates these waits. If the parallel threads are not given equal amounts of work to do, or one thread blocks, the waiting threads will also accumulate CXPACKET waits, which will make them aggregate a lot faster - this is a problem. One thread may have a lot more to do than the others, and so the whole query is blocked while the long-running thread completes. If this is combined with a high number of PAGEIOLATCH_XX waits, it could be large parallel table scans going on because of incorrect non-clustered indexes, or a bad query plan. If neither of these are the issue, you might want to try setting MAXDOP to 4, 2, or 1 for the offending queries (or possibly the whole instance). Make sure that if you have a NUMA system that you try setting MAXDOP to the number of cores in a single NUMA node first to see if that helps the problem. You also need to consider the MAXDOP effect on a mixed-load system. Play with the cost threshold for parallelism setting (bump it up to, say, 25) before reducing the MAXDOP of the whole instance. And don't forget Resource Governor in Enterprise Edition of  SQL Server 2008 onward that allows DOP governing for a particular group of connections to the server."
            PAGEIOLATCH_XX                   = "This is where SQL Server is waiting for a data page to be read from disk into memory. It may indicate a bottleneck at the IO subsystem level (which is a common knee-jerk response to seeing these), but why is the I/O subsystem having to service so many reads? It could be buffer pool/memory pressure (i.e. not enough memory for the workload), a sudden change in query plans causing a large parallel scan instead of a seek, plan cache bloat, or a number of other things. Don't assume the root cause is the I/O subsystem."
            ASYNC_NETWORK_IO                 = "This is usually where SQL Server is waiting for a client to finish consuming data. It could be that the client has asked for a very large amount of data or just that it's consuming it reeeeeally slowly because of poor programming - I rarely see this being a network issue. Clients often process one row at a time - called RBAR or Row-By-Agonizing-Row - instead of caching the data on the client and acknowledging to SQL Server immediately."
            WRITELOG                         = "This is the log management system waiting for a log flush to disk. It commonly indicates that the I/O subsystem can't keep up with the log flush volume, but on very high-volume systems it could also be caused by internal log flush limits, that may mean you have to split your workload over multiple databases or even make your transactions a little longer to reduce log flushes. To be sure it is the I/O subsystem, use the DMV sys.dm_io_virtual_file_stats to examine the I/O latency for the log file and see if it correlates to the average WRITELOG time. If WRITELOG is longer, you've got internal contention and need to shard. If not, investigate why you're creating so much transaction log."
            BROKER_RECEIVE_WAITFOR           = "This is just Service Broker waiting around for new messages to receive. I would add this to the list of waits to filter out and re-run the wait stats query."
            MSQL_XP                          = "This is SQL Server waiting for an extended stored-proc to finish. This could indicate a problem in your XP code."
            OLEDB                            = "As its name suggests, this is a wait for something communicating using OLEDB - e.g. a linked server. However, OLEDB is also used by all DMVs and by DBCC CHECKDB, so don't assume linked servers are the problem - it could be a third-party monitoring tool making excessive DMV calls. If it *is* a linked server (wait times in the 10s or 100s of milliseconds), go to the linked server and do wait stats analysis there to figure out what the performance issue is there."
            BACKUPIO                         = "This can show up when you're backing up to a slow I/O subsystem, like directly to tape, which is slooooow, or over a network."
            LCK_M_XX                         = "This is simply the thread waiting for a lock to be granted and indicates blocking problems. These could be caused by unwanted lock escalation or bad programming, but could also be from I/Os taking a long time causing locks to be held for longer than usual. Look at the resource associated with the lock using the DMV sys.dm_os_waiting_tasks. Don't assume that locking is the root cause."
            ONDEMAND_TASK_QUEUE              = "This is normal and is part of the background task system (e.g. deferred drop, ghost cleanup).  I would add this to the list of waits to filter out and re-run the wait stats query."
            BACKUPBUFFER                     = "This commonly show up with BACKUPIO and is a backup thread waiting for a buffer to write backup data into."
            IO_COMPLETION                    = "This is SQL Server waiting for non-data page I/Os to complete and could be an indication that the I/O subsystem is overloaded if the latencies look high (see Are I/O latencies killing your performance?)"
            SOS_SCHEDULER_YIELD              = "This is code running that doesn't hit any resource waits."
            DBMIRROR_EVENTS_QUEUE            = "These two are database mirroring just sitting around waiting for something to do. I would add these to the list of waits to filter out and re-run the wait stats query."
            DBMIRRORING_CMD                  = "These two are database mirroring just sitting around waiting for something to do. I would add these to the list of waits to filter out and re-run the wait stats query."
            PAGELATCH_XX                     = "This is contention for access to in-memory copies of pages. The most well-known cases of these are the PFS and SGAM contention that can occur in tempdb under certain workloads. To find out what page the contention is on, you'll need to use the DMV sys.dm_os_waiting_tasks to figure out what page the latch is for. For tempdb issues, Robert Davis (blog | twitter) has a good post showing how to do this. Another common cause I've seen is an index hot-spot with concurrent inserts into an index with an identity value key."
            LATCH_XX                         = "This is contention for some non-page structure inside SQL Server - so not related to I/O or data at all. These can be hard to figure out and you're going to be using the DMV sys.dm_os_latch_stats. More on this in my Latches category."
            PREEMPTIVE_OS_PIPEOPS            = "This is SQL Server switching to preemptive scheduling mode to call out to Windows for something, and this particular wait is usually from using xp_cmdshell. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            THREADPOOL                       = "This says that there aren't enough worker threads on the system to satisfy demand. Commonly this is large numbers of high-DOP queries trying to execute and taking all the threads from the thread pool."
            BROKER_TRANSMITTER               = "This is just Service Broker waiting around for new messages to send. I would add this to the list of waits to filter out and re-run the wait stats query."
            SQLTRACE_WAIT_ENTRIES            = "Part of SQL Trace. I would add this to the list of waits to filter out and re-run the wait stats query."
            DBMIRROR_DBM_MUTEX               = "This one is undocumented and is contention for the send buffer that database mirroring shares between all the mirroring sessions on a server. It could indicate that you've got too many mirroring sessions."
            RESOURCE_SEMAPHORE               = "This is queries waiting for execution memory (the memory used to process the query operators - like a sort). This could be memory pressure or a very high concurrent workload."
            PREEMPTIVE_OS_AUTHENTICATIONOPS  = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            PREEMPTIVE_OS_GENERICOPS         = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            SLEEP_BPOOL_FLUSH                = "This is normal to see and indicates that checkpoint is throttling itself to avoid overloading the IO subsystem. I would add this to the list of waits to filter out and re-run the wait stats query."
            MSQL_DQ                          = "This is SQL Server waiting for a distributed query to finish. This could indicate a problem with the distributed query, or it could just be normal."
            RESOURCE_SEMAPHORE_QUERY_COMPILE = "When there are too many concurrent query compilations going on, SQL Server will throttle them. I don't remember the threshold, but this can indicate excessive recompilation, or maybe single-use plans."
            DAC_INIT                         = "This is the Dedicated Admin Connection initializing."
            MSSEARCH                         = "This is normal to see for full-text operations.  If this is the highest wait, it could mean your system is spending most of its time doing full-text queries. You might want to consider adding this to the filter list."
            PREEMPTIVE_OS_FILEOPS            = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            PREEMPTIVE_OS_LIBRARYOPS         = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            PREEMPTIVE_OS_LOOKUPACCOUNTSID   = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            PREEMPTIVE_OS_QUERYREGISTRY      = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            SQLTRACE_LOCK                    = "Part of SQL Trace. I would add this to the list of waits to filter out and re-run the wait stats query."
        }

        # Thanks Brent Ozar via https://gist.github.com/BrentOzar/42e82ee0603a1917c17d74c3fca26d34
        # Thanks Marcin Gminski via https://www.dropbox.com/s/x3zr7u18tc1ojey/WaitStats.sql?dl=0

        $category = [pscustomobject]@{
            ASYNC_IO_COMPLETION                             = 'Other Disk IO'
            ASYNC_NETWORK_IO                                = 'Network IO'
            BACKUPIO                                        = 'Other Disk IO'
            BROKER_CONNECTION_RECEIVE_TASK                  = 'Service Broker'
            BROKER_DISPATCHER                               = 'Service Broker'
            BROKER_ENDPOINT_STATE_MUTEX                     = 'Service Broker'
            BROKER_EVENTHANDLER                             = 'Service Broker'
            BROKER_FORWARDER                                = 'Service Broker'
            BROKER_INIT                                     = 'Service Broker'
            BROKER_MASTERSTART                              = 'Service Broker'
            BROKER_RECEIVE_WAITFOR                          = 'User Wait'
            BROKER_REGISTERALLENDPOINTS                     = 'Service Broker'
            BROKER_SERVICE                                  = 'Service Broker'
            BROKER_SHUTDOWN                                 = 'Service Broker'
            BROKER_START                                    = 'Service Broker'
            BROKER_TASK_SHUTDOWN                            = 'Service Broker'
            BROKER_TASK_STOP                                = 'Service Broker'
            BROKER_TASK_SUBMIT                              = 'Service Broker'
            BROKER_TO_FLUSH                                 = 'Service Broker'
            BROKER_TRANSMISSION_OBJECT                      = 'Service Broker'
            BROKER_TRANSMISSION_TABLE                       = 'Service Broker'
            BROKER_TRANSMISSION_WORK                        = 'Service Broker'
            BROKER_TRANSMITTER                              = 'Service Broker'
            CHECKPOINT_QUEUE                                = 'Idle'
            CHKPT                                           = 'Tran Log IO'
            CLR_AUTO_EVENT                                  = 'SQL CLR'
            CLR_CRST                                        = 'SQL CLR'
            CLR_JOIN                                        = 'SQL CLR'
            CLR_MANUAL_EVENT                                = 'SQL CLR'
            CLR_MEMORY_SPY                                  = 'SQL CLR'
            CLR_MONITOR                                     = 'SQL CLR'
            CLR_RWLOCK_READER                               = 'SQL CLR'
            CLR_RWLOCK_WRITER                               = 'SQL CLR'
            CLR_SEMAPHORE                                   = 'SQL CLR'
            CLR_TASK_START                                  = 'SQL CLR'
            CLRHOST_STATE_ACCESS                            = 'SQL CLR'
            CMEMPARTITIONED                                 = 'Memory'
            CMEMTHREAD                                      = 'Memory'
            CXPACKET                                        = 'Parallelism'
            DBMIRROR_DBM_EVENT                              = 'Mirroring'
            DBMIRROR_DBM_MUTEX                              = 'Mirroring'
            DBMIRROR_EVENTS_QUEUE                           = 'Mirroring'
            DBMIRROR_SEND                                   = 'Mirroring'
            DBMIRROR_WORKER_QUEUE                           = 'Mirroring'
            DBMIRRORING_CMD                                 = 'Mirroring'
            DTC                                             = 'Transaction'
            DTC_ABORT_REQUEST                               = 'Transaction'
            DTC_RESOLVE                                     = 'Transaction'
            DTC_STATE                                       = 'Transaction'
            DTC_TMDOWN_REQUEST                              = 'Transaction'
            DTC_WAITFOR_OUTCOME                             = 'Transaction'
            DTCNEW_ENLIST                                   = 'Transaction'
            DTCNEW_PREPARE                                  = 'Transaction'
            DTCNEW_RECOVERY                                 = 'Transaction'
            DTCNEW_TM                                       = 'Transaction'
            DTCNEW_TRANSACTION_ENLISTMENT                   = 'Transaction'
            DTCPNTSYNC                                      = 'Transaction'
            EE_PMOLOCK                                      = 'Memory'
            EXCHANGE                                        = 'Parallelism'
            EXTERNAL_SCRIPT_NETWORK_IOF                     = 'Network IO'
            FCB_REPLICA_READ                                = 'Replication'
            FCB_REPLICA_WRITE                               = 'Replication'
            FT_COMPROWSET_RWLOCK                            = 'Full Text Search'
            FT_IFTS_RWLOCK                                  = 'Full Text Search'
            FT_IFTS_SCHEDULER_IDLE_WAIT                     = 'Idle'
            FT_IFTSHC_MUTEX                                 = 'Full Text Search'
            FT_IFTSISM_MUTEX                                = 'Full Text Search'
            FT_MASTER_MERGE                                 = 'Full Text Search'
            FT_MASTER_MERGE_COORDINATOR                     = 'Full Text Search'
            FT_METADATA_MUTEX                               = 'Full Text Search'
            FT_PROPERTYLIST_CACHE                           = 'Full Text Search'
            FT_RESTART_CRAWL                                = 'Full Text Search'
            'FULLTEXT GATHERER'                             = 'Full Text Search'
            HADR_AG_MUTEX                                   = 'Replication'
            HADR_AR_CRITICAL_SECTION_ENTRY                  = 'Replication'
            HADR_AR_MANAGER_MUTEX                           = 'Replication'
            HADR_AR_UNLOAD_COMPLETED                        = 'Replication'
            HADR_ARCONTROLLER_NOTIFICATIONS_SUBSCRIBER_LIST = 'Replication'
            HADR_BACKUP_BULK_LOCK                           = 'Replication'
            HADR_BACKUP_QUEUE                               = 'Replication'
            HADR_CLUSAPI_CALL                               = 'Replication'
            HADR_COMPRESSED_CACHE_SYNC                      = 'Replication'
            HADR_CONNECTIVITY_INFO                          = 'Replication'
            HADR_DATABASE_FLOW_CONTROL                      = 'Replication'
            HADR_DATABASE_VERSIONING_STATE                  = 'Replication'
            HADR_DATABASE_WAIT_FOR_RECOVERY                 = 'Replication'
            HADR_DATABASE_WAIT_FOR_RESTART                  = 'Replication'
            HADR_DATABASE_WAIT_FOR_TRANSITION_TO_VERSIONING = 'Replication'
            HADR_DB_COMMAND                                 = 'Replication'
            HADR_DB_OP_COMPLETION_SYNC                      = 'Replication'
            HADR_DB_OP_START_SYNC                           = 'Replication'
            HADR_DBR_SUBSCRIBER                             = 'Replication'
            HADR_DBR_SUBSCRIBER_FILTER_LIST                 = 'Replication'
            HADR_DBSEEDING                                  = 'Replication'
            HADR_DBSEEDING_LIST                             = 'Replication'
            HADR_DBSTATECHANGE_SYNC                         = 'Replication'
            HADR_FABRIC_CALLBACK                            = 'Replication'
            HADR_FILESTREAM_BLOCK_FLUSH                     = 'Replication'
            HADR_FILESTREAM_FILE_CLOSE                      = 'Replication'
            HADR_FILESTREAM_FILE_REQUEST                    = 'Replication'
            HADR_FILESTREAM_IOMGR                           = 'Replication'
            HADR_FILESTREAM_IOMGR_IOCOMPLETION              = 'Replication'
            HADR_FILESTREAM_MANAGER                         = 'Replication'
            HADR_FILESTREAM_PREPROC                         = 'Replication'
            HADR_GROUP_COMMIT                               = 'Replication'
            HADR_LOGCAPTURE_SYNC                            = 'Replication'
            HADR_LOGCAPTURE_WAIT                            = 'Replication'
            HADR_LOGPROGRESS_SYNC                           = 'Replication'
            HADR_NOTIFICATION_DEQUEUE                       = 'Replication'
            HADR_NOTIFICATION_WORKER_EXCLUSIVE_ACCESS       = 'Replication'
            HADR_NOTIFICATION_WORKER_STARTUP_SYNC           = 'Replication'
            HADR_NOTIFICATION_WORKER_TERMINATION_SYNC       = 'Replication'
            HADR_PARTNER_SYNC                               = 'Replication'
            HADR_READ_ALL_NETWORKS                          = 'Replication'
            HADR_RECOVERY_WAIT_FOR_CONNECTION               = 'Replication'
            HADR_RECOVERY_WAIT_FOR_UNDO                     = 'Replication'
            HADR_REPLICAINFO_SYNC                           = 'Replication'
            HADR_SEEDING_CANCELLATION                       = 'Replication'
            HADR_SEEDING_FILE_LIST                          = 'Replication'
            HADR_SEEDING_LIMIT_BACKUPS                      = 'Replication'
            HADR_SEEDING_SYNC_COMPLETION                    = 'Replication'
            HADR_SEEDING_TIMEOUT_TASK                       = 'Replication'
            HADR_SEEDING_WAIT_FOR_COMPLETION                = 'Replication'
            HADR_SYNC_COMMIT                                = 'Replication'
            HADR_SYNCHRONIZING_THROTTLE                     = 'Replication'
            HADR_TDS_LISTENER_SYNC                          = 'Replication'
            HADR_TDS_LISTENER_SYNC_PROCESSING               = 'Replication'
            HADR_THROTTLE_LOG_RATE_GOVERNOR                 = 'Log Rate Governor'
            HADR_TIMER_TASK                                 = 'Replication'
            HADR_TRANSPORT_DBRLIST                          = 'Replication'
            HADR_TRANSPORT_FLOW_CONTROL                     = 'Replication'
            HADR_TRANSPORT_SESSION                          = 'Replication'
            HADR_WORK_POOL                                  = 'Replication'
            HADR_WORK_QUEUE                                 = 'Replication'
            HADR_XRF_STACK_ACCESS                           = 'Replication'
            INSTANCE_LOG_RATE_GOVERNOR                      = 'Log Rate Governor'
            IO_COMPLETION                                   = 'Other Disk IO'
            IO_QUEUE_LIMIT                                  = 'Other Disk IO'
            IO_RETRY                                        = 'Other Disk IO'
            LATCH_DT                                        = 'Latch'
            LATCH_EX                                        = 'Latch'
            LATCH_KP                                        = 'Latch'
            LATCH_NL                                        = 'Latch'
            LATCH_SH                                        = 'Latch'
            LATCH_UP                                        = 'Latch'
            LAZYWRITER_SLEEP                                = 'Idle'
            LCK_M_BU                                        = 'Lock'
            LCK_M_BU_ABORT_BLOCKERS                         = 'Lock'
            LCK_M_BU_LOW_PRIORITY                           = 'Lock'
            LCK_M_IS                                        = 'Lock'
            LCK_M_IS_ABORT_BLOCKERS                         = 'Lock'
            LCK_M_IS_LOW_PRIORITY                           = 'Lock'
            LCK_M_IU                                        = 'Lock'
            LCK_M_IU_ABORT_BLOCKERS                         = 'Lock'
            LCK_M_IU_LOW_PRIORITY                           = 'Lock'
            LCK_M_IX                                        = 'Lock'
            LCK_M_IX_ABORT_BLOCKERS                         = 'Lock'
            LCK_M_IX_LOW_PRIORITY                           = 'Lock'
            LCK_M_RIn_NL                                    = 'Lock'
            LCK_M_RIn_NL_ABORT_BLOCKERS                     = 'Lock'
            LCK_M_RIn_NL_LOW_PRIORITY                       = 'Lock'
            LCK_M_RIn_S                                     = 'Lock'
            LCK_M_RIn_S_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_RIn_S_LOW_PRIORITY                        = 'Lock'
            LCK_M_RIn_U                                     = 'Lock'
            LCK_M_RIn_U_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_RIn_U_LOW_PRIORITY                        = 'Lock'
            LCK_M_RIn_X                                     = 'Lock'
            LCK_M_RIn_X_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_RIn_X_LOW_PRIORITY                        = 'Lock'
            LCK_M_RS_S                                      = 'Lock'
            LCK_M_RS_S_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RS_S_LOW_PRIORITY                         = 'Lock'
            LCK_M_RS_U                                      = 'Lock'
            LCK_M_RS_U_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RS_U_LOW_PRIORITY                         = 'Lock'
            LCK_M_RX_S                                      = 'Lock'
            LCK_M_RX_S_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RX_S_LOW_PRIORITY                         = 'Lock'
            LCK_M_RX_U                                      = 'Lock'
            LCK_M_RX_U_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RX_U_LOW_PRIORITY                         = 'Lock'
            LCK_M_RX_X                                      = 'Lock'
            LCK_M_RX_X_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RX_X_LOW_PRIORITY                         = 'Lock'
            LCK_M_S                                         = 'Lock'
            LCK_M_S_ABORT_BLOCKERS                          = 'Lock'
            LCK_M_S_LOW_PRIORITY                            = 'Lock'
            LCK_M_SCH_M                                     = 'Lock'
            LCK_M_SCH_M_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_SCH_M_LOW_PRIORITY                        = 'Lock'
            LCK_M_SCH_S                                     = 'Lock'
            LCK_M_SCH_S_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_SCH_S_LOW_PRIORITY                        = 'Lock'
            LCK_M_SIU                                       = 'Lock'
            LCK_M_SIU_ABORT_BLOCKERS                        = 'Lock'
            LCK_M_SIU_LOW_PRIORITY                          = 'Lock'
            LCK_M_SIX                                       = 'Lock'
            LCK_M_SIX_ABORT_BLOCKERS                        = 'Lock'
            LCK_M_SIX_LOW_PRIORITY                          = 'Lock'
            LCK_M_U                                         = 'Lock'
            LCK_M_U_ABORT_BLOCKERS                          = 'Lock'
            LCK_M_U_LOW_PRIORITY                            = 'Lock'
            LCK_M_UIX                                       = 'Lock'
            LCK_M_UIX_ABORT_BLOCKERS                        = 'Lock'
            LCK_M_UIX_LOW_PRIORITY                          = 'Lock'
            LCK_M_X                                         = 'Lock'
            LCK_M_X_ABORT_BLOCKERS                          = 'Lock'
            LCK_M_X_LOW_PRIORITY                            = 'Lock'
            LOGBUFFER                                       = 'Tran Log IO'
            LOGMGR                                          = 'Tran Log IO'
            LOGMGR_FLUSH                                    = 'Tran Log IO'
            LOGMGR_PMM_LOG                                  = 'Tran Log IO'
            LOGMGR_QUEUE                                    = 'Idle'
            LOGMGR_RESERVE_APPEND                           = 'Tran Log IO'
            MEMORY_ALLOCATION_EXT                           = 'Memory'
            MEMORY_GRANT_UPDATE                             = 'Memory'
            MSQL_XACT_MGR_MUTEX                             = 'Transaction'
            MSQL_XACT_MUTEX                                 = 'Transaction'
            MSSEARCH                                        = 'Full Text Search'
            NET_WAITFOR_PACKET                              = 'Network IO'
            ONDEMAND_TASK_QUEUE                             = 'Idle'
            PAGEIOLATCH_DT                                  = 'Buffer IO'
            PAGEIOLATCH_EX                                  = 'Buffer IO'
            PAGEIOLATCH_KP                                  = 'Buffer IO'
            PAGEIOLATCH_NL                                  = 'Buffer IO'
            PAGEIOLATCH_SH                                  = 'Buffer IO'
            PAGEIOLATCH_UP                                  = 'Buffer IO'
            PAGELATCH_DT                                    = 'Buffer Latch'
            PAGELATCH_EX                                    = 'Buffer Latch'
            PAGELATCH_KP                                    = 'Buffer Latch'
            PAGELATCH_NL                                    = 'Buffer Latch'
            PAGELATCH_SH                                    = 'Buffer Latch'
            PAGELATCH_UP                                    = 'Buffer Latch'
            POOL_LOG_RATE_GOVERNOR                          = 'Log Rate Governor'
            PREEMPTIVE_ABR                                  = 'Preemptive'
            PREEMPTIVE_CLOSEBACKUPMEDIA                     = 'Preemptive'
            PREEMPTIVE_CLOSEBACKUPTAPE                      = 'Preemptive'
            PREEMPTIVE_CLOSEBACKUPVDIDEVICE                 = 'Preemptive'
            PREEMPTIVE_CLUSAPI_CLUSTERRESOURCECONTROL       = 'Preemptive'
            PREEMPTIVE_COM_COCREATEINSTANCE                 = 'Preemptive'
            PREEMPTIVE_COM_COGETCLASSOBJECT                 = 'Preemptive'
            PREEMPTIVE_COM_CREATEACCESSOR                   = 'Preemptive'
            PREEMPTIVE_COM_DELETEROWS                       = 'Preemptive'
            PREEMPTIVE_COM_GETCOMMANDTEXT                   = 'Preemptive'
            PREEMPTIVE_COM_GETDATA                          = 'Preemptive'
            PREEMPTIVE_COM_GETNEXTROWS                      = 'Preemptive'
            PREEMPTIVE_COM_GETRESULT                        = 'Preemptive'
            PREEMPTIVE_COM_GETROWSBYBOOKMARK                = 'Preemptive'
            PREEMPTIVE_COM_LBFLUSH                          = 'Preemptive'
            PREEMPTIVE_COM_LBLOCKREGION                     = 'Preemptive'
            PREEMPTIVE_COM_LBREADAT                         = 'Preemptive'
            PREEMPTIVE_COM_LBSETSIZE                        = 'Preemptive'
            PREEMPTIVE_COM_LBSTAT                           = 'Preemptive'
            PREEMPTIVE_COM_LBUNLOCKREGION                   = 'Preemptive'
            PREEMPTIVE_COM_LBWRITEAT                        = 'Preemptive'
            PREEMPTIVE_COM_QUERYINTERFACE                   = 'Preemptive'
            PREEMPTIVE_COM_RELEASE                          = 'Preemptive'
            PREEMPTIVE_COM_RELEASEACCESSOR                  = 'Preemptive'
            PREEMPTIVE_COM_RELEASEROWS                      = 'Preemptive'
            PREEMPTIVE_COM_RELEASESESSION                   = 'Preemptive'
            PREEMPTIVE_COM_RESTARTPOSITION                  = 'Preemptive'
            PREEMPTIVE_COM_SEQSTRMREAD                      = 'Preemptive'
            PREEMPTIVE_COM_SEQSTRMREADANDWRITE              = 'Preemptive'
            PREEMPTIVE_COM_SETDATAFAILURE                   = 'Preemptive'
            PREEMPTIVE_COM_SETPARAMETERINFO                 = 'Preemptive'
            PREEMPTIVE_COM_SETPARAMETERPROPERTIES           = 'Preemptive'
            PREEMPTIVE_COM_STRMLOCKREGION                   = 'Preemptive'
            PREEMPTIVE_COM_STRMSEEKANDREAD                  = 'Preemptive'
            PREEMPTIVE_COM_STRMSEEKANDWRITE                 = 'Preemptive'
            PREEMPTIVE_COM_STRMSETSIZE                      = 'Preemptive'
            PREEMPTIVE_COM_STRMSTAT                         = 'Preemptive'
            PREEMPTIVE_COM_STRMUNLOCKREGION                 = 'Preemptive'
            PREEMPTIVE_CONSOLEWRITE                         = 'Preemptive'
            PREEMPTIVE_CREATEPARAM                          = 'Preemptive'
            PREEMPTIVE_DEBUG                                = 'Preemptive'
            PREEMPTIVE_DFSADDLINK                           = 'Preemptive'
            PREEMPTIVE_DFSLINKEXISTCHECK                    = 'Preemptive'
            PREEMPTIVE_DFSLINKHEALTHCHECK                   = 'Preemptive'
            PREEMPTIVE_DFSREMOVELINK                        = 'Preemptive'
            PREEMPTIVE_DFSREMOVEROOT                        = 'Preemptive'
            PREEMPTIVE_DFSROOTFOLDERCHECK                   = 'Preemptive'
            PREEMPTIVE_DFSROOTINIT                          = 'Preemptive'
            PREEMPTIVE_DFSROOTSHARECHECK                    = 'Preemptive'
            PREEMPTIVE_DTC_ABORT                            = 'Preemptive'
            PREEMPTIVE_DTC_ABORTREQUESTDONE                 = 'Preemptive'
            PREEMPTIVE_DTC_BEGINTRANSACTION                 = 'Preemptive'
            PREEMPTIVE_DTC_COMMITREQUESTDONE                = 'Preemptive'
            PREEMPTIVE_DTC_ENLIST                           = 'Preemptive'
            PREEMPTIVE_DTC_PREPAREREQUESTDONE               = 'Preemptive'
            PREEMPTIVE_FILESIZEGET                          = 'Preemptive'
            PREEMPTIVE_FSAOLEDB_ABORTTRANSACTION            = 'Preemptive'
            PREEMPTIVE_FSAOLEDB_COMMITTRANSACTION           = 'Preemptive'
            PREEMPTIVE_FSAOLEDB_STARTTRANSACTION            = 'Preemptive'
            PREEMPTIVE_FSRECOVER_UNCONDITIONALUNDO          = 'Preemptive'
            PREEMPTIVE_GETRMINFO                            = 'Preemptive'
            PREEMPTIVE_HADR_LEASE_MECHANISM                 = 'Preemptive'
            PREEMPTIVE_HTTP_EVENT_WAIT                      = 'Preemptive'
            PREEMPTIVE_HTTP_REQUEST                         = 'Preemptive'
            PREEMPTIVE_LOCKMONITOR                          = 'Preemptive'
            PREEMPTIVE_MSS_RELEASE                          = 'Preemptive'
            PREEMPTIVE_ODBCOPS                              = 'Preemptive'
            PREEMPTIVE_OLE_UNINIT                           = 'Preemptive'
            PREEMPTIVE_OLEDB_ABORTORCOMMITTRAN              = 'Preemptive'
            PREEMPTIVE_OLEDB_ABORTTRAN                      = 'Preemptive'
            PREEMPTIVE_OLEDB_GETDATASOURCE                  = 'Preemptive'
            PREEMPTIVE_OLEDB_GETLITERALINFO                 = 'Preemptive'
            PREEMPTIVE_OLEDB_GETPROPERTIES                  = 'Preemptive'
            PREEMPTIVE_OLEDB_GETPROPERTYINFO                = 'Preemptive'
            PREEMPTIVE_OLEDB_GETSCHEMALOCK                  = 'Preemptive'
            PREEMPTIVE_OLEDB_JOINTRANSACTION                = 'Preemptive'
            PREEMPTIVE_OLEDB_RELEASE                        = 'Preemptive'
            PREEMPTIVE_OLEDB_SETPROPERTIES                  = 'Preemptive'
            PREEMPTIVE_OLEDBOPS                             = 'Preemptive'
            PREEMPTIVE_OS_ACCEPTSECURITYCONTEXT             = 'Preemptive'
            PREEMPTIVE_OS_ACQUIRECREDENTIALSHANDLE          = 'Preemptive'
            PREEMPTIVE_OS_AUTHENTICATIONOPS                 = 'Preemptive'
            PREEMPTIVE_OS_AUTHORIZATIONOPS                  = 'Preemptive'
            PREEMPTIVE_OS_AUTHZGETINFORMATIONFROMCONTEXT    = 'Preemptive'
            PREEMPTIVE_OS_AUTHZINITIALIZECONTEXTFROMSID     = 'Preemptive'
            PREEMPTIVE_OS_AUTHZINITIALIZERESOURCEMANAGER    = 'Preemptive'
            PREEMPTIVE_OS_BACKUPREAD                        = 'Preemptive'
            PREEMPTIVE_OS_CLOSEHANDLE                       = 'Preemptive'
            PREEMPTIVE_OS_CLUSTEROPS                        = 'Preemptive'
            PREEMPTIVE_OS_COMOPS                            = 'Preemptive'
            PREEMPTIVE_OS_COMPLETEAUTHTOKEN                 = 'Preemptive'
            PREEMPTIVE_OS_COPYFILE                          = 'Preemptive'
            PREEMPTIVE_OS_CREATEDIRECTORY                   = 'Preemptive'
            PREEMPTIVE_OS_CREATEFILE                        = 'Preemptive'
            PREEMPTIVE_OS_CRYPTACQUIRECONTEXT               = 'Preemptive'
            PREEMPTIVE_OS_CRYPTIMPORTKEY                    = 'Preemptive'
            PREEMPTIVE_OS_CRYPTOPS                          = 'Preemptive'
            PREEMPTIVE_OS_DECRYPTMESSAGE                    = 'Preemptive'
            PREEMPTIVE_OS_DELETEFILE                        = 'Preemptive'
            PREEMPTIVE_OS_DELETESECURITYCONTEXT             = 'Preemptive'
            PREEMPTIVE_OS_DEVICEIOCONTROL                   = 'Preemptive'
            PREEMPTIVE_OS_DEVICEOPS                         = 'Preemptive'
            PREEMPTIVE_OS_DIRSVC_NETWORKOPS                 = 'Preemptive'
            PREEMPTIVE_OS_DISCONNECTNAMEDPIPE               = 'Preemptive'
            PREEMPTIVE_OS_DOMAINSERVICESOPS                 = 'Preemptive'
            PREEMPTIVE_OS_DSGETDCNAME                       = 'Preemptive'
            PREEMPTIVE_OS_DTCOPS                            = 'Preemptive'
            PREEMPTIVE_OS_ENCRYPTMESSAGE                    = 'Preemptive'
            PREEMPTIVE_OS_FILEOPS                           = 'Preemptive'
            PREEMPTIVE_OS_FINDFILE                          = 'Preemptive'
            PREEMPTIVE_OS_FLUSHFILEBUFFERS                  = 'Preemptive'
            PREEMPTIVE_OS_FORMATMESSAGE                     = 'Preemptive'
            PREEMPTIVE_OS_FREECREDENTIALSHANDLE             = 'Preemptive'
            PREEMPTIVE_OS_FREELIBRARY                       = 'Preemptive'
            PREEMPTIVE_OS_GENERICOPS                        = 'Preemptive'
            PREEMPTIVE_OS_GETADDRINFO                       = 'Preemptive'
            PREEMPTIVE_OS_GETCOMPRESSEDFILESIZE             = 'Preemptive'
            PREEMPTIVE_OS_GETDISKFREESPACE                  = 'Preemptive'
            PREEMPTIVE_OS_GETFILEATTRIBUTES                 = 'Preemptive'
            PREEMPTIVE_OS_GETFILESIZE                       = 'Preemptive'
            PREEMPTIVE_OS_GETFINALFILEPATHBYHANDLE          = 'Preemptive'
            PREEMPTIVE_OS_GETLONGPATHNAME                   = 'Preemptive'
            PREEMPTIVE_OS_GETPROCADDRESS                    = 'Preemptive'
            PREEMPTIVE_OS_GETVOLUMENAMEFORVOLUMEMOUNTPOINT  = 'Preemptive'
            PREEMPTIVE_OS_GETVOLUMEPATHNAME                 = 'Preemptive'
            PREEMPTIVE_OS_INITIALIZESECURITYCONTEXT         = 'Preemptive'
            PREEMPTIVE_OS_LIBRARYOPS                        = 'Preemptive'
            PREEMPTIVE_OS_LOADLIBRARY                       = 'Preemptive'
            PREEMPTIVE_OS_LOGONUSER                         = 'Preemptive'
            PREEMPTIVE_OS_LOOKUPACCOUNTSID                  = 'Preemptive'
            PREEMPTIVE_OS_MESSAGEQUEUEOPS                   = 'Preemptive'
            PREEMPTIVE_OS_MOVEFILE                          = 'Preemptive'
            PREEMPTIVE_OS_NETGROUPGETUSERS                  = 'Preemptive'
            PREEMPTIVE_OS_NETLOCALGROUPGETMEMBERS           = 'Preemptive'
            PREEMPTIVE_OS_NETUSERGETGROUPS                  = 'Preemptive'
            PREEMPTIVE_OS_NETUSERGETLOCALGROUPS             = 'Preemptive'
            PREEMPTIVE_OS_NETUSERMODALSGET                  = 'Preemptive'
            PREEMPTIVE_OS_NETVALIDATEPASSWORDPOLICY         = 'Preemptive'
            PREEMPTIVE_OS_NETVALIDATEPASSWORDPOLICYFREE     = 'Preemptive'
            PREEMPTIVE_OS_OPENDIRECTORY                     = 'Preemptive'
            PREEMPTIVE_OS_PDH_WMI_INIT                      = 'Preemptive'
            PREEMPTIVE_OS_PIPEOPS                           = 'Preemptive'
            PREEMPTIVE_OS_PROCESSOPS                        = 'Preemptive'
            PREEMPTIVE_OS_QUERYCONTEXTATTRIBUTES            = 'Preemptive'
            PREEMPTIVE_OS_QUERYREGISTRY                     = 'Preemptive'
            PREEMPTIVE_OS_QUERYSECURITYCONTEXTTOKEN         = 'Preemptive'
            PREEMPTIVE_OS_REMOVEDIRECTORY                   = 'Preemptive'
            PREEMPTIVE_OS_REPORTEVENT                       = 'Preemptive'
            PREEMPTIVE_OS_REVERTTOSELF                      = 'Preemptive'
            PREEMPTIVE_OS_RSFXDEVICEOPS                     = 'Preemptive'
            PREEMPTIVE_OS_SECURITYOPS                       = 'Preemptive'
            PREEMPTIVE_OS_SERVICEOPS                        = 'Preemptive'
            PREEMPTIVE_OS_SETENDOFFILE                      = 'Preemptive'
            PREEMPTIVE_OS_SETFILEPOINTER                    = 'Preemptive'
            PREEMPTIVE_OS_SETFILEVALIDDATA                  = 'Preemptive'
            PREEMPTIVE_OS_SETNAMEDSECURITYINFO              = 'Preemptive'
            PREEMPTIVE_OS_SQLCLROPS                         = 'Preemptive'
            PREEMPTIVE_OS_SQMLAUNCH                         = 'Preemptive'
            PREEMPTIVE_OS_VERIFYSIGNATURE                   = 'Preemptive'
            PREEMPTIVE_OS_VERIFYTRUST                       = 'Preemptive'
            PREEMPTIVE_OS_VSSOPS                            = 'Preemptive'
            PREEMPTIVE_OS_WAITFORSINGLEOBJECT               = 'Preemptive'
            PREEMPTIVE_OS_WINSOCKOPS                        = 'Preemptive'
            PREEMPTIVE_OS_WRITEFILE                         = 'Preemptive'
            PREEMPTIVE_OS_WRITEFILEGATHER                   = 'Preemptive'
            PREEMPTIVE_OS_WSASETLASTERROR                   = 'Preemptive'
            PREEMPTIVE_REENLIST                             = 'Preemptive'
            PREEMPTIVE_RESIZELOG                            = 'Preemptive'
            PREEMPTIVE_ROLLFORWARDREDO                      = 'Preemptive'
            PREEMPTIVE_ROLLFORWARDUNDO                      = 'Preemptive'
            PREEMPTIVE_SB_STOPENDPOINT                      = 'Preemptive'
            PREEMPTIVE_SERVER_STARTUP                       = 'Preemptive'
            PREEMPTIVE_SETRMINFO                            = 'Preemptive'
            PREEMPTIVE_SHAREDMEM_GETDATA                    = 'Preemptive'
            PREEMPTIVE_SNIOPEN                              = 'Preemptive'
            PREEMPTIVE_SOSHOST                              = 'Preemptive'
            PREEMPTIVE_SOSTESTING                           = 'Preemptive'
            PREEMPTIVE_SP_SERVER_DIAGNOSTICS                = 'Preemptive'
            PREEMPTIVE_STARTRM                              = 'Preemptive'
            PREEMPTIVE_STREAMFCB_CHECKPOINT                 = 'Preemptive'
            PREEMPTIVE_STREAMFCB_RECOVER                    = 'Preemptive'
            PREEMPTIVE_STRESSDRIVER                         = 'Preemptive'
            PREEMPTIVE_TESTING                              = 'Preemptive'
            PREEMPTIVE_TRANSIMPORT                          = 'Preemptive'
            PREEMPTIVE_UNMARSHALPROPAGATIONTOKEN            = 'Preemptive'
            PREEMPTIVE_VSS_CREATESNAPSHOT                   = 'Preemptive'
            PREEMPTIVE_VSS_CREATEVOLUMESNAPSHOT             = 'Preemptive'
            PREEMPTIVE_XE_CALLBACKEXECUTE                   = 'Preemptive'
            PREEMPTIVE_XE_CX_FILE_OPEN                      = 'Preemptive'
            PREEMPTIVE_XE_CX_HTTP_CALL                      = 'Preemptive'
            PREEMPTIVE_XE_DISPATCHER                        = 'Preemptive'
            PREEMPTIVE_XE_ENGINEINIT                        = 'Preemptive'
            PREEMPTIVE_XE_GETTARGETSTATE                    = 'Preemptive'
            PREEMPTIVE_XE_SESSIONCOMMIT                     = 'Preemptive'
            PREEMPTIVE_XE_TARGETFINALIZE                    = 'Preemptive'
            PREEMPTIVE_XE_TARGETINIT                        = 'Preemptive'
            PREEMPTIVE_XE_TIMERRUN                          = 'Preemptive'
            PREEMPTIVE_XETESTING                            = 'Preemptive'
            PWAIT_HADR_ACTION_COMPLETED                     = 'Replication'
            PWAIT_HADR_CHANGE_NOTIFIER_TERMINATION_SYNC     = 'Replication'
            PWAIT_HADR_CLUSTER_INTEGRATION                  = 'Replication'
            PWAIT_HADR_FAILOVER_COMPLETED                   = 'Replication'
            PWAIT_HADR_JOIN                                 = 'Replication'
            PWAIT_HADR_OFFLINE_COMPLETED                    = 'Replication'
            PWAIT_HADR_ONLINE_COMPLETED                     = 'Replication'
            PWAIT_HADR_POST_ONLINE_COMPLETED                = 'Replication'
            PWAIT_HADR_SERVER_READY_CONNECTIONS             = 'Replication'
            PWAIT_HADR_WORKITEM_COMPLETED                   = 'Replication'
            PWAIT_HADRSIM                                   = 'Replication'
            PWAIT_RESOURCE_SEMAPHORE_FT_PARALLEL_QUERY_SYNC = 'Full Text Search'
            QUERY_TRACEOUT                                  = 'Tracing'
            REPL_CACHE_ACCESS                               = 'Replication'
            REPL_HISTORYCACHE_ACCESS                        = 'Replication'
            REPL_SCHEMA_ACCESS                              = 'Replication'
            REPL_TRANFSINFO_ACCESS                          = 'Replication'
            REPL_TRANHASHTABLE_ACCESS                       = 'Replication'
            REPL_TRANTEXTINFO_ACCESS                        = 'Replication'
            REPLICA_WRITES                                  = 'Replication'
            REQUEST_FOR_DEADLOCK_SEARCH                     = 'Idle'
            RESERVED_MEMORY_ALLOCATION_EXT                  = 'Memory'
            RESOURCE_SEMAPHORE                              = 'Memory'
            RESOURCE_SEMAPHORE_QUERY_COMPILE                = 'Compilation'
            SLEEP_BPOOL_FLUSH                               = 'Idle'
            SLEEP_BUFFERPOOL_HELPLW                         = 'Idle'
            SLEEP_DBSTARTUP                                 = 'Idle'
            SLEEP_DCOMSTARTUP                               = 'Idle'
            SLEEP_MASTERDBREADY                             = 'Idle'
            SLEEP_MASTERMDREADY                             = 'Idle'
            SLEEP_MASTERUPGRADED                            = 'Idle'
            SLEEP_MEMORYPOOL_ALLOCATEPAGES                  = 'Idle'
            SLEEP_MSDBSTARTUP                               = 'Idle'
            SLEEP_RETRY_VIRTUALALLOC                        = 'Idle'
            SLEEP_SYSTEMTASK                                = 'Idle'
            SLEEP_TASK                                      = 'Idle'
            SLEEP_TEMPDBSTARTUP                             = 'Idle'
            SLEEP_WORKSPACE_ALLOCATEPAGE                    = 'Idle'
            SOS_SCHEDULER_YIELD                             = 'CPU'
            SQLCLR_APPDOMAIN                                = 'SQL CLR'
            SQLCLR_ASSEMBLY                                 = 'SQL CLR'
            SQLCLR_DEADLOCK_DETECTION                       = 'SQL CLR'
            SQLCLR_QUANTUM_PUNISHMENT                       = 'SQL CLR'
            SQLTRACE_BUFFER_FLUSH                           = 'Idle'
            SQLTRACE_FILE_BUFFER                            = 'Tracing'
            SQLTRACE_FILE_READ_IO_COMPLETION                = 'Tracing'
            SQLTRACE_FILE_WRITE_IO_COMPLETION               = 'Tracing'
            SQLTRACE_INCREMENTAL_FLUSH_SLEEP                = 'Idle'
            SQLTRACE_PENDING_BUFFER_WRITERS                 = 'Tracing'
            SQLTRACE_SHUTDOWN                               = 'Tracing'
            SQLTRACE_WAIT_ENTRIES                           = 'Idle'
            THREADPOOL                                      = 'Worker Thread'
            TRACE_EVTNOTIF                                  = 'Tracing'
            TRACEWRITE                                      = 'Tracing'
            TRAN_MARKLATCH_DT                               = 'Transaction'
            TRAN_MARKLATCH_EX                               = 'Transaction'
            TRAN_MARKLATCH_KP                               = 'Transaction'
            TRAN_MARKLATCH_NL                               = 'Transaction'
            TRAN_MARKLATCH_SH                               = 'Transaction'
            TRAN_MARKLATCH_UP                               = 'Transaction'
            TRANSACTION_MUTEX                               = 'Transaction'
            WAIT_FOR_RESULTS                                = 'User Wait'
            WAITFOR                                         = 'User Wait'
            WRITE_COMPLETION                                = 'Other Disk IO'
            WRITELOG                                        = 'Tran Log IO'
            XACT_OWN_TRANSACTION                            = 'Transaction'
            XACT_RECLAIM_SESSION                            = 'Transaction'
            XACTLOCKINFO                                    = 'Transaction'
            XACTWORKSPACE_MUTEX                             = 'Transaction'
            XE_DISPATCHER_WAIT                              = 'Idle'
            XE_TIMER_EVENT                                  = 'Idle'
            ABR                                             = 'Other'
            ASSEMBLY_LOAD                                   = 'SQLCLR'
            ASYNC_DISKPOOL_LOCK                             = 'Buffer I/O'
            BACKUP                                          = 'Backup'
            BACKUP_CLIENTLOCK                               = 'Backup'
            BACKUP_OPERATOR                                 = 'Backup'
            BACKUPBUFFER                                    = 'Backup'
            BACKUPTHREAD                                    = 'Backup'
            BAD_PAGE_PROCESS                                = 'Other'
            BUILTIN_HASHKEY_MUTEX                           = 'Other'
            CHECK_PRINT_RECORD                              = 'Other'
            CPU                                             = 'CPU'
            CURSOR                                          = 'Other'
            CURSOR_ASYNC                                    = 'Other'
            DAC_INIT                                        = 'Other'
            DBCC_COLUMN_TRANSLATION_CACHE                   = 'Other'
            DBTABLE                                         = 'Other'
            DEADLOCK_ENUM_MUTEX                             = 'Latch'
            DEADLOCK_TASK_SEARCH                            = 'Other'
            DEBUG                                           = 'Other'
            DISABLE_VERSIONING                              = 'Other'
            DISKIO_SUSPEND                                  = 'Backup'
            DLL_LOADING_MUTEX                               = 'Other'
            DROPTEMP                                        = 'Other'
            DUMP_LOG_COORDINATOR                            = 'Other'
            DUMP_LOG_COORDINATOR_QUEUE                      = 'Other'
            DUMPTRIGGER                                     = 'Other'
            EC                                              = 'Other'
            EE_SPECPROC_MAP_INIT                            = 'Other'
            ENABLE_VERSIONING                               = 'Other'
            ERROR_REPORTING_MANAGER                         = 'Other'
            EXECSYNC                                        = 'Parallelism'
            EXECUTION_PIPE_EVENT_INTERNAL                   = 'Other'
            FAILPOINT                                       = 'Other'
            FS_GARBAGE_COLLECTOR_SHUTDOWN                   = 'SQLCLR'
            FSAGENT                                         = 'Idle'
            FT_RESUME_CRAWL                                 = 'Other'
            GUARDIAN                                        = 'Other'
            HTTP_ENDPOINT_COLLCREATE                        = 'Other'
            HTTP_ENUMERATION                                = 'Other'
            HTTP_START                                      = 'Other'
            IMP_IMPORT_MUTEX                                = 'Other'
            IMPPROV_IOWAIT                                  = 'Other'
            INDEX_USAGE_STATS_MUTEX                         = 'Latch'
            INTERNAL_TESTING                                = 'Other'
            IO_AUDIT_MUTEX                                  = 'Other'
            KSOURCE_WAKEUP                                  = 'Idle'
            KTM_ENLISTMENT                                  = 'Other'
            KTM_RECOVERY_MANAGER                            = 'Other'
            KTM_RECOVERY_RESOLUTION                         = 'Other'
            LOWFAIL_MEMMGR_QUEUE                            = 'Memory'
            MIRROR_SEND_MESSAGE                             = 'Other'
            MISCELLANEOUS                                   = 'Other'
            MSQL_DQ                                         = 'Network I/O'
            MSQL_SYNC_PIPE                                  = 'Other'
            MSQL_XP                                         = 'Other'
            OLEDB                                           = 'Network I/O'
            PARALLEL_BACKUP_QUEUE                           = 'Other'
            PRINT_ROLLBACK_PROGRESS                         = 'Other'
            QNMANAGER_ACQUIRE                               = 'Other'
            QPJOB_KILL                                      = 'Other'
            QPJOB_WAITFOR_ABORT                             = 'Other'
            QRY_MEM_GRANT_INFO_MUTEX                        = 'Other'
            QUERY_ERRHDL_SERVICE_DONE                       = 'Other'
            QUERY_EXECUTION_INDEX_SORT_EVENT_OPEN           = 'Other'
            QUERY_NOTIFICATION_MGR_MUTEX                    = 'Other'
            QUERY_NOTIFICATION_SUBSCRIPTION_MUTEX           = 'Other'
            QUERY_NOTIFICATION_TABLE_MGR_MUTEX              = 'Other'
            QUERY_NOTIFICATION_UNITTEST_MUTEX               = 'Other'
            QUERY_OPTIMIZER_PRINT_MUTEX                     = 'Other'
            QUERY_REMOTE_BRICKS_DONE                        = 'Other'
            RECOVER_CHANGEDB                                = 'Other'
            REQUEST_DISPENSER_PAUSE                         = 'Other'
            RESOURCE_QUEUE                                  = 'Idle'
            RESOURCE_SEMAPHORE_MUTEX                        = 'Compilation'
            RESOURCE_SEMAPHORE_SMALL_QUERY                  = 'Compilation'
            SEC_DROP_TEMP_KEY                               = 'Other'
            SEQUENTIAL_GUID                                 = 'Other'
            SERVER_IDLE_CHECK                               = 'Idle'
            SHUTDOWN                                        = 'Other'
            SNI_CRITICAL_SECTION                            = 'Other'
            SNI_HTTP_ACCEPT                                 = 'Idle'
            SNI_HTTP_WAITFOR_0_DISCON                       = 'Other'
            SNI_LISTENER_ACCESS                             = 'Other'
            SNI_TASK_COMPLETION                             = 'Other'
            SOAP_READ                                       = 'Full Text Search'
            SOAP_WRITE                                      = 'Full Text Search'
            SOS_CALLBACK_REMOVAL                            = 'Other'
            SOS_DISPATCHER_MUTEX                            = 'Other'
            SOS_LOCALALLOCATORLIST                          = 'Other'
            SOS_OBJECT_STORE_DESTROY_MUTEX                  = 'Other'
            SOS_PROCESS_AFFINITY_MUTEX                      = 'Other'
            SOS_RESERVEDMEMBLOCKLIST                        = 'Memory'
            SOS_STACKSTORE_INIT_MUTEX                       = 'Other'
            SOS_SYNC_TASK_ENQUEUE_EVENT                     = 'Other'
            SOS_VIRTUALMEMORY_LOW                           = 'Memory'
            SOSHOST_EVENT                                   = 'Other'
            SOSHOST_INTERNAL                                = 'Other'
            SOSHOST_MUTEX                                   = 'Other'
            SOSHOST_RWLOCK                                  = 'Other'
            SOSHOST_SEMAPHORE                               = 'Other'
            SOSHOST_SLEEP                                   = 'Other'
            SOSHOST_TRACELOCK                               = 'Other'
            SOSHOST_WAITFORDONE                             = 'Other'
            SQLSORT_NORMMUTEX                               = 'Other'
            SQLSORT_SORTMUTEX                               = 'Other'
            SQLTRACE_LOCK                                   = 'Other'
            SRVPROC_SHUTDOWN                                = 'Other'
            TEMPOBJ                                         = 'Other'
            TIMEPRIV_TIMEPERIOD                             = 'Other'
            UTIL_PAGE_ALLOC                                 = 'Memory'
            VIA_ACCEPT                                      = 'Other'
            VIEW_DEFINITION_MUTEX                           = 'Latch'
            WAITFOR_TASKSHUTDOWN                            = 'Idle'
            WAITSTAT_MUTEX                                  = 'Other'
            WCC                                             = 'Other'
            WORKTBL_DROP                                    = 'Other'
            XE_BUFFERMGR_ALLPROCECESSED_EVENT               = 'Other'
            XE_BUFFERMGR_FREEBUF_EVENT                      = 'Other'
            XE_DISPATCHER_JOIN                              = 'Other'
            XE_MODULEMGR_SYNC                               = 'Other'
            XE_OLS_LOCK                                     = 'Other'
            XE_SERVICES_MUTEX                               = 'Other'
            XE_SESSION_CREATE_SYNC                          = 'Other'
            XE_SESSION_SYNC                                 = 'Other'
            XE_STM_CREATE                                   = 'Other'
            XE_TIMER_MUTEX                                  = 'Other'
            XE_TIMER_TASK_DONE                              = 'Other'
        }

        $ignorable = 'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
        'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
        'CHKPT', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE', 'CXCONSUMER',
        'DBMIRROR_DBM_EVENT', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRROR_WORKER_QUEUE',
        'DBMIRRORING_CMD', 'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE',
        'EXECSYNC', 'FSAGENT', 'FT_IFTS_SCHEDULER_IDLE_WAIT', 'FT_IFTSHC_MUTEX',
        'HADR_CLUSAPI_CALL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'HADR_LOGCAPTURE_WAIT',
        'HADR_NOTIFICATION_DEQUEUE', 'HADR_TIMER_TASK', 'HADR_WORK_QUEUE',
        'KSOURCE_WAKEUP', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
        'MEMORY_ALLOCATION_EXT', 'ONDEMAND_TASK_QUEUE',
        'PARALLEL_REDO_DRAIN_WORKER', 'PARALLEL_REDO_LOG_CACHE', 'PARALLEL_REDO_TRAN_LIST', 'PARALLEL_REDO_WORKER_SYNC',
        'PREEMPTIVE_SP_SERVER_DIAGNOSTICS',
        'PARALLEL_REDO_WORKER_WAIT_WORK', 'PREEMPTIVE_HADR_LEASE_MECHANISM',
        'PREEMPTIVE_OS_LIBRARYOPS', 'PREEMPTIVE_OS_COMOPS', 'PREEMPTIVE_OS_CRYPTOPS',
        'PREEMPTIVE_OS_PIPEOPS', 'PREEMPTIVE_OS_AUTHENTICATIONOPS',
        'PREEMPTIVE_OS_GENERICOPS', 'PREEMPTIVE_OS_VERIFYTRUST',
        'PREEMPTIVE_OS_FILEOPS', 'PREEMPTIVE_OS_DEVICEOPS', 'PREEMPTIVE_OS_QUERYREGISTRY',
        'PREEMPTIVE_OS_WRITEFILE', 'PREEMPTIVE_XE_CALLBACKEXECUTE', 'PREEMPTIVE_XE_DISPATCHER',
        'PREEMPTIVE_XE_GETTARGETSTATE', 'PREEMPTIVE_XE_SESSIONCOMMIT',
        'PREEMPTIVE_XE_TARGETINIT', 'PREEMPTIVE_XE_TARGETFINALIZE',
        'PWAIT_ALL_COMPONENTS_INITIALIZED', 'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
        'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'QDS_ASYNC_QUEUE',
        'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'REDO_THREAD_PENDING_WORK',
        'QDS_SHUTDOWN_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH',
        'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK', 'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP',
        'SLEEP_DCOMSTARTUP', 'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY',
        'SLEEP_MASTERUPGRADED', 'SLEEP_MSDBSTARTUP', 'SLEEP_SYSTEMTASK', 'SLEEP_TASK',
        'SLEEP_TEMPDBSTARTUP', 'SNI_HTTP_ACCEPT', 'SP_SERVER_DIAGNOSTICS_SLEEP',
        'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'SQLTRACE_WAIT_ENTRIES',
        'WAIT_FOR_RESULTS', 'WAITFOR', 'WAITFOR_TASKSHUTDOWN', 'WAIT_XTP_HOST_WAIT',
        'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'WAIT_XTP_CKPT_CLOSE', 'WAIT_XTP_RECOVERY',
        'XE_BUFFERMGR_ALLPROCESSED_EVENT', 'XE_DISPATCHER_JOIN',
        'XE_DISPATCHER_WAIT', 'XE_LIVE_TARGET_TVF', 'XE_TIMER_EVENT'

        if ($IncludeIgnorable) {
            $sql = "WITH [Waits] AS
                (SELECT
                    [wait_type],
                    [wait_time_ms] / 1000.0 AS [WaitS],
                    ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
                    [signal_wait_time_ms] / 1000.0 AS [SignalS],
                    [waiting_tasks_count] AS [WaitCount],
                    Case WHEN SUM ([wait_time_ms]) OVER() = 0 THEN NULL ELSE 100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() END AS [Percentage],
                    ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
                FROM sys.dm_os_wait_stats
                WHERE [waiting_tasks_count] > 0
                )
                SELECT
                    MAX ([W1].[wait_type]) AS [WaitType],
                    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [WaitSeconds],
                    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [ResourceSeconds],
                    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [SignalSeconds],
                    MAX ([W1].[WaitCount]) AS [WaitCount],
                    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
                    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWaitSeconds],
                    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgResSeconds],
                    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSigSeconds],
                    CAST ('https://www.sqlskills.com/help/waits/' + MAX ([W1].[wait_type]) as XML) AS [URL]
                FROM [Waits] AS [W1]
                INNER JOIN [Waits] AS [W2]
                    ON [W2].[RowNum] <= [W1].[RowNum]
                GROUP BY [W1].[RowNum] HAVING SUM ([W2].[Percentage]) - MAX([W1].[Percentage]) < $Threshold"
        } else {
            $IgnorableList = "'$($ignorable -join "','")'"
            $sql = "WITH [Waits] AS
                (SELECT
                    [wait_type],
                    [wait_time_ms] / 1000.0 AS [WaitS],
                    ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
                    [signal_wait_time_ms] / 1000.0 AS [SignalS],
                    [waiting_tasks_count] AS [WaitCount],
                    Case WHEN SUM ([wait_time_ms]) OVER() = 0 THEN NULL ELSE 100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() END AS [Percentage],
                    ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
                FROM sys.dm_os_wait_stats
                WHERE [waiting_tasks_count] > 0
                AND Cast([wait_type] as VARCHAR(60)) NOT IN ($IgnorableList)
                )
                SELECT
                    MAX ([W1].[wait_type]) AS [WaitType],
                    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [WaitSeconds],
                    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [ResourceSeconds],
                    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [SignalSeconds],
                    MAX ([W1].[WaitCount]) AS [WaitCount],
                    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
                    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWaitSeconds],
                    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgResSeconds],
                    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSigSeconds],
                    CAST ('https://www.sqlskills.com/help/waits/' + MAX ([W1].[wait_type]) as XML) AS [URL]
                FROM [Waits] AS [W1]
                INNER JOIN [Waits] AS [W2]
                    ON [W2].[RowNum] <= [W1].[RowNum]
                GROUP BY [W1].[RowNum] HAVING SUM ([W2].[Percentage]) - MAX([W1].[Percentage]) < $Threshold"

        }
        Write-Message -Level Debug -Message $sql
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($IncludeIgnorable) {
                $excludeColumns = 'Notes'
            } else {
                $excludeColumns = 'Notes', 'Ignorable'
            }

            foreach ($row in $server.Query($sql)) {
                $waitType = $row.WaitType
                if (-not $IncludeIgnorable) {
                    if ($ignorable -contains $waitType) { continue }
                }

                [PSCustomObject]@{
                    ComputerName           = $server.ComputerName
                    InstanceName           = $server.ServiceName
                    SqlInstance            = $server.DomainInstanceName
                    WaitType               = $waitType
                    Category               = ($category).$waitType
                    WaitSeconds            = $row.WaitSeconds
                    ResourceSeconds        = $row.ResourceSeconds
                    SignalSeconds          = $row.SignalSeconds
                    WaitCount              = $row.WaitCount
                    Percentage             = $row.Percentage
                    AverageWaitSeconds     = $row.AvgWaitSeconds
                    AverageResourceSeconds = $row.AvgResSeconds
                    AverageSignalSeconds   = $row.AvgSigSeconds
                    Ignorable              = ($ignorable -contains $waitType)
                    URL                    = $row.URL
                    Notes                  = ($details).$waitType
                } | Select-DefaultView -ExcludeProperty $excludeColumns
            }
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUrcNuVjZ5tEN4DX3HtbH6+aTx
# vUOgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFIPUaAbBzYdmpmX4rCucevIah+JmMA0G
# CSqGSIb3DQEBAQUABIIBAAroHrdhzAC20f/83JBr1j1ChG7/ZKOUB+GZTCo41ipQ
# 9AjX0cIeVXe/7/dTN0yHrCBmSKohV0ObrYnfl1YgXnwA3uBCcRoV0jevJdm4hpko
# Nd5H1vlcIl/7KeWUwmbUvHQUNFBFfGUVzK9/akWZ5i0YjlPT7AmnUXtKsFgbKBEx
# z0LEgJlSt2voQBQUYH+7TrGUkCbxIIJWL/lOD8Q8i7VfPfqy5Y0jvYOy6CbH7LpL
# ikVkx5k9oMRbP60sSw0z9l4sxqSrV8qcXRmf/CV2lvaqodNY3NadPOkIkBpUYrsf
# /CimIhe6bgh1YY5z90XpCAtFZwq3/Ie9/dt+gWNXKzWhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzQ5WjAvBgkqhkiG9w0BCQQxIgQgppR7H+0IJiVuIdkjAXzj
# /0iurfgsKSztIwae66LzZAUwDQYJKoZIhvcNAQEBBQAEggIAm6avyo0ecZjbgeWq
# NEse7d3ZL9q/WkL1dCAylQD5EvBCE366UT5QQJII1De9c6VlwqWkYKry7CfOdvqq
# aWGqDTVNbtg7jDvbaVAUMPjVV6k4JJQWOPXwC8a+RzoTx8K4HXZKb4raUK+7ngjA
# pBf6COZl7lxx8uVVqnZrXn5NFMz3n1Xbs3nb4NKjtqFtNXiR/RD+jqUBdI3KnI2i
# /vpKkM0jSCeKe7+dFlBCUAhugfU+LAIFJPGybhW81npQBSiloL/vIr0cMbBk4bfR
# zT8qq+RgxiXk/DMc5onUD9NAvatSeZm3Czafs9W1W+lqXqNTPckp+PJiWVHXG7or
# WvCM/LZKdxoaHD3QGWE29U3Dm3J57KeG3fEOE/O/fZRnVL+d/i/6LoN5P8k5PiXv
# UpBoO4HApy4ztHgGPqL/5HCJqlZEVo6m0n7Uz8pcqA7fdqusS79zYSgqWlZHAJtZ
# DzRav5Q/fq0pYRjyBkqSbjbASjZkigEqgwFKt+iAmtEexRZwLy/PmRwZ7DIQi3Kk
# ybZCnIur+9UPn9mpAcSaab3MIQE1GHX+fSds1OvSDWUEQstAD4x0JCjA0XpK68Zr
# g57GxNIqpdEvLOO1AqaBFFtGcVyQTDCQWoWxRLT33a+jr0SvgXfYjMcMgpPy2ACN
# nWNagcdeeEs9FepMKuG2n9IboKo=
# SIG # End signature block
