defmodule Elixirc.Connections do
	use Agent, restart: :temporary
	require Logger

	defstruct user: "", host: "", nick: "", realname: "", channels: []

	@doc"""
  	Starts the Connections Agent
  	"""
  	def start_link(opts) do
		Agent.start_link(fn -> %Elixirc.Connections{} end, opts)
	end

	@doc"""
	Gets a value from the 'connection' by 'key'.
	"""
	def get(connection, key) do
		Agent.get(connection, &Map.get(&1, key))
	end

	@doc"""
	Puts the 'value' for the given 'key' in the 'connection'.
	"""
	def put(connection, key, value) do
		Agent.update(connection, &Map.put(&1, key, value))
	end

	def change_nic(connection, nick) do
		Agent.update(connection, fn x -> 
			Registry.register(Registry.Connections, nick, nil)
			|> case do
				{:ok, _} -> 
					Registry.unregister(Registry.Connections, Map.get(x, :nick))
					Map.put(x, :nick, nick)
				{:error, {:already_registered, pid}} ->
					x
			end
		end)
	end

	def close(connection) do
		Agent.stop(connection)
	end
end