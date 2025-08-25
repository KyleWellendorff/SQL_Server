   --FILL THESE TWO PARAMETERS OUT! NO BRACKETS!
   DECLARE @DatabaseName NVARCHAR(128)='DB NAME';
   DECLARE @UserName NVARCHAR(128)='domain\kwellendorff'
   
   
   DECLARE @SQL NVARCHAR(MAX);

    SET @SQL = 
         'USE [' + @DatabaseName + '];' + CHAR(13) +
         'IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = ''' + @UserName + ''')' + CHAR(13) +
         'BEGIN' + CHAR(13) +
         '    CREATE USER [' + @UserName + '] FOR LOGIN [' + @UserName + '];' + CHAR(13) +
         'END;' + CHAR(13) +
         'ALTER ROLE [db_datareader] ADD MEMBER [' + @UserName + '];' + CHAR(13) +
         'ALTER ROLE [db_datawriter] ADD MEMBER [' + @UserName + '];'+ CHAR(13) ++ CHAR(13) +
   
    PRINT 'Executing the following dynamic SQL:'; 
    PRINT @SQL;
