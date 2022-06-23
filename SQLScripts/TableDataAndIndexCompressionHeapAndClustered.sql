-- Data (table) compression (heap or clustered index)
SELECT [t].[name] AS [Table], 
       [i].[name] AS [Index],
       [p].[partition_number] AS [Partition],
       [p].[data_compression_desc] AS [Compression]
FROM [sys].[partitions] AS [p]
INNER JOIN sys.tables AS [t] 
     ON [t].[object_id] = [p].[object_id]
INNER JOIN sys.indexes AS [i] 
     ON [i].[object_id] = [p].[object_id]
WHERE [p].[index_id] in (0,1)