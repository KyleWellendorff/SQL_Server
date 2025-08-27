/* ===== CONFIG ===== */
DECLARE @UserList TABLE (WinLogin sysname PRIMARY KEY);
INSERT INTO @UserList (WinLogin)
VALUES (N'NCC1701\jcongzon'),
       (N'NCC1701\amower'),
       (N'NCC1701\avogelgesang');

/* ===== 1) Ensure server-level LOGINS exist ===== */
DECLARE @u sysname;
DECLARE curLogins CURSOR LOCAL FAST_FORWARD FOR SELECT WinLogin FROM @UserList;
OPEN curLogins;
FETCH NEXT FROM curLogins INTO @u;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @u)
    BEGIN
        DECLARE @sqlCreateLogin nvarchar(max) = N'CREATE LOGIN ' + QUOTENAME(@u) + N' FROM WINDOWS;';
        PRINT 'Creating LOGIN ' + @u;
        EXEC(@sqlCreateLogin);
    END
    ELSE
        PRINT 'LOGIN exists: ' + @u;

    FETCH NEXT FROM curLogins INTO @u;
END
CLOSE curLogins; DEALLOCATE curLogins;

/* Temp table so the list is visible inside dynamic SQL batches */
IF OBJECT_ID('tempdb..#UsersToAdd') IS NOT NULL DROP TABLE #UsersToAdd;
CREATE TABLE #UsersToAdd(WinLogin sysname PRIMARY KEY);
INSERT INTO #UsersToAdd SELECT WinLogin FROM @UserList;

/* ===== 2) Loop all ONLINE DBs with "Gas" in the name ===== */
DECLARE @db sysname, @sql nvarchar(max);
DECLARE curDBs CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND name LIKE N'%Gas%';
OPEN curDBs;
FETCH NEXT FROM curDBs INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '--- Processing database ' + @db + ' ---';

    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    SET NOCOUNT ON;

    DECLARE @WinLogin sysname;

    DECLARE u2 CURSOR LOCAL FAST_FORWARD FOR
        SELECT WinLogin FROM #UsersToAdd;

    OPEN u2;
    FETCH NEXT FROM u2 INTO @WinLogin;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- 2a) Create USER if missing
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @WinLogin)
        BEGIN
            DECLARE @cmd nvarchar(max) =
                N''CREATE USER '' + QUOTENAME(@WinLogin) + N'' FOR LOGIN '' + QUOTENAME(@WinLogin) + N'';'';
            PRINT ''Creating USER '' + @WinLogin + '' in ' + @db + N''';
            EXEC(@cmd);
        END
        ELSE
            PRINT ''USER exists: '' + @WinLogin + '' in ' + @db + N''';

        -- 2b) Add to db_datareader
        IF NOT EXISTS (
            SELECT 1
            FROM sys.database_role_members drm
            JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
            JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
            WHERE r.name = N''db_datareader'' AND m.name = @WinLogin
        )
        BEGIN
            DECLARE @cmd_reader nvarchar(max) =
                N''ALTER ROLE [db_datareader] ADD MEMBER '' + QUOTENAME(@WinLogin) + N'';'';
            PRINT ''Adding to db_datareader: '' + @WinLogin + '' in ' + @db + N''';
            EXEC(@cmd_reader);
        END

        -- 2c) Add to db_datawriter
        IF NOT EXISTS (
            SELECT 1
            FROM sys.database_role_members drm
            JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
            JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
            WHERE r.name = N''db_datawriter'' AND m.name = @WinLogin
        )
        BEGIN
            DECLARE @cmd_writer nvarchar(max) =
                N''ALTER ROLE [db_datawriter] ADD MEMBER '' + QUOTENAME(@WinLogin) + N'';'';
            PRINT ''Adding to db_datawriter: '' + @WinLogin + '' in ' + @db + N''';
            EXEC(@cmd_writer);
        END

        -- 2d) Add to db_ddladmin
        IF NOT EXISTS (
            SELECT 1
            FROM sys.database_role_members drm
            JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
            JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
            WHERE r.name = N''db_ddladmin'' AND m.name = @WinLogin
        )
        BEGIN
            DECLARE @cmd_ddl nvarchar(max) =
                N''ALTER ROLE [db_ddladmin] ADD MEMBER '' + QUOTENAME(@WinLogin) + N'';'';
            PRINT ''Adding to db_ddladmin: '' + @WinLogin + '' in ' + @db + N''';
            EXEC(@cmd_ddl);
        END

        FETCH NEXT FROM u2 INTO @WinLogin;
    END
    CLOSE u2; DEALLOCATE u2;
    ';

    BEGIN TRY
        EXEC(@sql);
    END TRY
    BEGIN CATCH
        PRINT 'Error in DB ' + @db + ': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM curDBs INTO @db;
END
CLOSE curDBs; DEALLOCATE curDBs;

PRINT 'Done.';
