defmodule Elixirc.ChannelState do
	use Agent, restart: :temporary
	require Logger

	defstruct name: "", modes: MapSet.new(["s", "n"]), topic: "", owner: "", users: MapSet.new(), created: DateTime.utc_now()

	@doc"""
	Starts the Channel State Agent
	"""
	def start_link(opts) do
		Agent.start_link(fn -> %Elixirc.ChannelState{} end, opts)
	end

	@doc"""
	Gets `value` for given `key` in ChannelState
	"""
	def get(channel, key) do
		Agent.get(channel, &Map.get(&1, key))
	end

	@doc"""
	Puts the given `value` in specified `key`
	"""
	def put(channel, key, value) do
		Agent.update(channel, &Map.put(&1, key, value))
	end

	def adduser(channel, value) do
		Agent.update(channel, fn state ->
			Map.replace!(state, :users, MapSet.put(Map.get(state, :users), value))
		end)
	end

	def removeuser(channel, value) do
		Agent.update(channel, fn state ->
			Map.replace!(state, :users, MapSet.delete(Map.get(state, :users), value))
		end)
	end

	def addmode(channel, value) do
		Agent.update(channel, fn state ->
			Map.replace!(state, :modes, MapSet.put(Map.get(state, :modes), value))
		end)
	end

	def removemode(channel, value) do
		Agent.update(channel, fn state ->
			Map.replace!(state, :modes, MapSet.delete(Map.get(state, :modes), value))
		end)
	end

	def get_created_time(channel) do
		Agent.get(channel, &Map.get(&1, :created)) |> DateTime.to_unix()
	end

	def close(channel) do
		Agent.stop(channel)
	end

	def change_channel_mode(channel, modestring, op \\ "add")

	def change_channel_mode(channel, modestring, op) when modestring != "" do
		Logger.info(modestring)
		case modestring do
			"+"<>rest ->
				change_channel_mode(channel, rest, "add")
			"-"<>rest ->
				change_channel_mode(channel, rest, "sub")
			nil ->
				modes = Agent.get(channel, &Map.get(&1, :modes))
				{:return, List.to_string(Enum.map(MapSet.to_list(modes), fn n -> to_string(n) end))}
			_ ->
				case op do
					"add" ->
						addmode(channel, String.at(modestring, 0))
					"sub" ->
						removemode(channel, String.at(modestring, 0))
				end
				change_channel_mode(channel, String.slice(modestring, 1, String.length(modestring)), op)
		end
	end

	def change_channel_mode(_, modestring, _) when modestring == "" do
		{:ok, nil}
	end

end