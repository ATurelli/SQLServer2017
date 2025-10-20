SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

CREATE VIEW [dbo].[sysdtslog90]
AS
	SELECT [id]
		  ,[event]
		  ,[computer]
		  ,[operator]
		  ,[source]
		  ,[sourceid]
		  ,[executionid]
		  ,[starttime]
		  ,[endtime]
		  ,[datacode]
		  ,[databytes]
		  ,[message]
	  FROM [msdb].[dbo].[sysssislog]

GO
