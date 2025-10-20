SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
-- Returns a table of the latest changes to all database objects
-- that have changed since the last time the procedure was called.
-- It compares the current version of the database objects with the
-- previous one and lists what has altered and who did it. In order
-- to work out who did it, it uses the default trace.
CREATE PROCEDURE [dbo].[RG_WhatsChanged_v4]
  @SinceWhen DATETIME OUTPUT,
  @DatabaseList XML,
  @UseDefaultTraceRollover INT
AS
SET NOCOUNT ON
SET ANSI_PADDING ON
DECLARE
  @Ii                        INT,
  @IiMax                     INT,
  @SqlServerVersion          INT,
  @CurrentDatabase           NVARCHAR(258),
  @Command                   NVARCHAR(4000)

IF OBJECT_ID( N'tempdb.dbo.RG_AllObjects_v4', N'U' ) IS NULL
BEGIN
  -- This table keeps a record of all the objects we are interested in,
  -- and keeps them up to date from the system tables.
  CREATE TABLE tempdb.dbo.RG_AllObjects_v4
  (
    AllObjectsID     INT IDENTITY(1,1),
    EntryDateTime    DATETIME,
    DatabaseID       INT,
    ObjectType       CHAR(2),
    ObjectID         INT NOT NULL,
    SchemaName       sysname NULL,
    ObjectName       sysname  NOT NULL,
    ModifyDate       DATETIME,
    ParentObjectID   INT      NULL,
    ParentObjectName sysname  NULL,
    ParentObjectType CHAR(2)  NULL,
    TypeOfAction     VARCHAR(20) NOT NULL DEFAULT 'Existing', -- Deleted Modified Renamed Created Expired -- TODO WHAT SHOULD THE DEFAULT BE???
    [Matched]        INT NOT NULL DEFAULT 0,
    UserName         NVARCHAR(256) NULL
  )
  CREATE CLUSTERED INDEX IdxObjectType ON tempdb.dbo.RG_AllObjects_v4 (DatabaseID, ObjectID, ObjectType)
END

-- single '#' tables are scoped to this PROC.

CREATE TABLE #RG_DefaultTraceCache
(
  -- this is the section of default cache that is read in
  DefaultTraceCacheID INT IDENTITY(1,1) PRIMARY KEY NONCLUSTERED,
  StartTime           DATETIME      NULL,
  DatabaseID          INT           NULL,
  DatabaseName        NVARCHAR(128),
  EventSubClass       INT,
  EventClass          INT,
  ObjectID            INT,
  ObjectType          NVARCHAR(128),
  ObjectTypeCode      INT,
  ActionType          VARCHAR(40),
  ObjectName          NVARCHAR(256) NULL,
  UserName            NVARCHAR(256) NULL
) ON [PRIMARY];
CREATE CLUSTERED INDEX #RG_DefaultTraceCache_Index1 ON #RG_DefaultTraceCache (DatabaseID, DatabaseName, ObjectID, ObjectType);


-- get the databases into a table


-- first we update our idea of what's in the schema
CREATE TABLE #CurrentDatabaseObjects
(
  DatabaseID       INT,
  ObjectType       CHAR(2),
  ObjectID         INT,
  SchemaName       sysname  NULL,
  ObjectName       sysname,
  ModifyDate       DATETIME,
  ParentObjectID   INT NULL,
  ParentObjectName sysname  NULL,
  ParentObjectType CHAR(2)  NULL
);

CREATE TABLE #Mappings
(
  DatabaseID       INT,
  ObjectName       sysname,
  AttributeID      INT,
  ObjectID         INT,
  MappingType      VARCHAR(20)
);

CREATE TABLE #DatabaseNameToIdMapping
(
  DatabaseI    INT IDENTITY(1, 1),
  DatabaseName sysname,
  DatabaseID   INT
);

-- Build up the database name to ID mapping from the supplied @DatabaseList
INSERT INTO #DatabaseNameToIdMapping (DatabaseName, DatabaseID)
SELECT WantedDatabase, sys.databases.database_id
FROM
       ( SELECT X.Y.value('.', 'sysname') AS WantedDatabase
         FROM   @DatabaseList.nodes('/stringarray/element/item/text()') AS X ( Y )
       ) F
       LEFT OUTER JOIN sys.databases ON sys.databases.name = WantedDatabase
WHERE  sys.databases.database_id NOT IN
       ( SELECT resource_database_id
         FROM   sys.dm_tran_locks L
                INNER JOIN sys.databases D
                  ON D.database_id = L.resource_database_id
         WHERE  resource_type = 'OBJECT'
                AND resource_associated_entity_id < 100
                AND request_type = 'LOCK'
                AND request_status = 'GRANT'
       );

/***** DATABASE OBJECT ENUMERATION *****/

SELECT @Ii = MIN(DatabaseI), @IiMax = MAX(DatabaseI)
FROM   #DatabaseNameToIdMapping;
WHILE  @Ii <= @IiMax
BEGIN
  -- For each database that we are polling
  SELECT @CurrentDatabase = QUOTENAME(DatabaseName)
  FROM   #DatabaseNameToIdMapping
  WHERE  DatabaseI = @Ii;

  DECLARE @Command1 NVARCHAR(4000);
  DECLARE @Command2 NVARCHAR(4000);
  DECLARE @Command3 NVARCHAR(4000);

  -- USE has to be the first statement in a batch, therefore we have to build the query up as text and eval it.
  -- Enumerates all the objects in @CurrentDatabase and store the results into #CurrentDatabaseObjects
  SET @Command1 = '
    USE ' + @CurrentDatabase + '
    INSERT INTO #CurrentDatabaseObjects
      SELECT DB_ID(),''EP'',abs(checksum(major_id, minor_id, ep.name)), s.name, left(ep.name,256), ''1/1/2000'',parent.object_id, parent.name, parent.type
      from sys.extended_properties ep
      inner join sys.objects parent on major_id = parent.object_id
      inner join sys.schemas s on s.schema_id = parent.schema_id
      where class=1
      AND ep.name not like ''microsoft_database_tools_support''
      ';

    SET @Command2 = '
    USE ' + @CurrentDatabase + '
    INSERT INTO #CurrentDatabaseObjects
      SELECT DB_ID(), ''AS'', assembly_id, NULL, name COLLATE Latin1_General_BIN AS ObjectName, modify_date, null, null, null FROM sys.assemblies WHERE assembly_id > 65535
      UNION ALL
      SELECT DB_ID(), ''BN'', remote_service_binding_id, NULL, name, ''1/1/2000'', null, null, null FROM sys.remote_service_bindings
      UNION ALL
      SELECT DB_ID(), ''CT'', service_contract_id, NULL, name, ''1/1/2000'', null, null, null FROM sys.service_contracts WHERE service_contract_id > 65535
      UNION ALL
      SELECT DB_ID(), ''EN'' AS ObjectType, [object_id] AS ObjectID, NULL AS SchemaName, name, modify_date, null, null, null FROM sys.event_notifications
      UNION ALL
      SELECT DB_ID(), ''MT'', message_type_id, NULL, name, ''1/1/2000'', null, null, null FROM sys.service_message_types WHERE message_type_id > 65535
      UNION ALL
      SELECT DB_ID() AS DatabaseID, ''PF'' AS ObjectType, [function_id] AS ObjectID, NULL AS SchemaName, name, modify_date, null, null, null FROM sys.partition_functions
      UNION ALL
      SELECT DB_ID(), ''PS'', data_space_id, NULL, name, ''1/1/2000'', null, null, null FROM sys.partition_schemes
      UNION ALL
      SELECT DB_ID(), ''RT'', route_id, NULL, name, ''1/1/2000'', null, null, null FROM sys.routes WHERE route_id > 65535 AND name <> ''AutoCreatedLocal''
      UNION ALL
      SELECT DB_ID(), ''SC'' AS ObjectType, [schema_id] AS ObjectID, null AS SchemaName, name, ''1/1/2000'', null, null, null FROM sys.schemas
        WHERE schema_id > 4 AND (schema_id < 16384 OR schema_id > 16393) -- excludes all system generated schemas';

    SET @Command3 = '
    USE ' + @CurrentDatabase + '
    INSERT INTO #CurrentDatabaseObjects
      SELECT DB_ID(), ''SV'' AS ObjectType, [service_id] AS ObjectID, null AS SchemaName, name, ''1/1/2000'', null, null, null FROM sys.services where [service_id] > 65535
      UNION ALL
      SELECT DB_ID(), ''SX'', sysXSC.xml_collection_id, sysSchemas.name, sysXSC.name,  sysXSC.modify_date, null, null, null
        FROM sys.xml_schema_collections AS sysXSC LEFT JOIN sys.schemas AS sysSchemas ON sysSchemas.schema_id = sysXSC.schema_id
        WHERE sysXSC.xml_collection_id > 65535
      UNION ALL
      SELECT DB_ID(), [type] AS ObjectType, object_id AS ObjectID, NULL AS SchemaName, name, modify_Date, null, null, null FROM sys.triggers -- TA and TR
      WHERE parent_id = 0
      UNION ALL
      SELECT DB_ID(), SystemObjects.type, SystemObjects.object_id, SysSchemas.name COLLATE Latin1_General_BIN, SystemObjects.name, SystemObjects.modify_date,
        CASE WHEN SystemObjects.parent_object_id = 0 THEN NULL ELSE SystemObjects.parent_object_id END, OBJECT_NAME(SystemObjects.parent_object_id), Parent.type
      FROM sys.objects AS SystemObjects
        LEFT OUTER JOIN sys.objects AS Parent ON SystemObjects.parent_object_id = Parent.object_id
        LEFT OUTER JOIN sys.schemas AS SysSchemas ON SysSchemas.schema_id = SystemObjects.schema_id
      WHERE SystemObjects.type NOT IN  (''S'', ''IT'', ''TT'') -- exclude internal or system tables
        AND NOT (SystemObjects.type = ''SQ'' AND SystemObjects.name IN (''QueryNotificationErrorsQueue'', ''EventNotificationErrorsQueue'', ''ServiceBrokerQueue''))  -- crude way to ignore ms-shipped queue objects';

  EXEC sp_executesql @Command1;
  EXEC sp_executesql @Command2;
  EXEC sp_executesql @Command3;

  SELECT @Ii = @Ii + 1;
END

CREATE INDEX IdxCurrentDatabaseObjects ON #CurrentDatabaseObjects (DatabaseID, ObjectID, ObjectType);

/***** END OF DATABASE OBJECT ENUMERATION *****/


SELECT @SqlServerVersion = CONVERT(INT, LEFT(TheVersion, CHARINDEX('.', TheVersion) - 1))
    FROM ( SELECT CONVERT(Varchar(40), SERVERPROPERTY('productversion')) + '.' ) f(TheVersion)
-- For versions of SQL Server 2008 onwards, select table types insert into #Mappings (TO BE DETERMINED WHAT THIS MEANS)
IF @SqlServerVersion > 9
BEGIN
  SELECT @Ii = MIN(DatabaseI), @IiMax = MAX(DatabaseI)
  FROM   #DatabaseNameToIdMapping;
  WHILE  @Ii <= @IiMax
  BEGIN
    SELECT @CurrentDatabase = QUOTENAME(DatabaseName)
    FROM   #DatabaseNameToIdMapping
    WHERE  DatabaseI = @Ii;
    SET @Command = '
      USE ' + @CurrentDatabase + '
      INSERT INTO #Mappings (DatabaseID, ObjectName, AttributeID, ObjectID, MappingType)
      SELECT DB_ID(), t.name, t.user_type_id, o.object_ID, ''TT''
      FROM sys.types t
      INNER JOIN sys.objects o
        ON o.name LIKE ''TT_'' + t.name + ''%'' COLLATE Latin1_General_BIN
      AND t.is_user_defined = 1
      AND t.is_table_type = 1
      AND o.type =''TT'' COLLATE Latin1_General_BIN'
    EXEC sp_executesql @Command;

    SELECT @Ii = @Ii + 1;
  END
END

DECLARE @ChildObjectsTableEP TABLE
(
  ParentObjectID   INT,
  DatabaseID       INT,
  ParentObjectType CHAR(2)  NULL
);
INSERT INTO @ChildObjectsTableEP
SELECT CurrentObjects.ParentObjectID, CurrentObjects.DatabaseID, CurrentObjects.ParentObjectType
FROM   tempdb.dbo.RG_AllObjects_v4 CurrentObjects
  LEFT OUTER JOIN #CurrentDatabaseObjects NewObjects
    ON CurrentObjects.DatabaseID = NewObjects.DatabaseID
      AND CurrentObjects.ObjectID = NewObjects.ObjectID
      AND CurrentObjects.ObjectType = NewObjects.ObjectType
WHERE CurrentObjects.ObjectType = 'EP'
  AND NewObjects.ObjectID IS NULL
  AND CurrentObjects.TypeOfAction <> 'Deleted'
UNION ALL
SELECT NewObjects.ParentObjectID, NewObjects.DatabaseID, NewObjects.ParentObjectType
FROM   #CurrentDatabaseObjects NewObjects
  LEFT OUTER JOIN tempdb.dbo.RG_AllObjects_v4 CurrentObjects
    ON CurrentObjects.DatabaseID = NewObjects.DatabaseID
      AND CurrentObjects.ObjectID = NewObjects.ObjectID
      AND CurrentObjects.ObjectType = NewObjects.ObjectType
WHERE NewObjects.ObjectType = 'EP'
  AND CurrentObjects.ObjectID IS NULL


/***** UPDATE RG TABLE WITH OBJECT STATUS *****/

BEGIN TRANSACTION -- actually takes a mutex and blocks anyone else from proceeding
-- firstly we expire renamed objects
UPDATE tempdb.dbo.RG_AllObjects_v4
SET    EntryDateTime = GETUTCDATE(),
       [Matched]     = 0,
       UserName      = NULL,
       ObjectName    = NewObjects.ObjectName,
       SchemaName    = NewObjects.SchemaName,
       TypeOfAction  = 'Renamed',
       ModifyDate    = NewObjects.ModifyDate
FROM   tempdb.dbo.RG_AllObjects_v4 CurrentObjects
       INNER JOIN #CurrentDatabaseObjects NewObjects
         ON CurrentObjects.DatabaseID = NewObjects.DatabaseID
            AND CurrentObjects.ObjectID = NewObjects.ObjectID
            AND CurrentObjects.ObjectType = NewObjects.ObjectType
WHERE  (CurrentObjects.ObjectName <> NewObjects.ObjectName
            OR COALESCE(CurrentObjects.SchemaName, '') <> COALESCE(NewObjects.SchemaName, ''))

-- then expire modified objects
UPDATE tempdb.dbo.RG_AllObjects_v4
SET    EntryDateTime = GETUTCDATE(),
       [Matched]     = 0,
       UserName      = NULL,
       ObjectName    = NewObjects.ObjectName,
       SchemaName    = NewObjects.SchemaName,
       TypeOfAction  = 'Modified',
       ModifyDate    = NewObjects.ModifyDate
FROM   tempdb.dbo.RG_AllObjects_v4 CurrentObjects
       INNER JOIN #CurrentDatabaseObjects NewObjects
         ON CurrentObjects.DatabaseID = NewObjects.DatabaseID
            AND CurrentObjects.ObjectID = NewObjects.ObjectID
            AND CurrentObjects.ObjectType = NewObjects.ObjectType
WHERE  CurrentObjects.ModifyDate < NewObjects.ModifyDate


-- and any child objects that when created or deleted
-- there is no corresponding update to the parent modification date
-- currently only EP, but you wait!
UPDATE tempdb.dbo.RG_AllObjects_v4
SET    EntryDateTime = GETUTCDATE(),
       [Matched]     = 0,
       UserName      = NULL,
       TypeOfAction  = 'Modified',
       ModifyDate    = GETUTCDATE()
FROM   tempdb.dbo.RG_AllObjects_v4 o
INNER JOIN @ChildObjectsTableEP f
  ON o.ObjectID = f.ParentObjectID
    AND o.DatabaseID = f.DatabaseID
WHERE o.ObjectType = 'EP'

-- expire vanished objects
UPDATE tempdb.dbo.RG_AllObjects_v4
SET    EntryDateTime = GETUTCDATE(),
       [Matched]     = 0,
       UserName      = NULL,
       TypeOfAction  = 'Deleted'
       -- Because NewObjects has no record for the deleted table, we can't say when the deletion happened
FROM   tempdb.dbo.RG_AllObjects_v4
       LEFT OUTER JOIN #CurrentDatabaseObjects NewObjects
         ON tempdb.dbo.RG_AllObjects_v4.DatabaseID = NewObjects.DatabaseID
            AND tempdb.dbo.RG_AllObjects_v4.ObjectID = NewObjects.ObjectID
            AND tempdb.dbo.RG_AllObjects_v4.ObjectType = NewObjects.ObjectType
WHERE  tempdb.dbo.RG_AllObjects_v4.TypeOfAction <> 'Deleted'
       AND NewObjects.ObjectID IS NULL
       AND tempdb.dbo.RG_AllObjects_v4.DatabaseID IN (SELECT DatabaseID FROM #DatabaseNameToIdMapping)


-- Add in initial creation or modification
-- Remember if anything got changed
INSERT INTO tempdb.dbo.RG_AllObjects_v4
(
  EntryDateTime,
  DatabaseID, ObjectType, ObjectID,
  SchemaName, ObjectName,
  ModifyDate,
  ParentObjectID, ParentObjectName, ParentObjectType,
  TypeOfAction
)
SELECT GETUTCDATE(), NewObjects.DatabaseID, NewObjects.ObjectType, NewObjects.ObjectID,
       NewObjects.SchemaName, NewObjects.ObjectName,
       NewObjects.ModifyDate,
       NewObjects.ParentObjectID, NewObjects.ParentObjectName, NewObjects.ParentObjectType,
       'Created'
FROM   #CurrentDatabaseObjects NewObjects
       LEFT OUTER JOIN tempdb.dbo.RG_AllObjects_v4 CurrentObjects
         ON CurrentObjects.DatabaseID = NewObjects.DatabaseID
            AND CurrentObjects.ObjectID = NewObjects.ObjectID
            AND CurrentObjects.ObjectType = NewObjects.ObjectType
WHERE  CurrentObjects.ObjectID IS NULL -- Only add a record if it doesn't already exist

-- Expire parents of any object that has been modified so that the modification
-- is recorded against the parent
DECLARE @Waifs TABLE (ObjectID INT, DatabaseID INT, ModifyDate DATETIME)

-- Find all the objects modified where the parents have not shown as modified
INSERT INTO @Waifs (ObjectID, DatabaseID, ModifyDate)
SELECT Child.ParentObjectID as ObjectID, Child.DatabaseID, Child.ModifyDate
  FROM tempdb.dbo.RG_AllObjects_v4 Child
  LEFT OUTER JOIN tempdb.dbo.RG_AllObjects_v4 Parent
    ON Child.DatabaseID = Parent.DatabaseID
    AND Child.ParentObjectID = Parent.ObjectID
    AND Child.ObjectType = Parent.ObjectType
    AND Parent.TypeOfAction IN ('Created', 'Modified')
    AND ABS(DATEDIFF(minute, Parent.ModifyDate, Child.ModifyDate)) < 2 -- Not redundant. Removes ones that are way off as a performance optimisation, and also to avoid integer overflow below when dealing in ms and massive differences
  WHERE   Child.ParentObjectID IS NOT NULL
          AND ABS(DATEDIFF(ms, Parent.ModifyDate, Child.ModifyDate)) < 50
          AND Child.TypeOfAction = 'Created'
          AND Parent.AllObjectsID IS NULL

-- Adds a 'Modified' and Expired = 1 record for objects that are in @Waifs that are already in RG_AllObjects
UPDATE tempdb.dbo.RG_AllObjects_v4
SET
       EntryDateTime = GETUTCDATE(),
       UserName      = NULL,
       [Matched]     = 0,
       ModifyDate    = WaifObjects.ModifyDate,
       TypeOfAction  = 'Modified'
FROM   tempdb.dbo.RG_AllObjects_v4 CurrentObjects
       INNER JOIN @Waifs WaifObjects
         ON CurrentObjects.DatabaseID = WaifObjects.DatabaseID
            AND CurrentObjects.ObjectID = WaifObjects.ObjectID

-- further modifications are made to RG_AllObjects after this point, but only to copy in user info;
--  none of the fields that are involved in the matches above, so this can happen outside a transaction.
COMMIT TRANSACTION -- C# to check for deadlock in errors and ignore them (and back off polling time)

/***** END UPDATE RG TABLE WITH OBJECT STATUS *****/


/***** SHARED MODEL USERNAME SECTION *****/

-- Create a temporary table of all objects in the rg table that have not been matched to a username from the default trace.
CREATE TABLE #UnResolvedEvents(History INT NULL, [ObjectID] INT, ObjectType CHAR(2), [DatabaseID] INT, ParentObjectID INT)
INSERT INTO #UnResolvedEvents([ObjectID], ObjectType, [DatabaseID], ParentObjectID)
  SELECT ObjectID, ObjectType, DatabaseID, ParentObjectID
  FROM tempdb.dbo.RG_AllObjects_v4
  WHERE [Matched] = 0
  GROUP BY ObjectID, ObjectType, DatabaseID, ParentObjectID

-- if the previous query has processes any rows (ie there are unresolved events), then read the DT.
IF @@Rowcount >0
BEGIN
  -- now read in the default trace
  DECLARE
    @TraceLocation NVARCHAR(256),
    @TraceSuffixLength INT;

  -- Get the location of the default trace.
  -- If the trace file has rolled over, sys.traces returns the location of the current rollover
  -- trace file, such as C:\Program Files\Microsoft SQL Server\MSSQL11.SQL2012\MSSQL\Log\log_10.trc
  SET @TraceLocation = (SELECT TOP 1 path FROM sys.traces WHERE  is_default = 1);
  SET @TraceSuffixLength = CHARINDEX(N'_', REVERSE(@TraceLocation));

  -- If there is an underscore in the trace location, we can look at the suffix to try and strip the rollover
  -- number from it, so that the subsequent call to fn_trace_gettable will return data from previous rollovers.
  -- ie. transform
  --     C:\Program Files\Microsoft SQL Server\MSSQL11.SQL2012\MSSQL\Log\log_10.trc
  -- into
  --     C:\Program Files\Microsoft SQL Server\MSSQL11.SQL2012\MSSQL\Log\log.trc
  -- See http://technet.microsoft.com/en-us/library/ms188425.aspx for more info on fn_trace_gettable
  IF (@TraceSuffixLength > 1 AND @UseDefaultTraceRollover = 1) BEGIN

    DECLARE
      @TraceSeparatorLocation INT, -- Position of the underscore
      @TracePrefix NVARCHAR(256),  -- Eg. "C:\Program Files\Microsoft SQL Server\MSSQL11.SQL2012\MSSQL\Log\log"
      @TraceSuffix NVARCHAR(256);  -- Eg. "_10.trc"

    SET @TraceSeparatorLocation = LEN(@TraceLocation) - @TraceSuffixLength + 1;
    SET @TracePrefix = SUBSTRING(@TraceLocation, 0, @TraceSeparatorLocation);
    SET @TraceSuffix = SUBSTRING(@TraceLocation, @TraceSeparatorLocation, @TraceSuffixLength);

    -- This is equivalent to the regular expression '_[0-9]+.trc'.
    IF (@TraceSuffix LIKE N'_[0-9]%.trc' AND @TraceSuffix NOT LIKE '_%[^0-9]%.trc') BEGIN
      -- Strip the rollover number from the default trace location.
      SET @TraceLocation = @TracePrefix + N'.trc';
    END

  END

  BEGIN TRY
      INSERT INTO #RG_DefaultTraceCache
      SELECT DT.StartTime,
             DT.DatabaseID,
             DT.DatabaseName,
             DT.EventSubClass,
             DT.EventClass,
             DT.ObjectID,
             TSV.subclass_name AS ObjectType,
             DT.ObjectType AS ObjectTypeCode,
             TE.Name AS ActionType,
             DT.ObjectName,
             COALESCE(DT.NTUserName,DT.SessionLoginName, '') AS UserName
       FROM ::fn_trace_gettable(@TraceLocation, DEFAULT) DT
             INNER JOIN sys.trace_events TE
               ON DT.EventClass = TE.trace_event_id
             LEFT OUTER JOIN sys.trace_subclass_values TSV
               ON DT.EventClass = TSV.trace_event_id
                  AND DT.ObjectType = TSV.subclass_value
             INNER JOIN #UnResolvedEvents Work
               ON (Work.ObjectID = DT.ObjectID OR Work.ParentObjectID = DT.ObjectID)
                  AND Work.DatabaseID = DT.DatabaseID
            WHERE TE.name IN ( 'Object:Created', 'Object:Deleted', 'Object:Altered' ) -- TODO These are the only values, right?
                AND DT.EventSubClass = 0
            ORDER BY DT.StartTime ASC
END TRY
BEGIN CATCH
    -- Z50447 catch an error and ignore as this indicates a corrupt trace file on the server
    -- this should not stop the rest of this procedure from happening and should allow us to commit
END CATCH

  -- Not statistics and the information doesn't come from the parent
  UPDATE tempdb.dbo.RG_AllObjects_v4
  SET    UserName  = T.UserName,
         [Matched] = 1
  FROM   tempdb.dbo.RG_AllObjects_v4 RGA
         INNER JOIN #RG_DefaultTraceCache T
            ON RGA.DatabaseID = T.DatabaseID
              AND RGA.ObjectID = T.ObjectID
              AND RGA.ObjectType = T.ObjectType
              AND T.DefaultTraceCacheID =
              (SELECT MAX(DefaultTraceCacheID)
                FROM #RG_DefaultTraceCache
                WHERE
                    DatabaseID = RGA.DatabaseID
                    AND DatabaseName = DB_NAME(RGA.DatabaseID)
                    AND ObjectID = RGA.ObjectID
                    AND ObjectType = RGA.ObjectType
              )
  WHERE  (((T.ActionType IN ( 'Object:Created') OR T.ActionType IN ( 'Object:Altered' )) AND RGA.TypeOfAction = 'Created')
            OR
         (T.ActionType IN ( 'Object:Altered' ) AND RGA.TypeOfAction = 'Modified'))
         AND [Matched] = 0

  UPDATE tempdb.dbo.RG_AllObjects_v4
  SET    UserName  = T.UserName,
         [Matched] = 1
  FROM   tempdb.dbo.RG_AllObjects_v4 RGA
         INNER JOIN #RG_DefaultTraceCache T
           ON RGA.DatabaseID = T.DatabaseID
              AND DB_NAME(RGA.DatabaseID) = T.DatabaseName
              AND RGA.ObjectID = T.ObjectID
  WHERE  (T.ActionType = 'Object:Deleted' AND RGA.TypeOfAction = 'Deleted')
         AND [Matched] = 0

IF @SqlServerVersion > 9
BEGIN
  -- Copy across information for Table Type (SQL Server 2008 onwards)
  UPDATE tempdb.dbo.RG_AllObjects_v4
  SET    UserName   = T.UserName,
         ObjectName = M.ObjectName,
         [Matched]  = 1
  FROM   tempdb.dbo.RG_AllObjects_v4 RGA
         INNER JOIN #Mappings M
           ON M.DatabaseID = RGA.DatabaseID
              AND M.ObjectID = RGA.ObjectID
              AND M.MappingType = RGA.ObjectType
         INNER JOIN #RG_DefaultTraceCache T
           ON T.ObjectID = M.AttributeID
  WHERE  [Matched] = 0
         AND M.DatabaseID = T.DatabaseID
END

  -- Attach the user to the modification of the parent object so that changes
  -- to triggers, indexes etc are attributed to the table properly
  -- NB the child object gets the info direct from the DT (above),
  -- then this moves the info up to the parent so that both have it.
  UPDATE Parent
  SET    UserName  = Child.UserName,
         [Matched] = 1
  FROM   tempdb.dbo.RG_AllObjects_v4 Parent
         INNER JOIN tempdb.dbo.RG_AllObjects_v4 Child
           ON Parent.DatabaseID = Child.DatabaseID
              AND Parent.ObjectID = Child.ParentObjectID
  WHERE  Parent.TypeOfAction IN ('Modified', 'Deleted')
         AND Parent.[Matched] = 0 AND Child.[Matched] = 1


  -- and sometimes it is the other way around.
  UPDATE  Child
  SET     UserName  = Parent.UserName,
          [Matched] = 1
  FROM    tempdb.dbo.RG_AllObjects_v4 Child
          INNER JOIN tempdb.dbo.RG_AllObjects_v4 Parent
            ON Parent.ObjectID = Child.ParentObjectID
               AND Parent.ObjectID = Child.ParentObjectID
  WHERE   Child.[Matched] = 0 AND Parent.[Matched] = 1


END;
/***** END OF SHARED MODEL USERNAME SECTION *****/

/***** RETURN DATA SECTION *****/

-- Select all objects in the RG table where the EntryDateTime is set to later than the SinceWhen value.
-- This means that only new/edited/deleted objects are returned. This determines polled blue blobs and
-- object explorer auto-updating.
SELECT
  DB_NAME(DatabaseID) AS DatabaseName,
  TypeOfAction,
  ObjectType,
  SchemaName,
  ObjectName,
  ParentObjectID,
  UserName
FROM
  tempdb.dbo.RG_AllObjects_v4 RGA
WHERE
  DatabaseID IN (SELECT DatabaseID FROM #DatabaseNameToIdMapping)
  AND EntryDateTime > @SinceWhen

-- Return the latest DateTime value from the RG table. This is then used for the next
-- polling query run to only return entries that have changed since this instance ran.
SELECT @SinceWhen = MAX(EntryDateTime)
FROM   tempdb.dbo.RG_AllObjects_v4

/***** END OF RETURN DATA SECTION *****/
GO
