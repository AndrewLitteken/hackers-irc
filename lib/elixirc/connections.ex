defmodule Elixirc.Connections do
	use Agent, restart: :temporary
	require Logger

	defstruct registered: false, user: "", host: "", nick: "", realname: "", channels: {}, modes: MapSet.new()

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
			[{_, pid}] = Registry.lookup(Registry.Connections, Map.get(x, :nick))
			Registry.register(Registry.Connections, nick, pid)
			|> case do
				{:ok, _} -> 
					Registry.unregister(Registry.Connections, Map.get(x, :nick))
					Map.put(x, :nick, nick)
				{:error, {:already_registered, _pid}} ->
					x
			end
		end)
	end

	def change_user_mode(connection, modestring, op \\ "add") when modestring != "" do
		case modestring do
			"+"<>rest ->
				change_user_mode(connection, rest, "add")
			"-"<>rest ->
				change_user_mode(connection, rest, "sub")
			nil ->
				modes = Agent.get(connection, &Map.get(&1, :modes))
				{:return, List.to_string(Enum.map(MapSet.to_list(modes), fn n -> to_string(n) end))}
			_ ->
				case op do
					"add" ->
						modes = Agent.get(connection, &Map.get(&1, :modes))
						modes = if not MapSet.member?(modes, String.to_atom(String.at(modestring, 0))) do
							MapSet.put(modes, String.to_atom(String.at(modestring, 0)))
						end
						Agent.update(connection, &Map.put(&1, :modes, modes))
					"sub" ->
						modes = Agent.get(connection, &Map.get(&1, :modes))
						modes = if MapSet.member?(modes, String.to_atom(String.at(modestring, 0))) do
							MapSet.delete(modes, String.to_atom(String.at(modestring, 0)))
						end
						Agent.update(connection, &Map.put(&1, :modes, modes))
				end
				change_user_mode(connection, String.slice(modestring, 1, String.length(modestring)))
		end
	end

	def change_user_mode(_, modestring, _) when modestring == "" do
		{:ok, nil}
	end

	def close(connection) do
		Agent.stop(connection)
	end
end