defmodule Elixirc.Connections do
	use Agent, restart: :temporary
	require Logger

	defstruct registered: false, user: "", host: "", nick: "", realname: "", channels: {}, modes: {}

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
				tuple = Agent.get(connection, &Map.get(&1, :modes))
				{:return, List.to_string(Tuple.to_list(tuple))}
			_ ->
				case op do
					"add" ->
						tuple = Agent.get(connection, &Map.get(&1, :modes))
						tuple_string = List.to_string(Tuple.to_list(tuple))
						Logger.info(inspect(tuple))
						tuple = if not String.contains?(tuple_string, String.at(modestring, 0)) do
							Tuple.append(tuple, String.at(modestring, 0))
						else
							tuple
						end
						Logger.info(inspect(tuple))
						Agent.update(connection, &Map.put(&1, :modes, tuple))
					"sub" ->
						tuple = Agent.get(connection, &Map.get(&1, :modes))
						tuple_string = List.to_string(Tuple.to_list(tuple))
						char = String.at(modestring, 0)
						i = if String.contains?(tuple_string, char) do
							Enum.find_index(Tuple.to_list(tuple), fn x -> x == char end)
						end
						tuple = Tuple.delete_at(tuple, i)
						Agent.update(connection, &Map.put(&1, :modes, tuple))
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