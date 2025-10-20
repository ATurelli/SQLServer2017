CREATE TABLE [dbo].[#RG_DefaultTraceCache_______________________________________________________________________________________________000000000050]
(
[DefaultTraceCacheID] [int] NOT NULL IDENTITY(1, 1),
[StartTime] [datetime] NULL,
[DatabaseID] [int] NULL,
[DatabaseName] [nvarchar] (128) COLLATE Latin1_General_CI_AS NULL,
[EventSubClass] [int] NULL,
[EventClass] [int] NULL,
[ObjectID] [int] NULL,
[ObjectType] [nvarchar] (128) COLLATE Latin1_General_CI_AS NULL,
[ObjectTypeCode] [int] NULL,
[ActionType] [varchar] (40) COLLATE Latin1_General_CI_AS NULL,
[ObjectName] [nvarchar] (256) COLLATE Latin1_General_CI_AS NULL,
[UserName] [nvarchar] (256) COLLATE Latin1_General_CI_AS NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[#RG_DefaultTraceCache_______________________________________________________________________________________________000000000050] ADD CONSTRAINT [PK__#RG_Defa__264503DB558819B0] PRIMARY KEY NONCLUSTERED ([DefaultTraceCacheID]) ON [PRIMARY]
GO
CREATE CLUSTERED INDEX [#RG_DefaultTraceCache_Index1] ON [dbo].[#RG_DefaultTraceCache_______________________________________________________________________________________________000000000050] ([DatabaseID], [DatabaseName], [ObjectID], [ObjectType]) ON [PRIMARY]
GO
