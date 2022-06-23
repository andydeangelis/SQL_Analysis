SELECT
    o.*,
    s.name as schema_name,
    ISNULL(po.name, ps.name) AS object_owner,
    ISNULL(po.type_desc, ps.type_desc) as owner_type
FROM sys.all_objects o
INNER JOIN sys.schemas s on o.schema_id = s.schema_id
LEFT OUTER JOIN sys.database_principals po ON o.principal_id = po.principal_id
LEFT OUTER JOIN sys.database_principals ps ON s.principal_id = ps.principal_ID