USE [DBATools]
GO
/****** Object:  StoredProcedure [DBA].[ReportDBFileInfo]    Script Date: 8/25/2025 1:18:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [DBA].[ReportDBFileInfo]
AS BEGIN

SET NOCOUNT ON 
SET XACT_ABORT ON

--------------------------------------------------------------------------------
-- 0) Hold results
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#DbFiles') IS NOT NULL DROP TABLE #DbFiles;
CREATE TABLE #DbFiles
(
    database_name   SYSNAME,
    file_id         INT,
    type_desc       NVARCHAR(60),
    logical_name    SYSNAME,
    physical_name   NVARCHAR(4000),
    state_desc      NVARCHAR(60),
    size_mb         DECIMAL(19,2),
    used_mb         DECIMAL(19,2) NULL,   -- for data files (logs populated separately)
    max_size_mb     DECIMAL(19,2) NULL,   -- NULL = unlimited
    growth_desc     NVARCHAR(50),
    is_percent_growth BIT,
    growth_mb       DECIMAL(19,2) NULL,
    filegroup_name  SYSNAME NULL
);

IF OBJECT_ID('tempdb..#DbLogUsage') IS NOT NULL DROP TABLE #DbLogUsage;
CREATE TABLE #DbLogUsage
(
    database_name       SYSNAME PRIMARY KEY,
    total_log_size_mb   DECIMAL(19,2),
    used_log_size_mb    DECIMAL(19,2),
    used_log_pct        DECIMAL(9,4)
);

IF OBJECT_ID('tempdb..#DbLoopErrors') IS NOT NULL DROP TABLE #DbLoopErrors;
CREATE TABLE #DbLoopErrors
(
    database_name SYSNAME,
    error_number  INT,
    error_message NVARCHAR(4000)
);



--------------------------------------------------------------------------------
-- 1) Loop databases and capture per-file + log usage
--------------------------------------------------------------------------------


DECLARE @db SYSNAME, @sql NVARCHAR(MAX);

DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE state = 0   -- ONLINE only; skip RESTORING, etc.
ORDER BY name;

OPEN dbs;
FETCH NEXT FROM dbs INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    BEGIN TRY
        -- Per-file (data + log). Data "used_mb" via FILEPROPERTY.
        INSERT INTO #DbFiles
        (
            database_name, file_id, type_desc, logical_name, physical_name, state_desc,
            size_mb, used_mb, max_size_mb, growth_desc, is_percent_growth, growth_mb, filegroup_name
        )
        SELECT
            DB_NAME(),
            df.file_id,
            df.type_desc,
            df.name,
            df.physical_name,
            df.state_desc,
            CONVERT(DECIMAL(19,2), df.size * 8.0 / 1024.0) AS size_mb,
            CONVERT(DECIMAL(19,2),
                CASE
                    WHEN df.type_desc IN (''ROWS'',''FILESTREAM'') THEN FILEPROPERTY(df.name, ''SpaceUsed'') * 8.0 / 1024.0
                    ELSE NULL
                END) AS used_mb,
            CONVERT(DECIMAL(19,2),
                CASE
                    WHEN df.max_size = -1 THEN NULL
                    ELSE df.max_size * 8.0 / 1024.0
                END) AS max_size_mb,
            CASE
                WHEN df.is_percent_growth = 1 THEN CAST(df.growth AS NVARCHAR(10)) + N''%''
                ELSE CAST(CONVERT(DECIMAL(19,2), df.growth * 8.0 / 1024.0) AS NVARCHAR(30)) + N'' MB''
            END AS growth_desc,
            df.is_percent_growth,
            CONVERT(DECIMAL(19,2),
                CASE WHEN df.is_percent_growth = 0 THEN df.growth * 8.0 / 1024.0 ELSE NULL END) AS growth_mb,
            fg.name AS filegroup_name
        FROM sys.database_files AS df
        LEFT JOIN sys.filegroups AS fg
               ON df.data_space_id = fg.data_space_id;

        -- Log usage for this DB
        INSERT INTO #DbLogUsage(database_name, total_log_size_mb, used_log_size_mb, used_log_pct)
        SELECT
            DB_NAME(),
            CONVERT(DECIMAL(19,2), total_log_size_in_bytes / 1024.0 / 1024.0),
            CONVERT(DECIMAL(19,2), used_log_space_in_bytes / 1024.0 / 1024.0),
            CONVERT(DECIMAL(9,4),  used_log_space_in_percent)
        FROM sys.dm_db_log_space_usage;
    END TRY
    BEGIN CATCH
        INSERT INTO #DbLoopErrors(database_name, error_number, error_message)
        VALUES (' + QUOTENAME(@db,'''') + N', ERROR_NUMBER(), ERROR_MESSAGE());
    END CATCH;
    ';

    EXEC sys.sp_executesql @sql;

    FETCH NEXT FROM dbs INTO @db;
END
CLOSE dbs; DEALLOCATE dbs;

--------------------------------------------------------------------------------
-- 2) Summaries
--------------------------------------------------------------------------------
DROP TABLE IF EXISTS #DBSummary

;WITH dataAgg AS
(
    SELECT
        database_name,
        SUM(CASE WHEN type_desc IN ('ROWS','FILESTREAM') THEN size_mb ELSE 0 END) AS data_size_mb,
        SUM(CASE WHEN type_desc IN ('ROWS','FILESTREAM') THEN ISNULL(used_mb,0) ELSE 0 END) AS data_used_mb
    FROM #DbFiles
    GROUP BY database_name
)
SELECT
    d.database_name,
    CAST(d.data_size_mb / 1024.0 AS DECIMAL(19,2)) AS data_size_gb,
    CAST(d.data_used_mb / 1024.0 AS DECIMAL(19,2)) AS data_used_gb,
    CAST(CASE WHEN d.data_size_mb > 0 THEN (d.data_used_mb * 100.0 / d.data_size_mb) END AS DECIMAL(9,2)) AS data_used_pct,
    CAST(l.total_log_size_mb / 1024.0 AS DECIMAL(19,2)) AS log_size_gb,
    CAST(l.used_log_size_mb  / 1024.0 AS DECIMAL(19,2)) AS log_used_gb,
    CAST(l.used_log_pct AS DECIMAL(9,2)) AS log_used_pct,
    CAST((d.data_size_mb + ISNULL(l.total_log_size_mb,0)) / 1024.0 AS DECIMAL(19,2)) AS total_size_gb
INTO #DbSummary
FROM dataAgg AS d
LEFT JOIN #DbLogUsage AS l
       ON l.database_name = d.database_name;

-- Summary view
SELECT * FROM #DbSummary ORDER BY total_size_gb DESC, database_name;

-- Per-file details (handy for MOVE targets on restore)
SELECT
    database_name, type_desc, file_id, logical_name, physical_name, state_desc,
    size_mb, used_mb, max_size_mb, growth_desc, filegroup_name
FROM #DbFiles
ORDER BY database_name, type_desc, file_id;

-- Any databases we couldn't read (permissions/offline/etc.)
SELECT * FROM #DbLoopErrors;

--------------------------------------------------------------------------------
-- 3) Volume free space (server-level) — needs VIEW SERVER STATE
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Volumes') IS NOT NULL DROP TABLE #Volumes;
SELECT DISTINCT
    vs.volume_mount_point,
    vs.file_system_type,
    CAST(vs.total_bytes     / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(19,2)) AS total_gb,
    CAST(vs.available_bytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(19,2)) AS free_gb
INTO #Volumes
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs;

SELECT * FROM #Volumes ORDER BY volume_mount_point;


-- Names table for reuse
IF OBJECT_ID('tempdb..#Names') IS NOT NULL DROP TABLE #Names;
CREATE TABLE #Names (DBName SYSNAME  NULL, BackupFile NVARCHAR(4000)  NULL);
INSERT INTO #Names(DBName)
SELECT database_name DBName
FROM #DbSummary;

-- Distinct DB count
SELECT COUNT(DISTINCT DBName) AS DistinctDatabaseCount FROM #Names;

-- Duplicates within the folder (same DB backed up multiple times)
SELECT DBName, COUNT(*) AS BackupFileCount
FROM #Names
GROUP BY DBName
HAVING COUNT(*) > 1
ORDER BY DBName;

-- Name overlaps with current instance (potential restore conflicts)
SELECT n.DBName AS ConflictingNameAlreadyOnInstance
FROM #Names n
JOIN sys.databases d ON d.name = n.DBName
ORDER BY n.DBName;


END
