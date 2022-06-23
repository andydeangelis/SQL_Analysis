SELECT
 ISNULL(db_name(s.database_id),db_name()) AS DBName
 ,OBJECT_SCHEMA_NAME(i.object_id,DB_ID()) AS SchemaName
 ,o.name AS [Object_Name]
 ,i.name AS Index_name
 ,i.Type_Desc AS Type_Desc
 ,ds.name AS DataSpaceName
 ,ds.type_desc AS DataSpaceTypeDesc
 ,s.user_seeks
 ,s.user_scans
 ,s.user_lookups
 ,s.user_updates
 ,s.last_user_seek
 ,s.last_user_update
FROM sys.objects AS o
JOIN sys.indexes AS i ON o.object_id = i.object_id
JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
LEFT OUTER JOIN sys.dm_db_index_usage_stats AS s ON i.object_id = s.object_id AND i.index_id = s.index_id AND s.database_id = DB_ID()
WHERE o.type = 'u'
AND i.type IN (1, 2)
AND o.object_id in
(
 SELECT a.object_id from
 (SELECT ob.object_id, ds.type_desc from sys.objects ob 
 JOIN sys.indexes ind on ind.object_id = ob.object_id 
 JOIN sys.data_spaces ds on ds.data_space_id = ind.data_space_id
 GROUP BY ob.object_id, ds.type_desc ) a 
 GROUP BY a.object_id 
 HAVING COUNT (*) > 1
 )
ORDER BY [Object_Name] DESC;
GO