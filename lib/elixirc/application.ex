defmodule Elixirc.Application do
	use Application

	def start(_type, _args) do
		#List Children and Start them here
		children = [
			{Task.Supervisor, name: Elixirc.TaskSupervisor},
			{DynamicSupervisor, name: Elixirc.ConnectionsSupervisor, strategy: :one_for_one},
			{Elixirc.ChannelListener, name: :ChannelListener},
			{Registry, keys: :unique, listeners: [:ChannelListener], name: Registry.Connections},
			{Registry, keys: :duplicate, listeners: [:ChannelListener], name: Registry.Channels},
			Supervisor.child_spec({Task, fn -> Elixirc.run_server(6667) end}, restart: :permanent),
		]

		opts = [strategy: :one_for_one, name: Elixirc.Supervisor]
		Supervisor.start_link(children, opts)
	end
end
