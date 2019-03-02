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
    {:ok, pid} = Task.Supervisor.start_child(Elixirc.TaskSupervisor, fn -> Elixirc.connect(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loopaccecpt(socket)
  end

  def connect(socket) do
    {:ok, useragent} = Agent.start_link fn -> %{user: "", nick: "", realname: "", channels: []} end
    serve(socket, useragent)
  end

  def serve(socket, useragent) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        # Logger.info(data)
        data
        |> process_message(useragent)
        |> write_lines(socket, useragent)
      {:error, :closed} ->
        Logger.info("Socket Closed")
        Agent.stop(useragent)
        exit(:shutdown)
    end
    serve(socket, useragent)
  end

  defp process_message(data, useragent) do
    mapping = Elixirc.Task.MessageParser.call(data)

    case mapping[:command] do
    "NICK" ->
      update_user(useragent, :nick, hd(mapping[:params]))
      []
    "USER" ->
      update_user(useragent, :user, hd(mapping[:params]))
      update_user(useragent, :realname, List.last(mapping[:params]))
      response_registration()
    "PING" -> pong(hd(mapping[:params]))
      _ -> []
    end
  end

  defp update_user(useragent, field, value) do
    Agent.update(useragent, fn state -> %{state | field => value} end)
  end

  defp response_registration() do
    [
      "001 <nick> :Welcome to the elixIRC Network <nick>",
      "002 <nick> :Your host is elixIRC, running version elixIRC-v0.1",
      "003 <nick> :This server was created ???",
      "004 <nick> elixIRC elixIRC-v0.1 ??? ??? ???", #TODO: add user and channel modes
      "005 <nick> CHARSET=utf-8 :are supported by this server" #TODO: add support params
    ] ++ response_LUSERS() ++ response_MOTD()
  end

  defp response_LUSERS do
    [] #TODO LUSERS response
  end

  defp response_MOTD do
    [
      "375 <nick> :- ElixIRC Message of the day -",
      "372 <nick> :- ElixIRC is the Hackers project of",
      "372 <nick> :- Andrew Litteken, Kyle Miller, and Ethan Williams",
      "376 <nick> :End of /MOTD command."
    ]
  end

  defp pong(body) do
    ["PONG elixIRC :" <> body]
  end

  defp write_lines(lines, socket, useragent) do
    nick = Agent.get(useragent, fn state -> state[:nick] end)
    lines
    |> Enum.map(fn x -> String.replace(x, "<nick>", nick) end)
    |> Enum.each(fn x -> :gen_tcp.send(socket, ":elixIRC " <> x <> "\r\n") end)
  end
end
