-- No real RabbitMQ plugin ecosystem exists for nvim. The practical workflow
-- is .http files against the management API (http://localhost:15672/api/...)
-- via kulala in tools.lua, and `rabbitmqadmin`/`rabbitmqctl` in a terminal.
return {}
