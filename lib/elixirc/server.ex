defmodule Elixirc.Connections do
	use GenServer
	require Logger

	@doc"""
  	Starts the Connections GenServer
  	"""
  	def start_link(opts) do
		GenServer.start_link(__MODULE__, :ok, opts)
	end

	def run_irc(server) do
		Logger.info("Starting Server")
		GenServer.cast(server, {:run})
	end

	def init(:ok) do
		{:ok, %{}}
	end

	def handle_cast({:run}, %{socket: socket} = state) do
		
	end
end