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
			cmd -> IO.puts(inspect cmd)
		end
		listen()
	end
end
