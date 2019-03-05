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

end