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
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQULcJZDr//GZnHid2S59ZmAmXu
# HXCgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFGgKpI2OzuWVQuAUrwkdxrGiXLTPMA0G
# CSqGSIb3DQEBAQUABIIBAIHtIhi9mOyfl4rGeoTgGBpWfUggGSUTrmwMafGaqxTG
# u4Amer6duze7/MrSUtqaUWoG9oiL87su7wVOl+FBxL8XUEg6VPaePEoBwYKK26i+
# auCJCu2qYaVYiqzoCIhgubXXWIusDDpR03CpI8pJMAKCyK34ihJx9uN4jmkkFjk+
# Zc+Vq9EG5/iKyhS2gm1i5qYQ5D5mBl8Sg1/pMqkAKrQSITslOiBNHctx04R5Coi9
# 15u0B5JclHFYlbEbgQ4pT7gRvxDLWRIAxiyL+s5u2OWovHrbYDQ0TZrGGkppM9Id
# V/BLgYzd3hrLNsMjp0Sgs6P2VAjyb1GVonyR/iHnp0ShggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxMzM3WjAvBgkqhkiG9w0BCQQxIgQgbWW6A5eh8xpsMJ5FEhBr
# 2SmOlsz27xI2OSkeK4TIUFswDQYJKoZIhvcNAQEBBQAEggIAILAEPFFtc7okFJ3Y
# 26ALCzATYBaY2Y6cvz4Li6k4TqREcpBAaTB53rRG/YKxeU4djDpzre6oniTfUzH/
# 6fZHiq4kaEFcabRSu/Ya6Fal5rR988j+vnli+FoDWCOms/GBg6d1UwRfR/h6+RpD
# rJ+IAbAJn4V4cJ4Xz+38Hyqj1efQ7HTDL1KyWGE4r5CcBWaMv5VsOawaRNxAnLvY
# UNTQJ1anOPIaZVl56k0GBlA8l0dkWxbuM3B7PHkutVoEEX1MZB0SoRc3BHf3VW8w
# EggX9Jm6+/IQJe3tn1+UF1QMkCIcrWJku8WIdE80NX/KmgJTE8IqSY47KPzr/3CQ
# UAxyc/gScqXkKCAWRCSnjhnI5UABD5wfZoumE6KkP8fWyCakhSM851qhrDBAb5rZ
# 6PbT5rmAitTaTgc3uO5FHoU25dMfQH7LcxAs9kCYDgTeAaduA95Kx6f8VjBtm3Ex
# AeN2jFVTaUFRq9usqdXX7kemdgogLA/Tz1iW+imDXSto9Vqw1O2yWduYOvNz5lEo
# IhhjyhxuaLgjwJvH+UojuV4kTyFf3TR3kGMP0bPaUP0ZvhnM5Tu5e+hUnLBwzu3b
# nezUcwTGwpN2ffA4fmhHmqfhrGSOjpE/5Aplny7SGhZ5ube2iZTsIAXPbUczI9Ac
# sNdnzazknc8vs/p/Rf7KaczRBIQ=
# SIG # End signature block
