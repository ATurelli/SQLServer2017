CREATE QUEUE [dbo].[syspolicy_event_queue]
WITH STATUS=ON,
RETENTION=OFF,
POISON_MESSAGE_HANDLING (STATUS=ON),
ACTIVATION (
STATUS=ON,
PROCEDURE_NAME=[dbo].[sp_syspolicy_events_reader],
MAX_QUEUE_READERS=1,
EXECUTE AS N'##MS_PolicyEventProcessingLogin##'
)
ON [PRIMARY]
GO
