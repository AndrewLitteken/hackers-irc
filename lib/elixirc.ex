defmodule Elixirc do
  require Logger
  alias Elixirc.Commands, as: Commands

  def run_server(port) do
    opts = [:binary, packet: :line, active: true, reuseaddr: true]
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

    nick = receive do
      {:tcp, _port, data} ->
        Logger.info(data)
        {nick, lines, source} = process_message(data, nick, socket)
        name = {:via, Registry, {Registry.Connections, nick}}
        write_lines(lines, socket, name, source)
        nick
      {:tcp_closed, _port} ->
        if String.length(nick) != 0 do
          user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
          hostname = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
          channels = Registry.keys(Registry.Channels, self())
          Commands.broadcast_to_all({:outgoing, "QUIT :Remote host closed the connection", "#{nick}!#{user}@#{hostname}"}, channels)
          Commands.leave_channels(nick, channels)
          Elixirc.Connections.close({:via, Registry, {Registry.Connections, nick}})
        end
        Logger.info("Socket Closed")
        exit(:shutdown)
      {:outgoing, data, source} ->
        write_message(socket, data, source)
        nick
      {:error, error} ->
        if String.length(nick) != 0 do
          user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
          hostname = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
          channels = Registry.keys(Registry.Channels, self())
          reason = Atom.to_string(error)
          Commands.broadcast_to_all({:outgoing, "QUIT :#{reason}", "#{nick}!#{user}@#{hostname}"}, channels)
          Commands.leave_channels(nick, channels)
          Elixirc.Connections.close({:via, Registry, {Registry.Connections, nick}})
        end
        Logger.info(["Socket Crashed with exit code ", inspect(error)])
        exit(:shutdown)
      cmd -> 
        Logger.info(inspect(cmd))
    end
    serve(socket, nick)
  end

  defp process_message(data, nick, socket) do
    mapping = Elixirc.Task.MessageParser.call(data)
    Logger.info(mapping[:command])
    case mapping[:command] do
      "NICK" ->
        result = Elixirc.Validate.validate mapping[:params], [{:pattern, "^[^ :,]+$"}]
        case result do
          {:ok, _} ->
            [key|_tail] = mapping[:params]
            hostname = List.to_string(resolve_hostname(socket))
            key = String.downcase(key)
            Commands.handle_nick(key, nick, hostname)
          {:error, _}  ->
            {nick, Elixirc.Responses.response_nickspec(mapping[:params]), "elixIRC"}
        end
      "USER" ->
         result = Elixirc.Validate.validate mapping[:params], [{:pattern, "^[^ :,]+$"}, {:pattern, ".*"}, {:pattern, ".*"}, {:pattern, "^[^:,]+$"}]
         case result do
           {:ok, _} ->
             [head|tail] = mapping[:params]
             Commands.handle_user(nick, head, List.last(tail))
           {:error, _} ->
            {nick, Elixirc.Responses.response_userspec(mapping[:params]), "elixIRC"}
          end
      "JOIN" ->
        result = Elixirc.Validate.validate mapping[:params], [{:pattern, "^#[^:, ]*"}]
        case result do
          {:ok, _} ->
            [head|_tail] = mapping[:params]
            head = String.downcase(head)
            result = Commands.handle_join(nick, String.split(head, ","))
            case result do
              {:ok, _} -> {nick, [], "elixIRC"}
              {:err, msg} -> {nick, [msg], "elixIRC"}
            end
          {:error, _} ->
            {nick, Elixirc.Responses.response_nosuchchannel(mapping[:params]), "elixIRC"}
        end
      "PART" ->
        result = Elixirc.Validate.validate mapping[:params], [{:pattern, "^#[^: ,]+(,#[^: ]+)*$"}, {:option, {:pattern, ".*"}}]
        case result do
          {:ok, _} ->
            [head|_tail] = mapping[:params]
            head = String.downcase(head)
            case Commands.handle_part(nick, String.split(head, ",")) do
              {:ok, _} -> {nick, [], "elixIRC"}
              {:error, msg} -> {nick, [msg], "elixIRC"}
            end
          {:error, msg} ->
            {nick, [msg], "elixIRC"}
        end
      "TOPIC" ->
        result = Elixirc.Validate.validate mapping[:params], [{:pattern, "#[^: ,]+"}, {:option, {:pattern, ".*"}}]
        case result do
          {:ok, _} ->
            [head|tail] = mapping[:params]
            Logger.info(inspect(tail))
            head = String.downcase(head)
            result_value = Commands.handle_topic(nick, head, tail)
            user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
            hostname = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
            case result_value do
              {:ok, send_msg} ->
                Commands.broadcast_to_channel({:outgoing, send_msg, "#{nick}!#{user}@#{hostname}"}, head)
                {nick, [], "elixIRC"}
              {:error, msg} -> 
                msg
              {:personal, msg} ->
                {nick, [msg], "elixIRC"}
            end
          {:error, _} ->
            {nick, ["461 #{nick} TOPIC :Not enough parameters"], "elixIRC"}
        end
      "PRIVMSG" ->
        result = Elixirc.Validate.validate mapping[:params], [{:pattern, ".*"}, {:pattern, ".*"}]
        case result do
          {:ok, _} ->
            [target|data] = mapping[:params]
            Logger.info("Message is #{data}")
            target = String.downcase(target)
            user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
            host = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
            Commands.handle_privmsg(nick, target, {:outgoing, "PRIVMSG #{target} :"<>hd(data), "#{nick}!#{user}@#{host}"})
          {:error, msg} ->
            {nick, [msg], "elixIRC"}
        end
      "NOTICE" ->
        result = Elixirc.Validate.validate mapping[:params], [{:pattern, ".*"}, {:pattern, ".*"}]
        case result do
          {:ok, _} ->
            [target|data] = mapping[:params]
            Logger.info("Message is #{data}")
            target = String.downcase(target)
            user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
            host = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
            Commands.handle_privmsg(nick, target, {:outgoing, "NOTICE #{target} :"<>hd(data), "#{nick}!#{user}@#{host}"})
          {:error, msg} ->
            {nick, [msg], "elixIRC"}
        end
      "PING" -> {nick, Commands.pong(hd(mapping[:params])), "elixIRC"}
      "PONG" ->
        Logger.info("Received PONG from Client - Doing nothing about this at the moment")
        {nick, [], "elixIRC"}
      "MODE" ->
        result = Elixirc.Validate.validate mapping[:params], [{:pattern, "^(#)?[^ :,]+$"}, {:option, {:pattern, "^(\\+|\\-)[a-zA-Z]+$"}}]
        case result do
          {:ok, _} ->
            [head|tail] = mapping[:params]
            head = String.downcase(head)
            Commands.handle_mode(nick, head, List.first(tail))
          {:error, _} ->
            {nick, ["400 #{nick}!<user>@<hostname> :Unknown error for MODE"], "elixIRC"}
        end
      "NAMES" ->
        result = Elixirc.Validate.validate mapping[:params], [{:option, {:pattern, "#[^: ,]+"}}]
        Logger.info(inspect(result))
        case result do
          {:ok, _} ->
            Commands.handle_names(nick, mapping[:params])
          {:error, _} ->
            {nick, ["400 #{nick}!<user>@<hostname> :Unknown error for NAMES"], "elixIRC"}
        end  
      "PASS" ->
        Logger.info("Received PASS from Client - Ignoring for now")
        {nick, [], "elixIRC"}
      "QUIT" -> Commands.handle_quit(nick, socket)
      cmd ->
        Logger.info("Command #{cmd} Not Handled")
        Commands.handle_unknown(nick, cmd)
    end
  end

  defp resolve_hostname(client) do
    {:ok, {ip, _port}} = :inet.peername(client)
    case :inet.gethostbyaddr(ip) do
      {:ok, {:hostent, hostname, _, _, _, _}} ->
        hostname
      {:error, _error} ->
        Logger.info("Falling back to ip address")
        [Enum.join(Tuple.to_list(ip), ".")]
    end
  end

  def write_message(socket, data, source) do
    :gen_tcp.send(socket, ":"<>source<>" "<>data<>"\r\n")
  end

  def write_lines(lines, socket, {:via, Registry, {Registry.Connections, ""}} = _name, source) do
    cond do
      source == "" -> lines |> Enum.each(fn x -> :gen_tcp.send(socket, x<>"\r\n") end)
      true -> lines |> Enum.each(fn x -> :gen_tcp.send(socket, ":"<>source<>" "<>x<>"\r\n") end)
    end
  end

  def write_lines(lines, socket, {:via, Registry, {Registry.Connections, nick}} = name, source) do
    source = String.replace(source, "<user>", Elixirc.Connections.get(name, :user)) |> String.replace("<hostname>", Elixirc.Connections.get(name, :host)) |> String.replace("<nick>", Elixirc.Connections.get(name, :nick))
    cond do
      source == "" ->
        lines
        |> Enum.map(fn x -> String.replace(x, "<nick>", nick) |> String.replace("<hostname>", Elixirc.Connections.get(name, :host)) |> String.replace("<user>", Elixirc.Connections.get(name, :user)) end)
        |> Enum.each(fn x -> :gen_tcp.send(socket, x<>"\r\n") end)
      true ->
        lines
        |> Enum.map(fn x -> String.replace(x, "<nick>", nick) |> String.replace("<hostname>", Elixirc.Connections.get(name, :host)) |> String.replace("<user>", Elixirc.Connections.get(name, :user)) end)
        |> Enum.each(fn x -> :gen_tcp.send(socket, ":"<>source<>" "<>x<>"\r\n") end)
    end
  end
end
