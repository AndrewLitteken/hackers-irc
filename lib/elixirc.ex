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
        Logger.info(inspect(Elixirc.Task.MessageParser.call(data)))
        if data == "NICK" do
          # register user
        end
        data
        |> process_message
        |> write_line(socket)
      {:error, :closed} ->
        Logger.info("Socket Closed")
        exit(:shutdown)
    end
    serve(socket)
  end

  defp process_message(data) do
    mapping = Elixirc.Task.MessageParser.call(data)
    #[command | body] = String.split(data)
    #case command do
    case mapping[:command] do
    "PING" -> pong(List.to_string(mapping[:params]))
    #"PING" -> pong(hd(body))
      _ -> "TEST"
    end
  end

  defp pong(body) do
    ":elixIRC PONG elixIRC :" <> body
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line <> "\r\n")
  end
end
