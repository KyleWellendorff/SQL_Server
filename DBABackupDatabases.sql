USE [DBATools]
GO
/****** Object:  StoredProcedure [DBA].[BackupDatabases]    Script Date: 8/25/2025 1:21:16 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [DBA].[BackupDatabases]
/* RUN ON SSDSQL01!
	SOURCE SERVER: Full COPY_ONLY backups for all user DBs
    Writes one .bak per DB to the UNC you provided.
*/

@BackupDir NVARCHAR(4000) = NULL --N'\\sgw\public\Public\Internal\SQLBackups\BackupsBeforeMigration\'

AS BEGIN

SET NOCOUNT ON
SET XACT_ABORT ON

PRINT 'PLEASE UNCOMMENT THE EXEC(@SQL) IN THIS SP. It Only PRINTS as of now'

DECLARE @name SYSNAME
DECLARE @sql NVARCHAR(MAX);

-- Safety: make sure the SQL Server service account can WRITE to @BackupDir

DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE database_id > 4           -- user DBs only
  AND state_desc = 'ONLINE'
  AND name like '%kyle%';

OPEN dbs;
FETCH NEXT FROM dbs INTO @name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'BACKUP DATABASE ' + QUOTENAME(@name) + '
      TO DISK = ' + QUOTENAME(@BackupDir + @name + N'.bak', '''') + '
      WITH COPY_ONLY, CHECKSUM, INIT, COMPRESSION, STATS = 5;';
    
	
	PRINT @sql;
    --BEGIN TRY
    --    EXEC sys.sp_executesql @sql;
    --END TRY
    --BEGIN CATCH
    --    PRINT CONCAT('!! Backup failed for ', @name, ': ', ERROR_MESSAGE());
    --END CATCH;

    FETCH NEXT FROM dbs INTO @name;
END

CLOSE dbs; DEALLOCATE dbs;

PRINT 'Backups completed.';

END
