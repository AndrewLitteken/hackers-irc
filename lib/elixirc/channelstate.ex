defmodule Elixirc.ChannelState do
	use Agent, restart: :temporary
	require Logger

	defstruct name: "", mode: MapSet.new([:secret, :noexternal]), topic: ""

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

	def close(channel) do
		Agent.stop(channel)
	end

end