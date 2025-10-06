USE master;
GO

DECLARE @dbName SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE database_id > 4   -- Skip system DBs
  AND state = 0;        -- Online only

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
USE [' + @dbName + N'];
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_256
ENCRYPTION BY SERVER CERTIFICATE TDE_Cert_2025_09;
ALTER DATABASE [' + @dbName + N'] SET ENCRYPTION ON;
';

    PRINT '----------------------------------------------------';
    PRINT '-- Commands for database: ' + @dbName;
    PRINT '----------------------------------------------------';
    PRINT @sql;

    FETCH NEXT FROM db_cursor INTO @dbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

PRINT 'All CREATE DATABASE ENCRYPTION KEY and ENCRYPTION ON statements have been printed.';
GO



SELECT 
    db.name AS DatabaseName,
    dek.encryption_state,
    CASE dek.encryption_state
        WHEN 0 THEN 'No database encryption key present'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        WHEN 6 THEN 'Protection change in progress'
    END AS EncryptionStateDescription,
    dek.percent_complete,
    dek.encryptor_type,
    c.name AS CertificateName
FROM sys.databases AS db
LEFT JOIN sys.dm_database_encryption_keys AS dek
    ON db.database_id = dek.database_id
LEFT JOIN sys.certificates AS c
    ON dek.encryptor_thumbprint = c.thumbprint
ORDER BY db.name;
