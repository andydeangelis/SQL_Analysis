SELECT d.name AS 'Database Name', t.*
FROM sys.change_tracking_databases t
INNER JOIN sys.databases d ON d.database_id = t.database_id