CREATE ROLE [SQLAgentUserRole]
AUTHORIZATION [dbo]
GO
ALTER ROLE [SQLAgentUserRole] ADD MEMBER [dc_operator]
GO
ALTER ROLE [SQLAgentUserRole] ADD MEMBER [MS_DataCollectorInternalUser]
GO
ALTER ROLE [SQLAgentUserRole] ADD MEMBER [SQLAgentReaderRole]
GO
