defmodule Elixirc.Commands do
	alias Elixirc.Responses, as: Responses
	
	def handle_nick(new_nick, "" = _old_nick, hostname) do
    name = {:via, Registry, {Registry.Connections, new_nick}}
    Elixirc.Connections.start_link([name: name])
    |> case do
      {:ok, _pid} -> 
        Elixirc.Connections.put(name, :nick, new_nick)
        Elixirc.Connections.put(name, :host, hostname)
        {new_nick, [], "elixIRC"}
      {:error, {:already_started, _pid}} -> {"", Responses.response_nickclash(new_nick), "elixIRC"}
    end
  end

  def handle_nick(new_nick, old_nick, _hostname) do
    Registry.lookup(Registry.Connections, new_nick)
    |> case do
      [{_pid, nil}] -> {old_nick, Responses.response_nickclash(new_nick), "elixIRC"}
      _ -> 
        Elixirc.Connections.change_nic({:via, Registry, {Registry.Connections, old_nick}}, new_nick)
        if (Elixirc.Connections.get({:via, Registry, {Registry.Connections, new_nick}}, :registered) == true) do
          {new_nick, ["NICK :#{new_nick}"], "#{old_nick}!<user>@<hostname>"}
        else
          Elixirc.Connections.put({:via, Registry, {Registry.Connections, new_nick}}, :registered, true)
          {new_nick, Responses.response_registration(), "elixIRC"}
        end
    end
  end

  def handle_user("" = _nick, username, realname) do
    temp_nick = generate_good_nick()
    name = {:via, Registry, {Registry.Connections, temp_nick}}
    {:ok, _pid} = Elixirc.Connections.start_link([name: name])
    Elixirc.Connections.put(name, :user, "~"<>username)
    Elixirc.Connections.put(name, :realname, realname)
    {temp_nick, [], "elixIRC"}
  end

  def handle_user(nick, username, realname) do
    name = {:via, Registry, {Registry.Connections, nick}}
    Elixirc.Connections.put(name, :user, "~"<>username)
    Elixirc.Connections.put(name, :realname, realname)
    Elixirc.Connections.put(name, :registered, true)
    {nick, Responses.response_registration(), "elixIRC"}
  end

  defp generate_good_nick() do
    temp_nick = Elixirc.Randstring.randomizer(20, :downcase)
    case Registry.lookup(Registry.Connections, temp_nick) do
      {:ok, _pid} -> generate_good_nick()
      _ -> temp_nick
    end
  end

  def pong(body) do
    ["PONG elixIRC :" <> body]
  end

end