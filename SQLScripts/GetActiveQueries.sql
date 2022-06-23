select 
    r.session_id,
    r.status,
    r.command,
    r.cpu_time,
    r.total_elapsed_time,
    t.text
from sys.dm_exec_requests as r
    cross apply sys.dm_exec_sql_text(r.sql_handle) as t