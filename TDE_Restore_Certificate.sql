USE master;
GO

-- Create DMK if missing
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'STRONG_PW';
END
GO

-- Restore certificate from file
CREATE CERTIFICATE TDE_Cert_2025_09
FROM FILE = '\\sgw\public\Public\Internal\SQLBackups\TDE\TDE_Cert_2025_09.cer'
WITH PRIVATE KEY (
    FILE = '\\sgw\public\Public\Internal\SQLBackups\TDE\TDE_Cert_2025_09.pvk',
    DECRYPTION BY PASSWORD = 'StrongPW'
);
GO

GO
