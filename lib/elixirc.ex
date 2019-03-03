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

  def serve(socket, nick \\ "") do
    nick = case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        {nick, lines} = process_message(data, nick)
        name = {:via, Registry, {Registry.Connections, nick}}
        write_lines(lines, socket, name)
        nick
      {:error, :closed} ->
        if String.length(nick) != 0 do
          Elixirc.Connections.close({:via, Registry, {Registry.Connections, nick}})
        end
        Logger.info("Socket Closed")
        exit(:shutdown)
      {:error, error} ->
        if String.length(nick) != 0 do
          Elixirc.Connections.close({:via, Registry, {Registry.Connections, nick}})
        end
        Logger.info(["Socket Crashed with exit code ", inspect(error)])
        exit(:shutdown)
    end
    serve(socket, nick)
  end

  defp process_message(data, nick) do
    mapping = Elixirc.Task.MessageParser.call(data)
    case mapping[:command] do
    "NICK" ->
      [key | _tail] = mapping[:params]
      if String.length(nick) != 0 do
        Registry.lookup(Registry.Connections, key)
        |> case do
          [{_pid, nil}] -> {nick, response_nickclash(key)}
          _ -> 
            Elixirc.Connections.change_nic({:via, Registry, {Registry.Connections, nick}}, key)
            {key, []}
        end
      else
        name = {:via, Registry, {Registry.Connections, key}}
        DynamicSupervisor.start_child(Elixirc.ConnectionsSupervisor, Elixirc.Connections.child_spec(name: name))
        |> case do
          {:ok, _pid} -> 
            Elixirc.Connections.put(name, :nick, key)
            Logger.info("Got here")
            {key, []}
          {:error, {:already_started, _pid}} -> {nick, response_nickclash(key)}
        end
      end
    "USER" ->
      [head|tail] = mapping[:params]
      name = {:via, Registry, {Registry.Connections, nick}}
      Elixirc.Connections.put(name, :user, head)
      Elixirc.Connections.put(name, :realname, List.last(tail))
      {nick, response_registration()}
    "PING" -> pong(hd(mapping[:params]))
      cmd -> 
        Logger.info("Command #{cmd} Not Handled")
        {nick,[]}
    end
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

  defp response_nickclash(key) do
    [
      "436 #{key} :#{key} already in use"
    ]
  end

  defp pong(body) do
    ["PONG elixIRC :" <> body]
  end

  defp write_lines(lines, socket, name) do
    {:via, Registry, {Registry.Connections, nick}} = name
    if String.length(nick) == 0 do
        lines
        |> Enum.each(fn x -> :gen_tcp.send(socket, ":elixIRC "<>x<>"\r\n") end)
      else
        lines
        |> Enum.map(fn x -> String.replace(x, "<nick>", nick) end)
        |> Enum.each(fn x -> :gen_tcp.send(socket, ":elixIRC " <> x <> "\r\n") end)
    end 
  end
end
