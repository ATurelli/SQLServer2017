CREATE USER [MS_DataCollectorInternalUser] WITHOUT LOGIN
GO
GRANT IMPERSONATE ON USER:: [MS_DataCollectorInternalUser] TO [dc_admin]
GO
