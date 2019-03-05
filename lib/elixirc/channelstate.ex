defmodule Elixirc.ChannelState do
	use Agent, restart: :permanent
	require Logger

	defstruct name: "", modes: MapSet.new([:s, :n]), topic: "", owner: "", users: [], created: DateTime.utc_now()

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
		old_list = get(channel, :users)
		Agent.update(channel, &Map.replace!(&1, :users, [value|old_list]))
	end

	def close(channel) do
		Agent.stop(channel)
	end

	def change_channel_mode(channel, modestring, op \\ "add") when modestring != "" do
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
						modes = Agent.get(channel, &Map.get(&1, :modes))
						modes = MapSet.put(modes, String.at(modestring, 0))
						Agent.update(channel, &Map.put(&1, :modes, modes))
					"sub" ->
						modes = Agent.get(channel, &Map.get(&1, :modes))
						modes = if MapSet.member?(modes, String.to_atom(String.at(modestring, 0))) do
							MapSet.delete(modes, String.to_atom(String.at(modestring, 0)))
						end
						Agent.update(channel, &Map.put(&1, :modes, modes))
				end
				change_channel_mode(channel, String.slice(modestring, 1, String.length(modestring)), op)
		end
	end

	def change_user_mode(_, modestring, _) when modestring == "" do
		{:ok, nil}
	end

end