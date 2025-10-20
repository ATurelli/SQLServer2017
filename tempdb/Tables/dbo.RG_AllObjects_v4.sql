CREATE TABLE [dbo].[RG_AllObjects_v4]
(
[AllObjectsID] [int] NOT NULL IDENTITY(1, 1),
[EntryDateTime] [datetime] NULL,
[DatabaseID] [int] NULL,
[ObjectType] [char] (2) COLLATE Latin1_General_CI_AS NULL,
[ObjectID] [int] NOT NULL,
[SchemaName] [sys].[sysname] NULL,
[ObjectName] [sys].[sysname] NOT NULL,
[ModifyDate] [datetime] NULL,
[ParentObjectID] [int] NULL,
[ParentObjectName] [sys].[sysname] NULL,
[ParentObjectType] [char] (2) COLLATE Latin1_General_CI_AS NULL,
[TypeOfAction] [varchar] (20) COLLATE Latin1_General_CI_AS NOT NULL CONSTRAINT [DF__RG_AllObj__TypeO__3A81B327] DEFAULT ('Existing'),
[Matched] [int] NOT NULL CONSTRAINT [DF__RG_AllObj__Match__3B75D760] DEFAULT ((0)),
[UserName] [nvarchar] (256) COLLATE Latin1_General_CI_AS NULL
) ON [PRIMARY]
GO
CREATE CLUSTERED INDEX [IdxObjectType] ON [dbo].[RG_AllObjects_v4] ([DatabaseID], [ObjectID], [ObjectType]) ON [PRIMARY]
GO
