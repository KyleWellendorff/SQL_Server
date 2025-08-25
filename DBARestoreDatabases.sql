USE [DBATools]
GO

/****** Object:  StoredProcedure [DBA].[RestoreDatabases]    Script Date: 8/25/2025 1:22:06 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [DBA].[RestoreDatabases]
@BackupDir NVARCHAR(4000),
@DataDir   NVARCHAR(4000),
@LogDir    NVARCHAR(4000)

----------------------------------------------------------------
--RUN ON SSDSQL01 WEST. Change storage volumes. DONT FORGET
----------------------------------------------------------------
/* TARGET SERVER: Restore every .bak from the backup share.
   Default uses xp_cmdshell to enumerate files (simple & reliable).
   If you cannot allow xp_cmdshell, see the "No xp_cmdshell" variant below.
*/
----------------------------------------------------------------
----------------------------------------------------------------
AS BEGIN

SET NOCOUNT ON
SET XACT_ABORT ON
/* === PARAMETERS === */
--DECLARE @BackupDir NVARCHAR(4000) = N'\\sgw\public\Public\Internal\SQLBackups\BackupsBeforeMigration\';
--DECLARE @DataDir   NVARCHAR(4000) = N'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\';
--DECLARE @LogDir    NVARCHAR(4000) = N'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\';

/* === SAFETY: ensure trailing slash on dirs === */
IF RIGHT(@BackupDir,1) <> N'\' SET @BackupDir += N'\';
IF RIGHT(@DataDir,1)   <> N'\' SET @DataDir   += N'\';
IF RIGHT(@LogDir,1)    <> N'\' SET @LogDir    += N'\';

/* === Enable xp_cmdshell if needed (idempotent) === */
IF NOT EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'xp_cmdshell' AND value_in_use = 1)
BEGIN
  EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
  EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;
END

/* === List .bak files === */
IF OBJECT_ID('tempdb..#Files') IS NOT NULL DROP TABLE #Files;
CREATE TABLE #Files (BackupFile NVARCHAR(4000));

DECLARE @cmd VARCHAR(8000);  -- IMPORTANT: xp_cmdshell expects VARCHAR on your instance
SET @cmd = 'dir "' + REPLACE(@BackupDir,'''','''''') + '*.bak" /b';

INSERT INTO #Files(BackupFile)
EXEC xp_cmdshell @cmd;

-- Clean rows and keep only .bak lines
DELETE FROM #Files
WHERE BackupFile IS NULL
   OR LTRIM(RTRIM(BackupFile)) = ''
   OR BackupFile NOT LIKE '%.bak';

/* === Loop and restore === */
DECLARE @BackupFile NVARCHAR(4000);
DECLARE @DBName SYSNAME;
DECLARE @RestoreSQL NVARCHAR(MAX);

DECLARE file_cursor CURSOR FAST_FORWARD FOR
    SELECT BackupFile FROM #Files;

OPEN file_cursor;
FETCH NEXT FROM file_cursor INTO @BackupFile;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Derive DB name from file name (strip .bak)
    SET @DBName = LEFT(@BackupFile, LEN(@BackupFile) - 4);

    -- Get FILELIST for this backup
    IF OBJECT_ID('tempdb..#FileList') IS NOT NULL DROP TABLE #FileList;
    CREATE TABLE #FileList
    (
        LogicalName NVARCHAR(128),
        PhysicalName NVARCHAR(260),
        [Type]       CHAR(1),
        FileGroupName NVARCHAR(128),
        [Size] BIGINT,
        MaxSize BIGINT,
        FileId INT,
        CreateLSN NUMERIC(25,0),
        DropLSN NUMERIC(25,0),
        UniqueId UNIQUEIDENTIFIER,
        ReadOnlyLSN NUMERIC(25,0),
        ReadWriteLSN NUMERIC(25,0),
        BackupSizeInBytes BIGINT,
        SourceBlockSize INT,
        FileGroupId INT,
        LogGroupGUID UNIQUEIDENTIFIER NULL,
        DifferentialBaseLSN NUMERIC(25,0) NULL,
        DifferentialBaseGUID UNIQUEIDENTIFIER NULL,
        IsReadOnly BIT,
        IsPresent BIT,
        TDEThumbprint VARBINARY(32) NULL,
        SnapshotUrl NVARCHAR(360) NULL
    );

    DECLARE @FileListSQL NVARCHAR(MAX) =
        N'RESTORE FILELISTONLY FROM DISK = N''' + @BackupDir + @BackupFile + N'''';

    INSERT INTO #FileList
    EXEC (@FileListSQL);

    /* Build MOVE clauses.
       - Logs -> @LogDir\<DBName>_<LogicalName>.ldf
       - Data (FileId=1) -> @DataDir\<DBName>_<LogicalName>.mdf
       - Additional data files -> .ndf
    */
DECLARE @Move NVARCHAR(MAX) = N'';

SELECT @Move =
    STUFF((
        SELECT N', ' +
               N'MOVE N''' + fl.LogicalName + N''' TO N''' +
               CASE WHEN fl.[Type] = 'L' THEN @LogDir ELSE @DataDir END +
               REPLACE(@DBName + N'_' + fl.LogicalName, N' ', N'_') +
               CASE WHEN fl.[Type] = 'L' THEN N'.ldf'
                    WHEN fl.[Type] = 'D' AND fl.FileId = 1 THEN N'.mdf'
                    ELSE N'.ndf' END + N''''
        FROM #FileList AS fl
        -- optional: keep primary data first, then others, then logs
        ORDER BY CASE WHEN fl.[Type] = 'D' THEN 0 ELSE 1 END,
                 CASE WHEN fl.FileId = 1 THEN 0 ELSE 1 END,
                 fl.FileId
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'');


    -- Final RESTORE command (prints by default)
    SET @RestoreSQL =
        N'RESTORE DATABASE [' + @DBName + N'] ' +
        N'FROM DISK = N''' + @BackupDir + @BackupFile + N''' ' +
        N'WITH REPLACE, ' + @Move + N', STATS = 5;';

    PRINT '---- Restoring ' + @DBName + ' from ' + @BackupFile + ' ----';
    PRINT @RestoreSQL;

    /* To actually run it, UNCOMMENT the next line */
    --EXEC (@RestoreSQL);

    DROP TABLE #FileList;

    FETCH NEXT FROM file_cursor INTO @BackupFile;
END

CLOSE file_cursor;
DEALLOCATE file_cursor;

DROP TABLE #Files;

END
GO


