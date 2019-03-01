defmodule Elixirc do
  require Logger

  def run_server(port) do
    opts = [:binary, packet: :line, active: false, reuseaddr: true]
    {:ok, socket} = :gen_tcp.listen(6667, opts)
    Logger.info("Server Started on Port: #{port}")
    loopaccecpt(socket)
  end

  defp loopaccecpt(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(Elixirc.TaskSupervisor, fn -> Elixirc.serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loopaccecpt(socket)
  end

  def serve(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} -> 
        Logger.info(data)
      {:error, :closed} -> 
        Logger.info("Socket Closed")
        exit(:shutdown)
    end
    serve(socket)
  end
end
