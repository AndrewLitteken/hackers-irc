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
        {nick, lines, source} = process_message(data, nick, socket)
        name = {:via, Registry, {Registry.Connections, nick}}
        write_lines(lines, socket, name, source)
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

  defp process_message(data, nick, socket) do
    mapping = Elixirc.Task.MessageParser.call(data)
    case mapping[:command] do
      "NICK" ->
        [key|_tail] = mapping[:params]
        hostname = List.to_string(resolve_hostname(socket))
        Logger.info("Hostname is #{hostname}")
        handle_nick(key, nick, hostname)
      "USER" ->
        [head|tail] = mapping[:params]
        handle_user(nick, head, List.last(tail))
      "PING" -> {nick, pong(hd(mapping[:params])), "elixIRC"}
      "FAIL" -> 1 + []
      cmd -> 
        Logger.info("Command #{cmd} Not Handled")
        {nick,[], "elixIRC"}
    end
  end

  defp handle_nick(new_nick, "" = _old_nick, hostname) do
    name = {:via, Registry, {Registry.Connections, new_nick}}
    Elixirc.Connections.start_link([name: name])
    |> case do
      {:ok, _pid} -> 
        Elixirc.Connections.put(name, :nick, new_nick)
        Elixirc.Connections.put(name, :host, hostname)
        {new_nick, [], "elixIRC"}
      {:error, {:already_started, _pid}} -> {"", response_nickclash(new_nick), "elixIRC"}
    end
  end

  defp handle_nick(new_nick, old_nick, _hostname) do
    Registry.lookup(Registry.Connections, new_nick)
    |> case do
      [{_pid, nil}] -> {old_nick, response_nickclash(new_nick), "elixIRC"}
      _ -> 
        Elixirc.Connections.change_nic({:via, Registry, {Registry.Connections, old_nick}}, new_nick)
        if (Elixirc.Connections.get({:via, Registry, {Registry.Connections, new_nick}}, :registered) == true) do
          {new_nick, ["NICK :#{new_nick}"], "#{old_nick}!<user>@<hostname>"}
        else
          Elixirc.Connections.put({:via, Registry, {Registry.Connections, new_nick}}, :registered, true)
          {new_nick, response_registration(), "elixIRC"}
        end
    end
  end

  defp handle_user("" = _nick, username, realname) do
    temp_nick = generate_good_nick()
    name = {:via, Registry, {Registry.Connections, temp_nick}}
    {:ok, _pid} = Elixirc.Connections.start_link([name: name])
    Elixirc.Connections.put(name, :user, "~"<>username)
    Elixirc.Connections.put(name, :realname, realname)
    {temp_nick, [], "elixIRC"}
  end

  defp handle_user(nick, username, realname) do
    name = {:via, Registry, {Registry.Connections, nick}}
    Elixirc.Connections.put(name, :user, "~"<>username)
    Elixirc.Connections.put(name, :realname, realname)
    Elixirc.Connections.put(name, :registered, true)
    {nick, response_registration(), "elixIRC"}
  end

  defp generate_good_nick() do
    temp_nick = Elixirc.Randstring.randomizer(20, :downcase)
    case Registry.lookup(Registry.Connections, temp_nick) do
      {:ok, _pid} -> generate_good_nick()
      _ -> temp_nick
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
      "433 * #{key} :Nickname already in use"
    ]
  end

  defp pong(body) do
    ["PONG elixIRC :" <> body]
  end

  defp resolve_hostname(client) do
    {:ok, {ip, _port}} = :inet.peername(client)
    case :inet.gethostbyaddr(ip) do
      {:ok, {:hostent, hostname, _, _, _, _}} ->
        hostname
      {:error, _error} ->
        Logger.info("Falling back to ip address")
        Enum.join(Tuple.to_list(ip), ".")
    end
  end

  defp write_lines(lines, socket, {:via, Registry, {Registry.Connections, ""}} = _name, source) do
    lines
    |> Enum.each(fn x -> :gen_tcp.send(socket, ":"<>source<>" "<>x<>"\r\n") end)
  end

  defp write_lines(lines, socket, {:via, Registry, {Registry.Connections, nick}} = name, source) do
      source = String.replace(source, "<user>", Elixirc.Connections.get(name, :user))
      source = String.replace(source, "<hostname>", Elixirc.Connections.get(name, :host))
      source = String.replace(source, "<nick>", Elixirc.Connections.get(name, :nick))
      lines
      |> Enum.map(fn x -> String.replace(x, "<nick>", nick) end)
      |> Enum.each(fn x -> :gen_tcp.send(socket, ":"<>source<>" "<>x<>"\r\n") end) 
  end
end
