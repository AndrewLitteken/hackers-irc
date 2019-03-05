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
        {nick, lines, source} = process_message(data, nick, socket)
        name = {:via, Registry, {Registry.Connections, nick}}
        write_lines(lines, socket, name, source)
        nick
      {:tcp_close, _port} ->
        if String.length(nick) != 0 do
          Enum.each(Registry.keys(Registry.Channels, self()), fn x -> Registry.unregister(Elixirc.Channels, x) end)
          Elixirc.Connections.close({:via, Registry, {Registry.Connections, nick}})
        end
        Logger.info("Socket Closed")
        exit(:shutdown)
      {:outgoing, data} ->
        :gen_tcp.send(socket, data)
        nick
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
    Logger.info(mapping[:command])
    case mapping[:command] do
      "NICK" ->
        result = Elixirc.Validate.validate mapping[:params], [{:pattern, "^[^ :,]+$"}]
        case result do
          {:ok, _} ->
            [key|_tail] = mapping[:params]
            hostname = List.to_string(resolve_hostname(socket))
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
            Commands.handle_join(nick, head)
          {:error, _} ->
            {nick, Elixirc.Responses.response_nosuchchannel(mapping[:params]), "elixIRC"}
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
            Commands.handle_mode(nick, head, List.first(tail))
          {:error, _} ->
            #{"", Elixirc.Responses.response_modespec(mapping[:params]), "elixIRC"}
            {nick, ["400 #{nick}!<user>@<hostname> :Unknown error for MODE"], ""}
        end
      "FAIL" -> 1 + []
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
        Enum.join(Tuple.to_list(ip), ".")
    end
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
        |> Enum.map(fn x -> String.replace(x, "<nick>", nick) |> String.replace("<hostname>", Elixirc.Connections.get(name, :host)) end)
        |> Enum.each(fn x -> :gen_tcp.send(socket, x<>"\r\n") end)
      true ->
        lines
        |> Enum.map(fn x -> String.replace(x, "<nick>", nick) |> String.replace("<hostname>", Elixirc.Connections.get(name, :host)) end)
        |> Enum.each(fn x -> :gen_tcp.send(socket, ":"<>source<>" "<>x<>"\r\n") end)
    end
  end
end
