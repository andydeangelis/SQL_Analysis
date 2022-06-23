function Get-DbaHelpIndex {
    <#
    .SYNOPSIS
        Returns size, row and configuration information for indexes in databases.

    .DESCRIPTION
        This function will return detailed information on indexes (and optionally statistics) for all indexes in a database, or a given index should one be passed along.
        As this uses SQL Server DMVs to access the data it will only work in 2005 and up (sorry folks still running SQL Server 2000).
        For performance reasons certain statistics information will not be returned from SQL Server 2005 if an ObjectName is not provided.

        The data includes:
        - ObjectName: the table containing the index
        - IndexType: clustered/non-clustered/columnstore and whether the index is unique/primary key
        - KeyColumns: the key columns of the index
        - IncludeColumns: any include columns in the index
        - FilterDefinition: any filter that may have been used in the index
        - DataCompression: row/page/none depending upon whether or not compression has been used
        - IndexReads: the number of reads of the index since last restart or index rebuild
        - IndexUpdates: the number of writes to the index since last restart or index rebuild
        - SizeKB: the size the index in KB
        - IndexRows: the number of the rows in the index (note filtered indexes will have fewer rows than exist in the table)
        - IndexLookups: the number of lookups that have been performed (only applicable for the heap or clustered index)
        - MostRecentlyUsed: when the index was most recently queried (default to 1900 for when never read)
        - StatsSampleRows: the number of rows queried when the statistics were built/rebuilt (not included in SQL Server 2005 unless ObjectName is specified)
        - StatsRowMods: the number of changes to the statistics since the last rebuild
        - HistogramSteps: the number of steps in the statistics histogram (not included in SQL Server 2005 unless ObjectName is specified)
        - StatsLastUpdated: when the statistics were last rebuilt (not included in SQL Server 2005 unless ObjectName is specified)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER ObjectName
        The name of a table for which you want to obtain the index information. If the two part naming convention for an object is not used it will use the default schema for the executing user. If not passed it will return data on all indexes in a given database.

    .PARAMETER IncludeStats
        If this switch is enabled, statistics as well as indexes will be returned in the output (statistics information such as the StatsRowMods will always be returned for indexes).

    .PARAMETER IncludeDataTypes
        If this switch is enabled, the output will include the data type of each column that makes up a part of the index definition (key and include columns).

    .PARAMETER IncludeFragmentation
        If this switch is enabled, the output will include fragmentation information.

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase

    .PARAMETER Raw
        If this switch is enabled, results may be less user-readable but more suitable for processing by other code.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Index
        Author: Nic Cain, https://sirsql.net/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaHelpIndex

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB

        Returns information on all indexes on the MyDB database on the localhost.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB,MyDB2

        Returns information on all indexes on the MyDB & MyDB2 databases.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1

        Returns index information on the object dbo.Table1 in the database MyDB.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -IncludeStats

        Returns information on the indexes and statistics for the table dbo.Table1 in the MyDB database.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -IncludeDataTypes

        Returns the index information for the table dbo.Table1 in the MyDB database, and includes the data types for the key and include columns.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -Raw

        Returns the index information for the table dbo.Table1 in the MyDB database, and returns the numerical data without localized separators.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -IncludeStats -Raw

        Returns the index information for all indexes in the MyDB database as well as their statistics, and formats the numerical data without localized separators.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -IncludeFragmentation

        Returns the index information for all indexes in the MyDB database as well as their fragmentation

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 -Database MyDB | Get-DbaHelpIndex

        Returns the index information for all indexes in the MyDB database

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [string]$ObjectName,
        [switch]$IncludeStats,
        [switch]$IncludeDataTypes,
        [switch]$Raw,
        [switch]$IncludeFragmentation,
        [switch]$EnableException
    )

    begin {

        #Add the table predicate to the query
        if (!$ObjectName) {
            $TablePredicate = "DECLARE @TableName NVARCHAR(256);";
        } else {
            $TablePredicate = "DECLARE @TableName NVARCHAR(256); SET @TableName = '$ObjectName';";
        }

        #Add Fragmentation info if requested
        $FragSelectColumn = ", NULL as avg_fragmentation_in_percent"
        $FragJoin = ''
        $OutputProperties = 'Database,Object,Index,IndexType,KeyColumns,IncludeColumns,FilterDefinition,DataCompression,IndexReads,IndexUpdates,SizeKB,IndexRows,IndexLookups,MostRecentlyUsed,StatsSampleRows,StatsRowMods,HistogramSteps,StatsLastUpdated'
        if ($IncludeFragmentation) {
            $FragSelectColumn = ', pstat.avg_fragmentation_in_percent'
            $FragJoin = "LEFT JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL , 'DETAILED') pstat
             ON pstat.database_id = ustat.database_id
             AND pstat.object_id = ustat.object_id
             AND pstat.index_id = ustat.index_id"
            $OutputProperties = 'Database,Object,Index,IndexType,KeyColumns,IncludeColumns,FilterDefinition,DataCompression,IndexReads,IndexUpdates,SizeKB,IndexRows,IndexLookups,MostRecentlyUsed,StatsSampleRows,StatsRowMods,HistogramSteps,StatsLastUpdated,IndexFragInPercent'
        }
        $OutputProperties = $OutputProperties.Split(',')
        #Figure out if we are including stats in the results
        if ($IncludeStats) {
            $IncludeStatsPredicate = "";
        } else {
            $IncludeStatsPredicate = "WHERE StatisticsName IS NULL";
        }

        #Data types being returns with the results?
        if ($IncludeDataTypes) {
            $IncludeDataTypesPredicate = 'DECLARE @IncludeDataTypes BIT; SET @IncludeDataTypes = 1';
        } else {
            $IncludeDataTypesPredicate = 'DECLARE @IncludeDataTypes BIT; SET @IncludeDataTypes = 0';
        }

        #region SizesQuery
        $SizesQuery = "
            SET NOCOUNT ON;
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            $TablePredicate
            $IncludeDataTypesPredicate
            ;

        DECLARE @IndexUsageStats TABLE
            (
            object_id INT ,
            index_id INT ,
            user_scans BIGINT ,
            user_seeks BIGINT ,
            user_updates BIGINT ,
            user_lookups BIGINT ,
            last_user_lookup DATETIME2(0) ,
            last_user_scan DATETIME2(0) ,
            last_user_seek DATETIME2(0) ,
            avg_fragmentation_in_percent FLOAT
            );

        DECLARE @StatsInfo TABLE
            (
            object_id INT ,
            stats_id INT ,
            stats_column_name NVARCHAR(128) ,
            stats_column_id INT ,
            stats_name NVARCHAR(128) ,
            stats_last_updated DATETIME2(0) ,
            stats_sampled_rows BIGINT ,
            rowmods BIGINT ,
            histogramsteps INT ,
            StatsRows BIGINT ,
            FullObjectName NVARCHAR(256)
            );

        INSERT  INTO @IndexUsageStats
                ( object_id ,
                index_id ,
                user_scans ,
                user_seeks ,
                user_updates ,
                user_lookups ,
                last_user_lookup ,
                last_user_scan ,
                last_user_seek ,
                avg_fragmentation_in_percent
                )
                SELECT  ustat.object_id ,
                        ustat.index_id ,
                        ustat.user_scans ,
                        ustat.user_seeks ,
                        ustat.user_updates ,
                        ustat.user_lookups ,
                        ustat.last_user_lookup ,
                        ustat.last_user_scan ,
                        ustat.last_user_seek
                        $FragSelectColumn
                FROM    sys.dm_db_index_usage_stats ustat
                $FragJoin
                WHERE   ustat.database_id = DB_ID();

        INSERT  INTO @StatsInfo
                ( object_id ,
                stats_id ,
                stats_column_name ,
                stats_column_id ,
                stats_name ,
                stats_last_updated ,
                stats_sampled_rows ,
                rowmods ,
                histogramsteps ,
                StatsRows ,
                FullObjectName
                )
                SELECT  s.object_id ,
                        s.stats_id ,
                        c.name ,
                        sc.stats_column_id ,
                        s.name ,
                        sp.last_updated ,
                        sp.rows_sampled ,
                        sp.modification_counter ,
                        sp.steps ,
                        sp.rows ,
                        QUOTENAME(sch.name) + '.' + QUOTENAME(t.name) AS FullObjectName
                FROM    [sys].[stats] AS [s]
                        INNER JOIN sys.stats_columns sc ON s.stats_id = sc.stats_id
                                                        AND s.object_id = sc.object_id
                        INNER JOIN sys.columns c ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                        INNER JOIN sys.tables t ON c.object_id = t.object_id
                        INNER JOIN sys.schemas sch ON sch.schema_id = t.schema_id
                        OUTER APPLY sys.dm_db_stats_properties([s].[object_id],
                                                            [s].[stats_id]) AS [sp]
                WHERE   s.object_id = CASE WHEN @TableName IS NULL THEN s.object_id
                                        else OBJECT_ID(@TableName)
                                    END;


        ;
        WITH    cteStatsInfo
                AS ( SELECT   object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                STUFF((SELECT   N', ' + stats_column_name
                                    FROM     @StatsInfo si2
                                    WHERE    si2.object_id = si.object_id
                                                AND si2.stats_id = si.stats_id
                                    ORDER BY si2.stats_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS StatsColumns ,
                                MAX(si.stats_sampled_rows) AS SampleRows ,
                                MAX(si.rowmods) AS RowMods ,
                                MAX(si.histogramsteps) AS HistogramSteps ,
                                MAX(si.stats_last_updated) AS StatsLastUpdated ,
                                MAX(si.StatsRows) AS StatsRows,
                                FullObjectName
                    FROM     @StatsInfo si
                    GROUP BY si.object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                si.FullObjectName
                    ),
                cteIndexSizes
                AS ( SELECT   object_id ,
                                index_id ,
                                CASE WHEN index_id < 2
                                    THEN ( ( SUM(in_row_data_page_count
                                                + lob_used_page_count
                                                + row_overflow_used_page_count)
                                            * 8192 ) / 1024 )
                                    else ( ( SUM(used_page_count) * 8192 ) / 1024 )
                                END AS SizeKB
                    FROM     sys.dm_db_partition_stats
                    GROUP BY object_id ,
                                index_id
                    ),
                cteRows
                AS ( SELECT   object_id ,
                                index_id ,
                                SUM(rows) AS IndexRows
                    FROM     sys.partitions
                    GROUP BY object_id ,
                                index_id
                    ),
                cteIndex
                AS ( SELECT   OBJECT_NAME(c.object_id) AS ObjectName ,
                                c.object_id ,
                                c.index_id ,
                                i.name COLLATE SQL_Latin1_General_CP1_CI_AS AS name ,
                                c.index_column_id ,
                                c.column_id ,
                                c.is_included_column ,
                                CASE WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 1
                                    THEN sc.name + ' DESC'
                                    WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 0 THEN sc.name
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 1
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' DESC (' + t.name + ') '
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 0
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' (' + t.name + ')'
                                    else sc.name
                                END AS ColumnName ,
                                i.filter_definition ,
                                ISNULL(dd.user_scans, 0) AS user_scans ,
                                ISNULL(dd.user_seeks, 0) AS user_seeks ,
                                ISNULL(dd.user_updates, 0) AS user_updates ,
                                ISNULL(dd.user_lookups, 0) AS user_lookups ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_lookup,
                                                            '1901-01-01')) AS LastLookup ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_scan,
                                                            '1901-01-01')) AS LastScan ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_seek,
                                                            '1901-01-01')) AS LastSeek ,
                                i.fill_factor ,
                                c.is_descending_key ,
                                p.data_compression_desc ,
                                i.type_desc ,
                                i.is_unique ,
                                i.is_unique_constraint ,
                                i.is_primary_key ,
                                ci.SizeKB ,
                                cr.IndexRows ,
                                QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                ISNULL(dd.avg_fragmentation_in_percent, 0) as avg_fragmentation_in_percent
                    FROM     sys.indexes i
                                JOIN sys.index_columns c ON i.object_id = c.object_id
                                                            AND i.index_id = c.index_id
                                JOIN sys.columns sc ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                                INNER JOIN sys.tables tbl ON c.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN sys.types t ON sc.user_type_id = t.user_type_id
                                LEFT JOIN @IndexUsageStats dd ON i.object_id = dd.object_id
                                                                AND i.index_id = dd.index_id --and dd.database_id = db_id()
                                JOIN sys.partitions p ON i.object_id = p.object_id
                                                        AND i.index_id = p.index_id
                                JOIN cteIndexSizes ci ON i.object_id = ci.object_id
                                                        AND i.index_id = ci.index_id
                                JOIN cteRows cr ON i.object_id = cr.object_id
                                                AND i.index_id = cr.index_id
                    WHERE    i.object_id = CASE WHEN @TableName IS NULL
                                                THEN i.object_id
                                                else OBJECT_ID(@TableName)
                                            END
                    ),
                cteResults
                AS ( SELECT   ci.FullObjectName ,
                                ci.object_id ,
                                MAX(index_id) AS Index_Id ,
                                ci.type_desc
                                + CASE WHEN ci.is_primary_key = 1
                                    THEN ' (PRIMARY KEY)'
                                    WHEN ci.is_unique_constraint = 1
                                    THEN ' (UNIQUE CONSTRAINT)'
                                    WHEN ci.is_unique = 1 THEN ' (UNIQUE)'
                                    else ''
                                END AS IndexType ,
                                name AS IndexName ,
                                STUFF((SELECT   N', ' + ColumnName
                                    FROM     cteIndex ci2
                                    WHERE    ci2.name = ci.name
                                                AND ci2.is_included_column = 0
                                    GROUP BY ci2.index_column_id ,
                                                ci2.ColumnName
                                    ORDER BY ci2.index_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS KeyColumns ,
                                ISNULL(STUFF((SELECT    N',  ' + ColumnName
                                            FROM      cteIndex ci3
                                            WHERE     ci3.name = ci.name
                                                        AND ci3.is_included_column = 1
                                            GROUP BY  ci3.index_column_id ,
                                                        ci3.ColumnName
                                            ORDER BY  ci3.index_column_id
                                    FOR   XML PATH(N'') ,
                                                TYPE).value(N'.[1]',
                                                            N'nvarchar(1000)'), 1, 2,
                                            N''), '') AS IncludeColumns ,
                                ISNULL(filter_definition, '') AS FilterDefinition ,
                                ci.fill_factor ,
                                CASE WHEN ci.data_compression_desc = 'NONE' THEN ''
                                    else ci.data_compression_desc
                                END AS DataCompression ,
                                MAX(ci.user_seeks) + MAX(ci.user_scans)
                                + MAX(ci.user_lookups) AS IndexReads ,
                                MAX(ci.user_lookups) AS IndexLookups ,
                                ci.user_updates AS IndexUpdates ,
                                ci.SizeKB AS SizeKB ,
                                ci.IndexRows AS IndexRows ,
                                CASE WHEN LastScan > LastSeek
                                        AND LastScan > LastLookup THEN LastScan
                                    WHEN LastSeek > LastScan
                                        AND LastSeek > LastLookup THEN LastSeek
                                    WHEN LastLookup > LastScan
                                        AND LastLookup > LastSeek THEN LastLookup
                                    else ''
                                END AS MostRecentlyUsed ,
                                AVG(ci.avg_fragmentation_in_percent) as avg_fragmentation_in_percent
                    FROM     cteIndex ci
                    GROUP BY ci.ObjectName ,
                                ci.name ,
                                ci.filter_definition ,
                                ci.object_id ,
                                ci.LastLookup ,
                                ci.LastSeek ,
                                ci.LastScan ,
                                ci.user_updates ,
                                ci.fill_factor ,
                                ci.data_compression_desc ,
                                ci.type_desc ,
                                ci.is_primary_key ,
                                ci.is_unique ,
                                ci.is_unique_constraint ,
                                ci.SizeKB ,
                                ci.IndexRows ,
                                ci.FullObjectName
                    ),
                AllResults
                AS ( SELECT   c.FullObjectName ,
                                IndexType ,
                                ISNULL(IndexName, si.stats_name) AS IndexName ,
                                NULL as StatisticsName ,
                                ISNULL(KeyColumns, si.StatsColumns) AS KeyColumns ,
                                ISNULL(IncludeColumns, '') AS IncludeColumns ,
                                FilterDefinition ,
                                fill_factor AS [FillFactor] ,
                                DataCompression ,
                                IndexReads ,
                                IndexUpdates ,
                                SizeKB ,
                                IndexRows ,
                                IndexLookups ,
                                MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                si.HistogramSteps ,
                                si.StatsLastUpdated ,
                                avg_fragmentation_in_percent AS IndexFragInPercent,
                                1 AS Ordering
                    FROM     cteResults c
                                INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                            AND si.stats_id = c.Index_Id
                    UNION
                    SELECT   QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                '' ,
                                '' ,
                                stats_name ,
                                StatsColumns ,
                                '' ,
                                '' AS FilterDefinition ,
                                '' AS Fill_Factor ,
                                '' AS DataCompression ,
                                '' AS IndexReads ,
                                '' AS IndexUpdates ,
                                '' AS SizeKB ,
                                StatsRows AS IndexRows ,
                                '' AS IndexLookups ,
                                '' AS MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                csi.HistogramSteps ,
                                csi.StatsLastUpdated ,
                                '' AS IndexFragInPercent ,
                                2
                    FROM     cteStatsInfo csi
                    INNER JOIN sys.tables tbl ON csi.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                    WHERE    stats_id NOT IN (
                                SELECT  stats_id
                                FROM    cteResults c
                                        INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                                    AND si.stats_id = c.Index_Id )
                    )
            SELECT  FullObjectName ,
                    IndexType ,
                    IndexName ,
                    StatisticsName ,
                    KeyColumns ,
                    ISNULL(IncludeColumns, '') AS IncludeColumns ,
                    FilterDefinition ,
                    [FillFactor] AS [FillFactor] ,
                    DataCompression ,
                    IndexReads ,
                    IndexUpdates ,
                    SizeKB ,
                    IndexRows ,
                    IndexLookups ,
                    MostRecentlyUsed ,
                    StatsSampleRows ,
                    StatsRowMods ,
                    HistogramSteps ,
                    StatsLastUpdated ,
                    IndexFragInPercent
            FROM    AllResults
                    $IncludeStatsPredicate
        OPTION  ( RECOMPILE );
        "
        #endRegion SizesQuery


        #region sizesQuery2005
        $SizesQuery2005 = "
        SET NOCOUNT ON;
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        $TablePredicate
        $IncludeDataTypesPredicate
        ;

        DECLARE @AllResults TABLE
            (
                RowNum INT ,
                FullObjectName	NVARCHAR(300) ,
                IndexType	NVARCHAR(256) ,
                IndexName	NVARCHAR(256) ,
                KeyColumns	NVARCHAR(2000) ,
                IncludeColumns	NVARCHAR(2000) ,
                FilterDefinition	NVARCHAR(100) ,
                [FillFactor]	TINYINT ,
                DataCompression	CHAR(4) ,
                IndexReads	BIGINT ,
                IndexUpdates	BIGINT ,
                SizeKB	BIGINT ,
                IndexRows	BIGINT ,
                IndexLookups	BIGINT ,
                MostRecentlyUsed	DATETIME ,
                StatsSampleRows	BIGINT ,
                StatsRowMods	BIGINT ,
                HistogramSteps	INT	,
                StatsLastUpdated	DATETIME ,
                object_id BIGINT ,
                index_id BIGINT
            );

        DECLARE @IndexUsageStats TABLE
            (
            object_id INT ,
            index_id INT ,
            user_scans BIGINT ,
            user_seeks BIGINT ,
            user_updates BIGINT ,
            user_lookups BIGINT ,
            last_user_lookup DATETIME ,
            last_user_scan DATETIME ,
            last_user_seek DATETIME ,
            avg_fragmentation_in_percent FLOAT
            );

        DECLARE @StatsInfo TABLE
            (
            object_id INT ,
            stats_id INT ,
            stats_column_name NVARCHAR(128) ,
            stats_column_id INT ,
            stats_name NVARCHAR(128) ,
            stats_last_updated DATETIME ,
            stats_sampled_rows BIGINT ,
            rowmods BIGINT ,
            histogramsteps INT ,
            StatsRows BIGINT ,
            FullObjectName NVARCHAR(256)
            );

        INSERT  INTO @IndexUsageStats
                ( object_id ,
                index_id ,
                user_scans ,
                user_seeks ,
                user_updates ,
                user_lookups ,
                last_user_lookup ,
                last_user_scan ,
                last_user_seek ,
                avg_fragmentation_in_percent
                )
                SELECT  ustat.object_id ,
                        ustat.index_id ,
                        ustat.user_scans ,
                        ustat.user_seeks ,
                        ustat.user_updates ,
                        ustat.user_lookups ,
                        ustat.last_user_lookup ,
                        ustat.last_user_scan ,
                        ustat.last_user_seek
                        $FragSelectColumn
                FROM    sys.dm_db_index_usage_stats ustat
                $FragJoin
                WHERE   database_id = DB_ID();


        INSERT  INTO @StatsInfo
                ( object_id ,
                stats_id ,
                stats_column_name ,
                stats_column_id ,
                stats_name ,
                stats_last_updated ,
                stats_sampled_rows ,
                rowmods ,
                histogramsteps ,
                StatsRows ,
                FullObjectName
                )
                SELECT  s.object_id ,
                        s.stats_id ,
                        c.name ,
                        sc.stats_column_id ,
                        s.name ,
                        NULL AS last_updated ,
                        NULL AS rows_sampled ,
                        NULL AS modification_counter ,
                        NULL AS steps ,
                        NULL AS rows ,
                        QUOTENAME(sch.name) + '.' + QUOTENAME(t.name) AS FullObjectName
                FROM    [sys].[stats] AS [s]
                        INNER JOIN sys.stats_columns sc ON s.stats_id = sc.stats_id
                                                        AND s.object_id = sc.object_id
                        INNER JOIN sys.columns c ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                        INNER JOIN sys.tables t ON c.object_id = t.object_id
                        INNER JOIN sys.schemas sch ON sch.schema_id = t.schema_id
                    --   OUTER APPLY sys.dm_db_stats_properties([s].[object_id],
                    --                                        [s].[stats_id]) AS [sp]
                WHERE   s.object_id = CASE WHEN @TableName IS NULL THEN s.object_id
                                        else OBJECT_ID(@TableName)
                                    END;


        ;
        WITH    cteStatsInfo
                AS ( SELECT   object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                STUFF((SELECT   N', ' + stats_column_name
                                    FROM     @StatsInfo si2
                                    WHERE    si2.object_id = si.object_id
                                                AND si2.stats_id = si.stats_id
                                    ORDER BY si2.stats_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS StatsColumns ,
                                MAX(si.stats_sampled_rows) AS SampleRows ,
                                MAX(si.rowmods) AS RowMods ,
                                MAX(si.histogramsteps) AS HistogramSteps ,
                                MAX(si.stats_last_updated) AS StatsLastUpdated ,
                                MAX(si.StatsRows) AS StatsRows,
                                FullObjectName
                    FROM     @StatsInfo si
                    GROUP BY si.object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                si.FullObjectName
                    ),
                cteIndexSizes
                AS ( SELECT   object_id ,
                                index_id ,
                                CASE WHEN index_id < 2
                                    THEN ( ( SUM(in_row_data_page_count
                                                + lob_used_page_count
                                                + row_overflow_used_page_count)
                                            * 8192 ) / 1024 )
                                    else ( ( SUM(used_page_count) * 8192 ) / 1024 )
                                END AS SizeKB
                    FROM     sys.dm_db_partition_stats
                    GROUP BY object_id ,
                                index_id
                    ),
                cteRows
                AS ( SELECT   object_id ,
                                index_id ,
                                SUM(rows) AS IndexRows
                    FROM     sys.partitions
                    GROUP BY object_id ,
                                index_id
                    ),
                cteIndex
                AS ( SELECT   OBJECT_NAME(c.object_id) AS ObjectName ,
                                c.object_id ,
                                c.index_id ,
                                i.name COLLATE SQL_Latin1_General_CP1_CI_AS AS name ,
                                c.index_column_id ,
                                c.column_id ,
                                c.is_included_column ,
                                CASE WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 1
                                    THEN sc.name + ' DESC'
                                    WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 0 THEN sc.name
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 1
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' DESC (' + t.name + ') '
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 0
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' (' + t.name + ')'
                                    else sc.name
                                END AS ColumnName ,
                                '' AS filter_definition ,
                                ISNULL(dd.user_scans, 0) AS user_scans ,
                                ISNULL(dd.user_seeks, 0) AS user_seeks ,
                                ISNULL(dd.user_updates, 0) AS user_updates ,
                                ISNULL(dd.user_lookups, 0) AS user_lookups ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_lookup,
                                                            '1901-01-01')) AS LastLookup ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_scan,
                                                            '1901-01-01')) AS LastScan ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_seek,
                                                            '1901-01-01')) AS LastSeek ,
                                i.fill_factor ,
                                c.is_descending_key ,
                                'NONE' as data_compression_desc ,
                                i.type_desc ,
                                i.is_unique ,
                                i.is_unique_constraint ,
                                i.is_primary_key ,
                                ci.SizeKB ,
                                cr.IndexRows ,
                                QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                ISNULL(dd.avg_fragmentation_in_percent, 0) as avg_fragmentation_in_percent
                    FROM     sys.indexes i
                                JOIN sys.index_columns c ON i.object_id = c.object_id
                                                            AND i.index_id = c.index_id
                                JOIN sys.columns sc ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                                INNER JOIN sys.tables tbl ON c.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN sys.types t ON sc.user_type_id = t.user_type_id
                                LEFT JOIN @IndexUsageStats dd ON i.object_id = dd.object_id
                                                                AND i.index_id = dd.index_id --and dd.database_id = db_id()
                                JOIN sys.partitions p ON i.object_id = p.object_id
                                                        AND i.index_id = p.index_id
                                JOIN cteIndexSizes ci ON i.object_id = ci.object_id
                                                        AND i.index_id = ci.index_id
                                JOIN cteRows cr ON i.object_id = cr.object_id
                                                AND i.index_id = cr.index_id
                    WHERE    i.object_id = CASE WHEN @TableName IS NULL
                                                THEN i.object_id
                                                else OBJECT_ID(@TableName)
                                            END
                    ),
                cteResults
                AS ( SELECT   ci.FullObjectName ,
                                ci.object_id ,
                                MAX(index_id) AS Index_Id ,
                                ci.type_desc
                                + CASE WHEN ci.is_primary_key = 1
                                    THEN ' (PRIMARY KEY)'
                                    WHEN ci.is_unique_constraint = 1
                                    THEN ' (UNIQUE CONSTRAINT)'
                                    WHEN ci.is_unique = 1 THEN ' (UNIQUE)'
                                    else ''
                                END AS IndexType ,
                                name AS IndexName ,
                                STUFF((SELECT   N', ' + ColumnName
                                    FROM     cteIndex ci2
                                    WHERE    ci2.name = ci.name
                                                AND ci2.is_included_column = 0
                                    GROUP BY ci2.index_column_id ,
                                                ci2.ColumnName
                                    ORDER BY ci2.index_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS KeyColumns ,
                                ISNULL(STUFF((SELECT    N',  ' + ColumnName
                                            FROM      cteIndex ci3
                                            WHERE     ci3.name = ci.name
                                                        AND ci3.is_included_column = 1
                                            GROUP BY  ci3.index_column_id ,
                                                        ci3.ColumnName
                                            ORDER BY  ci3.index_column_id
                                    FOR   XML PATH(N'') ,
                                                TYPE).value(N'.[1]',
                                                            N'nvarchar(1000)'), 1, 2,
                                            N''), '') AS IncludeColumns ,
                                ISNULL(filter_definition, '') AS FilterDefinition ,
                                ci.fill_factor ,
                                CASE WHEN ci.data_compression_desc = 'NONE' THEN ''
                                    else ci.data_compression_desc
                                END AS DataCompression ,
                                MAX(ci.user_seeks) + MAX(ci.user_scans)
                                + MAX(ci.user_lookups) AS IndexReads ,
                                MAX(ci.user_lookups) AS IndexLookups ,
                                ci.user_updates AS IndexUpdates ,
                                ci.SizeKB AS SizeKB ,
                                ci.IndexRows AS IndexRows ,
                                CASE WHEN LastScan > LastSeek
                                        AND LastScan > LastLookup THEN LastScan
                                    WHEN LastSeek > LastScan
                                        AND LastSeek > LastLookup THEN LastSeek
                                    WHEN LastLookup > LastScan
                                        AND LastLookup > LastSeek THEN LastLookup
                                    else ''
                                END AS MostRecentlyUsed ,
                                AVG(ci.avg_fragmentation_in_percent) as avg_fragmentation_in_percent
                    FROM     cteIndex ci
                    GROUP BY ci.ObjectName ,
                                ci.name ,
                                ci.filter_definition ,
                                ci.object_id ,
                                ci.LastLookup ,
                                ci.LastSeek ,
                                ci.LastScan ,
                                ci.user_updates ,
                                ci.fill_factor ,
                                ci.data_compression_desc ,
                                ci.type_desc ,
                                ci.is_primary_key ,
                                ci.is_unique ,
                                ci.is_unique_constraint ,
                                ci.SizeKB ,
                                ci.IndexRows ,
                                ci.FullObjectName
                    ), AllResults AS
                        (		 SELECT   c.FullObjectName ,
                                ISNULL(IndexType, 'STATISTICS') AS IndexType ,
                                ISNULL(IndexName, '') AS IndexName ,
                                ISNULL(KeyColumns, '') AS KeyColumns ,
                                ISNULL(IncludeColumns, '') AS IncludeColumns ,
                                FilterDefinition ,
                                fill_factor AS [FillFactor] ,
                                DataCompression ,
                                IndexReads ,
                                IndexUpdates ,
                                SizeKB ,
                                IndexRows ,
                                IndexLookups ,
                                MostRecentlyUsed ,
                                NULL AS StatsSampleRows ,
                                NULL AS StatsRowMods ,
                                NULL AS HistogramSteps ,
                                NULL AS StatsLastUpdated ,
                                avg_fragmentation_in_percent as IndexFragInPercent,
                                1 AS Ordering ,
                                c.object_id ,
                                c.Index_Id
                    FROM     cteResults c
                                INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                            AND si.stats_id = c.Index_Id
                        UNION
                    SELECT   QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                'STATISTICS' ,
                                stats_name ,
                                StatsColumns ,
                                '' ,
                                '' AS FilterDefinition ,
                                '' AS Fill_Factor ,
                                '' AS DataCompression ,
                                '' AS IndexReads ,
                                '' AS IndexUpdates ,
                                '' AS SizeKB ,
                                StatsRows AS IndexRows ,
                                '' AS IndexLookups ,
                                '' AS MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                csi.HistogramSteps ,
                                csi.StatsLastUpdated ,
                                '' as IndexFragInPercent,
                                2 ,
                                csi.object_id ,
                                csi.stats_id
                    FROM     cteStatsInfo csi
                    INNER JOIN sys.tables tbl ON csi.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN (SELECT si.object_id, si.stats_id
                                            FROM    cteResults c
                                            INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                                    AND si.stats_id = c.Index_Id ) AS x on csi.object_id = x.object_id and csi.stats_id = x.stats_id
                        WHERE x.object_id is null
                    )
            INSERT INTO @AllResults
            SELECT  row_number() OVER (ORDER BY FullObjectName) AS RowNum ,
                    FullObjectName ,
                    ISNULL(IndexType, 'STATISTICS') AS IndexType ,
                    IndexName ,
                    KeyColumns ,
                    ISNULL(IncludeColumns, '') AS IncludeColumns ,
                    FilterDefinition ,
                    [FillFactor] AS [FillFactor] ,
                    DataCompression ,
                    IndexReads ,
                    IndexUpdates ,
                    SizeKB ,
                    IndexRows ,
                    IndexLookups ,
                    MostRecentlyUsed ,
                    StatsSampleRows ,
                    StatsRowMods ,
                    HistogramSteps ,
                    StatsLastUpdated ,
                    IndexFragInPercent ,
                    object_id ,
                    index_id
            FROM    AllResults
                    $IncludeStatsPredicate
        OPTION  ( RECOMPILE );

        /* Only update the stats data on 2005 for a single table, otherwise the run time for this is a potential problem for large table/index volumes */
        if @TableName IS NOT NULL
        BEGIN

            DECLARE @StatsInfo2005 TABLE (Name nvarchar(128), Updated DATETIME, Rows BIGINT, RowsSampled BIGINT, Steps INT, Density INT, AverageKeyLength INT, StringIndex NVARCHAR(20))

            DECLARE @SqlCall NVARCHAR(2000), @RowNum INT;
            SELECT @RowNum = min(RowNum) FROM @AllResults;
            WHILE @RowNum IS NOT NULL
            BEGIN
                SELECT @SqlCall = 'dbcc show_statistics('+FullObjectName+', '+IndexName+') with stat_header' FROM @AllResults WHERE RowNum = @RowNum;
                INSERT INTO @StatsInfo2005 exec (@SqlCall);
                UPDATE @AllResults
                    SET StatsSampleRows = RowsSampled,
                    HistogramSteps = Steps,
                    StatsLastUpdated = Updated
                    FROM @StatsInfo2005
                    WHERE RowNum = @RowNum;
                DELETE FROM @StatsInfo2005
                SELECT @RowNum = min(RowNum) FROM @AllResults WHERE RowNum > @RowNum;
            END;

        END;

        UPDATE a
        SET a.StatsRowMods = i.rowmodctr
        FROM @AllResults a
            JOIN sys.sysindexes i ON a.object_id = i.id AND a.index_id = i.indid;

        SELECT	FullObjectName ,
                IndexType ,
                IndexName ,
                KeyColumns ,
                IncludeColumns ,
                FilterDefinition ,
                [FillFactor] ,
                DataCompression ,
                IndexReads ,
                IndexUpdates ,
                SizeKB ,
                IndexRows ,
                IndexLookups ,
                MostRecentlyUsed ,
                StatsSampleRows ,
                StatsRowMods ,
                HistogramSteps ,
                StatsLastUpdated ,
                IndexFragInPercent
        FROM @AllResults;"

        #endregion sizesQuery2005
    }
    process {
        Write-Message -Level Debug -Message $SizesQuery
        Write-Message -Level Debug -Message $SizesQuery2005

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            #Need to check the version of SQL
            if ($server.versionMajor -ge 10) {
                $indexesQuery = $SizesQuery
            } else {
                $indexesQuery = $SizesQuery2005
            }

            if (!$db.IsAccessible) {
                Stop-Function -Message "$db is not accessible. Skipping." -Continue
            }

            Write-Message -Level Debug -Message "$indexesQuery"
            try {
                $IndexDetails = $db.Query($indexesQuery)

                if (!$Raw) {
                    foreach ($detail in $IndexDetails) {
                        $recentlyused = [datetime]$detail.MostRecentlyUsed

                        if ($recentlyused.year -eq 1900) {
                            $recentlyused = $null
                        }

                        [pscustomobject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Database           = $db.Name
                            Object             = $detail.FullObjectName
                            Index              = $detail.IndexName
                            IndexType          = $detail.IndexType
                            Statistics         = $detail.StatisticsName
                            KeyColumns         = $detail.KeyColumns
                            IncludeColumns     = $detail.IncludeColumns
                            FilterDefinition   = $detail.FilterDefinition
                            DataCompression    = $detail.DataCompression
                            IndexReads         = "{0:N0}" -f $detail.IndexReads
                            IndexUpdates       = "{0:N0}" -f $detail.IndexUpdates
                            Size               = "{0:N0}" -f $detail.SizeKB
                            IndexRows          = "{0:N0}" -f $detail.IndexRows
                            IndexLookups       = "{0:N0}" -f $detail.IndexLookups
                            MostRecentlyUsed   = $recentlyused
                            StatsSampleRows    = "{0:N0}" -f $detail.StatsSampleRows
                            StatsRowMods       = "{0:N0}" -f $detail.StatsRowMods
                            HistogramSteps     = $detail.HistogramSteps
                            StatsLastUpdated   = $detail.StatsLastUpdated
                            IndexFragInPercent = "{0:F2}" -f $detail.IndexFragInPercent
                        }
                    }
                }

                else {
                    foreach ($detail in $IndexDetails) {
                        $recentlyused = [datetime]$detail.MostRecentlyUsed

                        if ($recentlyused.year -eq 1900) {
                            $recentlyused = $null
                        }

                        [pscustomobject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Database           = $db.Name
                            Object             = $detail.FullObjectName
                            Index              = $detail.IndexName
                            IndexType          = $detail.IndexType
                            Statistics         = $detail.StatisticsName
                            KeyColumns         = $detail.KeyColumns
                            IncludeColumns     = $detail.IncludeColumns
                            FilterDefinition   = $detail.FilterDefinition
                            DataCompression    = $detail.DataCompression
                            IndexReads         = $detail.IndexReads
                            IndexUpdates       = $detail.IndexUpdates
                            Size               = [dbasize]($detail.SizeKB * 1024)
                            IndexRows          = $detail.IndexRows
                            IndexLookups       = $detail.IndexLookups
                            MostRecentlyUsed   = $recentlyused
                            StatsSampleRows    = $detail.StatsSampleRows
                            StatsRowMods       = $detail.StatsRowMods
                            HistogramSteps     = $detail.HistogramSteps
                            StatsLastUpdated   = $detail.StatsLastUpdated
                            IndexFragInPercent = $detail.IndexFragInPercent
                        }
                    }
                }
            } catch {
                Stop-Function -Continue -ErrorRecord $_ -Message "Cannot process $db on $server"
            }
        }
    }
}
# SIG # Begin signature block
# MIIjigYJKoZIhvcNAQcCoIIjezCCI3cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDadvb+o7rmItnn
# L1B0zgPntuVF7b9S1onK0vmsoDBPkaCCHYMwggUaMIIEAqADAgECAhADBbuGIbCh
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
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCA6hKFoTXtYAmgJTyRpwLAdnzVtXXpylk/m
# 5Uen0fqFaTANBgkqhkiG9w0BAQEFAASCAQBbO+CN5weSLgv8l7GIQ75p4YIAcMg2
# FAlCqhJIGHQA0gXXyMHstZrYgwX0v/86Pzr3yt02Ahx/+zigVYBkJ2jUaffFABX0
# TprgKToPv/Glaj/9PV6FYnHtfz5/BiU6xNtjoRrLD4fjAFgIf3mzt2Gou/4qjJRd
# Kt8/aebKffsqEjMUZJeJcbzp66yLd7Zv5GZ8k0XX7WTlTBq7+BoE6s+zzPqccpfa
# ZFNdnV7sfw7c6T3JOAO60g2HHCBUffId73phjvIu2ZgQ4pJQqytrO263qiRwmhu3
# AeWzKY7WWSFO3GV7CxScuL5n1scMFtj2B69qfKO+0q5dVzAaLgi/0oRnoYIDIDCC
# AxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQCnpKiJ7JmUKQBmM4TYaX
# nTANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTIyMDYyMjA2NDMwNlowLwYJKoZIhvcNAQkEMSIEIMjEWrKh
# tlz2ftTNAmsRks12EVxMhnAEiLsjTf4ZOCRZMA0GCSqGSIb3DQEBAQUABIICAENR
# 2e52a+Bym0lTw9eRcQncCHe2LBdKnuMY3Qjk5lZNC0II2oqNSVwgTJM478a25AwO
# 06ENLGOqXGmnmiE5kStQkGxdMfWOPPfFO/FYTfNbvDzRxigBV97VM0YWersnApt/
# OpdInS73G7J36OHNlBbQJn6buARMNd5WM2OsIpSgjJwBJIRa184ozjSuVz0JSX+7
# tNb/Mkt030na3ExjYT2jJPxVLK5BlpeyLfpu9Z3pHOSt5nJCDp+QSqIU/wcbzqJV
# EtpX+lAI7C9rvQLCgMFZDKyS0MHaIqQcEg7VSkNIMDQHbXqfGn3k/h36wiRDtvnD
# CqDZiqRdNAinwr3FIiqhByMUsD/UHUnwFA8LvUzTTOU3cYscH6VlpCrX/yQmcJet
# vRbrkLrxreqaGw3wazHGrWmlNGCyoIuloaXGtpstlz1DKeQZreTrLco/VOX2OvzF
# 7NVLORQlFnzOr5LWfiAqcoEYSiCpGgY/XM6cg/Y4W02+3/lAS89iSy9du859picq
# 5H7DhAJWSmKLDPBawJLyQ68gWcGX2ZaFjk8SOEjTLPNXPHTtJfhHh8ctCJ/s1VXA
# mQIOdkKxbP9y+HRk/zlkFFMnTE7bhDBcv0sIQV9OMgPLPPGkkoQysyAtHD57LtK+
# bXCs3iExcxqbWyKigg47Hpkf3+rzGnuBRS6lrqCC
# SIG # End signature block
