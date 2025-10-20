CREATE ROLE [PolicyAdministratorRole]
AUTHORIZATION [dbo]
GO
ALTER ROLE [PolicyAdministratorRole] ADD MEMBER [##MS_PolicyEventProcessingLogin##]
GO
ALTER ROLE [PolicyAdministratorRole] ADD MEMBER [##MS_PolicyTsqlExecutionLogin##]
GO
