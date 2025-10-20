CREATE TYPE [dbo].[syspolicy_target_filters_type] AS TABLE
(
[target_filter_id] [int] NULL,
[policy_id] [int] NULL,
[type] [sys].[sysname] NOT NULL,
[filter] [nvarchar] (max) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
[type_skeleton] [sys].[sysname] NOT NULL
)
GO
