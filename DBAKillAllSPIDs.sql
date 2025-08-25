USE [master]
GO 

DECLARE @kill VARCHAR(8000) = '';

SELECT @kill = @kill + 'kill ' + CONVERT(VARCHAR(5), spid) + ';' FROM master..sysprocesses  WHERE dbid = db_id('kyle_dev') 

PRINT @kill 
--EXEC(@kill) --uncomment when ready
