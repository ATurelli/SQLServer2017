CREATE TABLE [dbo].[#CurrentDatabaseObjects_____________________________________________________________________________________________00000000004F]
(
[DatabaseID] [int] NULL,
[ObjectType] [char] (2) COLLATE Latin1_General_CI_AS NULL,
[ObjectID] [int] NULL,
[SchemaName] [sys].[sysname] NULL,
[ObjectName] [sys].[sysname] NOT NULL,
[ModifyDate] [datetime] NULL,
[ParentObjectID] [int] NULL,
[ParentObjectName] [sys].[sysname] NULL,
[ParentObjectType] [char] (2) COLLATE Latin1_General_CI_AS NULL
) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IdxCurrentDatabaseObjects] ON [dbo].[#CurrentDatabaseObjects_____________________________________________________________________________________________00000000004F] ([DatabaseID], [ObjectID], [ObjectType]) ON [PRIMARY]
GO
