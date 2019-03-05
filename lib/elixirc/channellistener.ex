defmodule Elixirc.ChannelListener do
	use Task, restart: :permanent

	def start_link(arg) do
    Task.start_link(__MODULE__, :run, [arg])
  end

	def run(arg) do
		Process.register(self(), arg[:name])
		listen()
	end

	def listen() do
		receive do
			{:register, _registry, key, _pid, _value} when ->
				:ok
			{:unregister, _registry, key, _pid, _value} when [] = Registry.lookup(Elixirc.Channels, key) ->
				:ok #delete channel
		end
		listen()
	end
end
