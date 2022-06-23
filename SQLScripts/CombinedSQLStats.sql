USE master;
SELECT
       LEFT ([mf].[physical_name], 2) AS [Drive],
    DB_NAME ([vfs].[database_id]) AS [database_name], [mf].state_desc,
    [mf].[physical_name], [mf].name logical_name, 
       CASE rm.compatibility_level
              WHEN 65  THEN 'SQL Server 6.5'
              WHEN 70  THEN 'SQL Server 7.0'
              WHEN 80  THEN 'SQL Server 2000'
              WHEN 90  THEN 'SQL Server 2005'
              WHEN 100 THEN 'SQL Server 2008/R2'
              WHEN 110 THEN 'SQL Server 2012'
              WHEN 120 THEN 'SQL Server 2014'
              WHEN 130 THEN 'SQL Server 2016'
              WHEN 140 THEN 'SQL Server 2017'
			  WHEN 150 THEN 'SQL Server 2019'
              END AS [compatibility_level],
       CONVERT (DECIMAL (20,2) , (CONVERT(DECIMAL, size)/128)) [file_size_MB],
       fileproperty(mf.name,'SpaceUsed')/128.00 as [file_size_usedMB],
       [rm].recovery_model_desc, 
       CASE [mf].is_percent_growth
              WHEN 1 THEN 'Yes'
              ELSE 'No'
              END AS [is_percent_growth],
       CASE [mf].is_percent_growth
              WHEN 1 THEN CONVERT(VARCHAR, [mf].growth) + '%'
              WHEN 0 THEN CONVERT(VARCHAR, [mf].growth/128) + ' MB' -- Convert from byte pages to MB
              END AS [growth_in_increment_of],
       CASE [mf].is_percent_growth
              WHEN 1 THEN
              CONVERT(DECIMAL(20,2), (((CONVERT(DECIMAL, size)*growth)/100)*8)/1024) -- Convert from byte pages to MB
              WHEN 0 THEN
              CONVERT(DECIMAL(20,2), (CONVERT(DECIMAL, growth)/128)) -- Convert from byte pages to MB
              END AS [next_auto_growth_size_MB],
       CASE mf.max_size
              WHEN 0 THEN 'No growth is allowed'
              WHEN -1 THEN 'File will grow until the disk is full'
              ELSE CONVERT(VARCHAR, [mf].max_size)
              END AS [max_size],
    [AVGReadLatency_ms] =
        CASE WHEN [num_of_reads] = 0
            THEN 0 ELSE ([io_stall_read_ms] / [num_of_reads]) END,
    [AVGWriteLatency_ms] =
        CASE WHEN [num_of_writes] = 0
            THEN 0 ELSE ([io_stall_write_ms] / [num_of_writes]) END,
    [AVGTotalLatency_ms(Reads + Writes)] =
        CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
            THEN 0 ELSE ([io_stall] / ([num_of_reads] + [num_of_writes])) END,
    [AvgBytesPerRead] =
        CASE WHEN [num_of_reads] = 0
            THEN 0 ELSE ([num_of_bytes_read] / [num_of_reads]) END,
    [AvgBytesPerWrite] =
        CASE WHEN [num_of_writes] = 0
            THEN 0 ELSE ([num_of_bytes_written] / [num_of_writes]) END,
    [AvgBytesPerTransfer] =
        CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
            THEN 0 ELSE
                (([num_of_bytes_read] + [num_of_bytes_written]) /
                ([num_of_reads] + [num_of_writes])) END    
FROM
    sys.dm_io_virtual_file_stats (NULL,NULL) AS [vfs]
JOIN sys.master_files AS [mf]
    ON [vfs].[database_id] = [mf].[database_id]
    AND [vfs].[file_id] = [mf].[file_id]
JOIN sys.databases AS [rm]
       ON [vfs].[database_id] = [rm].[database_id]
ORDER BY [vfs].[database_id] ASC;