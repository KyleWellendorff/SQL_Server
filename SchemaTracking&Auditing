--create view for long running transcode and video quality. check if it is initiated
--
/* ==========================================================
   Create Archive Schema
   ========================================================== */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Archive')
    EXEC('CREATE SCHEMA Archive')
	GO
/* ==========================================================
   Drop Old Objects (if they exist)
   ========================================================== */
IF OBJECT_ID('Archive.ProcedureChanges_vw') IS NOT NULL
    DROP VIEW Archive.ProcedureChanges_vw;
IF OBJECT_ID('Archive.ViewChanges_vw') IS NOT NULL
    DROP VIEW Archive.ViewChanges_vw;
IF OBJECT_ID('Archive.SchemaChanges_vw') IS NOT NULL
    DROP VIEW Archive.SchemaChanges_vw;
IF OBJECT_ID('SchemaChange_trg') IS NOT NULL
    DROP TRIGGER SchemaChange_trg ON DATABASE;
IF OBJECT_ID('Archive.SchemaChangeLog') IS NOT NULL
    DROP TABLE Archive.SchemaChangeLog;
IF OBJECT_ID('Archive.StoredProcedureArchive') IS NOT NULL
    DROP TABLE Archive.StoredProcedureArchive;
GO

/* ==========================================================
   Create Archive Table
   ========================================================== */
CREATE TABLE Archive.SchemaChangeLog
(
    ChangeID     INT IDENTITY(1,1) PRIMARY KEY,
    EventType    NVARCHAR(100) NOT NULL,
    SchemaName   NVARCHAR(128) NOT NULL,
    ObjectName   NVARCHAR(512) NOT NULL,
    ObjectType   NVARCHAR(100) NOT NULL,
    EventTime    DATETIME2(3)  NOT NULL,
    EventDDL     NVARCHAR(MAX) NULL,
    EventXML     XML NULL
);
GO

CREATE NONCLUSTERED INDEX IX_SchemaChangeLog_EventType
ON Archive.SchemaChangeLog (EventType)
INCLUDE (SchemaName, ObjectName, ObjectType, EventTime);
GO

CREATE NONCLUSTERED INDEX IX_SchemaChangeLog_EventTime
ON Archive.SchemaChangeLog (EventTime);
GO

/* ==========================================================
   Create Trigger
   ========================================================== */
CREATE TRIGGER SchemaChange_trg
ON DATABASE
FOR CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE,
    CREATE_TABLE, ALTER_TABLE, DROP_TABLE,
    CREATE_SCHEMA, ALTER_SCHEMA, DROP_SCHEMA,
    CREATE_VIEW, ALTER_VIEW, DROP_VIEW
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @data XML = EVENTDATA();
    DECLARE @eventType NVARCHAR(100) = @data.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)');
    DECLARE @objectName NVARCHAR(512) = @data.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(512)');
    DECLARE @schemaName NVARCHAR(128) = @data.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)');
    DECLARE @fullName NVARCHAR(512) = QUOTENAME(@schemaName) + '.' + QUOTENAME(@objectName);
    DECLARE @objectType NVARCHAR(100) = @data.value('(/EVENT_INSTANCE/ObjectType)[1]', 'NVARCHAR(100)');
    DECLARE @eventTime DATETIME2(3) = @data.value('(/EVENT_INSTANCE/PostTime)[1]', 'DATETIME2(3)');
    DECLARE @ddl NVARCHAR(MAX) = @data.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)');

    -- Skip temp tables
    IF (@objectName LIKE '#%')
        RETURN;

    -- Only log if ALTER actually changed the definition
    IF @eventType IN ('ALTER_PROCEDURE','ALTER_VIEW')
    BEGIN
        DECLARE @curr NVARCHAR(MAX), @prev NVARCHAR(MAX);

        SELECT @curr = sm.definition
        FROM sys.sql_modules sm
        JOIN sys.objects o ON sm.object_id = o.object_id
        WHERE o.object_id = OBJECT_ID(@fullName);

        SELECT TOP 1 @prev = scl.EventDDL
        FROM Archive.SchemaChangeLog scl
        WHERE scl.ObjectName = @objectName
          AND scl.SchemaName = @schemaName
          AND scl.ObjectType = @objectType
        ORDER BY scl.ChangeID DESC;

        IF @curr = @prev
            RETURN; -- no change in definition
    END

-- Save just the CommandText as XML with new line
INSERT INTO Archive.SchemaChangeLog (EventType, ObjectName, ObjectType, EventTime, EventDDL, EventXML, SchemaName)
VALUES (
    @eventType,
    @objectName,
    @objectType,
    @eventTime,
    @ddl,
    CAST('<definition><![CDATA[' + CHAR(13) + CHAR(10) + @ddl + CHAR(13) + CHAR(10) +']]></definition>' AS XML)
	,@schemaName
);END
GO

/* ==========================================================
   Views for Reporting
   ========================================================== */
-- Stored Procedure Changes
CREATE OR ALTER VIEW Archive.ProcedureChanges_vw
AS
WITH Ranked AS (
    SELECT 
        scl.SchemaName,
        scl.ObjectName,
        scl.ObjectType,
        scl.EventTime,
        scl.EventDDL,
        scl.EventXML,
        ROW_NUMBER() OVER (PARTITION BY scl.SchemaName, scl.ObjectName ORDER BY scl.EventTime) AS rn
    FROM Archive.SchemaChangeLog scl
    WHERE scl.ObjectType = 'PROCEDURE'
)
SELECT 
    curr.SchemaName,
    curr.ObjectName,
    prev.EventDDL AS PreviousVersion,
    curr.EventDDL AS CurrentVersion,
    prev.EventXML AS PreviousVersionXML,
    curr.EventXML AS CurrentVersionXML,
    curr.EventTime AS ChangeDate
FROM Ranked curr
JOIN Ranked prev
    ON curr.SchemaName = prev.SchemaName
   AND curr.ObjectName = prev.ObjectName
   AND curr.rn = prev.rn + 1
WHERE prev.EventDDL <> curr.EventDDL;
GO

-- View Changes
CREATE OR ALTER VIEW Archive.ViewChanges_vw
AS
WITH Ranked AS (
    SELECT 
        scl.SchemaName,
        scl.ObjectName,
        scl.ObjectType,
        scl.EventTime,
        scl.EventDDL,
        scl.EventXML,
        ROW_NUMBER() OVER (PARTITION BY scl.SchemaName, scl.ObjectName ORDER BY scl.EventTime) AS rn
    FROM Archive.SchemaChangeLog scl
    WHERE scl.ObjectType = 'VIEW'
)
SELECT 
    curr.SchemaName,
    curr.ObjectName,
    prev.EventDDL AS PreviousVersion,
    curr.EventDDL AS CurrentVersion,
    prev.EventXML AS PreviousVersionXML,
    curr.EventXML AS CurrentVersionXML,
    curr.EventTime AS ChangeDate
FROM Ranked curr
JOIN Ranked prev
    ON curr.SchemaName = prev.SchemaName
   AND curr.ObjectName = prev.ObjectName
   AND curr.rn = prev.rn + 1
WHERE prev.EventDDL <> curr.EventDDL;
GO

-- Schema/Table Changes
CREATE OR ALTER VIEW Archive.SchemaChanges_vw
AS
SELECT 
    scl.SchemaName,
    scl.ObjectName,
    scl.ObjectType,
    scl.EventType,
    scl.EventTime as ChangeDate,
    scl.EventDDL,
    scl.EventXML
FROM Archive.SchemaChangeLog scl
WHERE scl.ObjectType IN ('TABLE','SCHEMA');
GO

/* ==========================================================
   Permissions
   ========================================================== */
GRANT SELECT, INSERT ON SCHEMA::Archive TO PUBLIC;
GO

/* ==========================================================
   Baseline Inserts
   ========================================================== */
TRUNCATE TABLE Archive.SchemaChangeLog;

-- Baseline: Procedures
INSERT INTO Archive.SchemaChangeLog (EventType, SchemaName, ObjectName, ObjectType, EventTime, EventDDL, EventXML)
SELECT
    'BASELINE' AS EventType,
    s.name AS SchemaName,
    o.name AS ObjectName,
    'PROCEDURE' AS ObjectType,
    SYSDATETIME() AS EventTime,
    sm.definition AS EventDDL,
    CAST('<definition><![CDATA[' + CHAR(13) + CHAR(10) + sm.definition + CHAR(13) + CHAR(10) + ']]></definition>' AS XML)
FROM sys.objects o
JOIN sys.sql_modules sm ON o.object_id = sm.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'P';  

-- Baseline: Views
INSERT INTO Archive.SchemaChangeLog (EventType, SchemaName, ObjectName, ObjectType, EventTime, EventDDL, EventXML)
SELECT
    'BASELINE' AS EventType,
    s.name AS SchemaName,
    o.name AS ObjectName,
    'VIEW' AS ObjectType,
    SYSDATETIME() AS EventTime,
    sm.definition AS EventDDL,
    CAST('<definition><![CDATA[' + CHAR(13) + CHAR(10) + sm.definition + CHAR(13) + CHAR(10) +']]></definition>' AS XML)
FROM sys.objects o
JOIN sys.sql_modules sm ON o.object_id = sm.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'V';  

-- Baseline: Tables
INSERT INTO Archive.SchemaChangeLog (EventType, SchemaName, ObjectName, ObjectType, EventTime, EventDDL, EventXML)
SELECT
    'BASELINE' AS EventType,
    s.name AS SchemaName,
    t.name AS ObjectName,
    'TABLE' AS ObjectType,
    SYSDATETIME() AS EventTime,
    OBJECT_DEFINITION(t.object_id) AS EventDDL,
    NULL AS EventXML
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id;
GO




--TESTING
ALTER PROCEDURE Archive.TestSelect
AS
BEGIN
    SELECT 9999 AS Test;
END;
GO

create  table model.test (ID int)



--views to highlight last change
SELECT * FROM Archive.ProcedureChanges_vw ORDER BY ChangeDate desc
SELECT * FROM Archive.ViewChanges_vw ORDER BY ChangeDate desc
SELECT * FROM Archive.SchemaChanges_vw ORDER BY ChangeDate desc

--base table
SELECT * FROM Archive.SchemaChangeLog ORDER BY EventTime desc

