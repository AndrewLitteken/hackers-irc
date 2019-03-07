defmodule Elixirc.Commands do
	alias Elixirc.Responses, as: Responses
	require Logger

	def handle_nick(new_nick, "" = _old_nick, hostname) do
    name = {:via, Registry, {Registry.Connections, new_nick, self()}}
    Elixirc.Connections.start_link([name: name])
    |> case do
      {:ok, _pid} -> 
        Elixirc.Connections.put(name, :nick, new_nick)
        Elixirc.Connections.put(name, :host, hostname)
        {new_nick, [], "elixIRC"}
      {:error, {:already_started, _pid}} -> {"", Responses.response_nickclash(new_nick), "elixIRC"}
    end
  end

  def handle_nick(new_nick, old_nick, hostname) do
    Registry.lookup(Registry.Connections, new_nick)
    |> case do
      [{_pid, _pid2}] -> {old_nick, Responses.response_nickclash(new_nick), "elixIRC"}
      _ -> 
        Elixirc.Connections.change_nic({:via, Registry, {Registry.Connections, old_nick}}, new_nick)
        if (Elixirc.Connections.get({:via, Registry, {Registry.Connections, new_nick}}, :registered) == true) do
          name = {:via, Registry, {Registry.Connections, new_nick}}
          channels = Registry.keys(Registry.Channels, self())
          user = Elixirc.Connections.get(name, :user)
          hostname = Elixirc.Connections.get(name, :host)
          broadcastlist = MapSet.new(List.flatten(Enum.map(channels, fn name -> Registry.lookup(Registry.Channels, name) end)), fn x -> 
            {pid, _} = x 
            pid 
          end)
          Enum.each(broadcastlist, fn pid -> send pid, {:outgoing, "NICK :#{new_nick}", "#{old_nick}!#{user}@#{hostname}"} end)
          Enum.each(channels, fn chan -> 
            Elixirc.ChannelState.removeuser({:via, Registry, {Registry.ChannelState, chan}}, old_nick)
            Elixirc.ChannelState.adduser({:via, Registry, {Registry.ChannelState, chan}}, new_nick)
            if Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, chan}}, :owner) == old_nick do
              Elixirc.ChannelState.put({:via, Registry, {Registry.ChannelState, chan}}, :owner, new_nick)
            end
          end)
          case channels do 
            [] -> {new_nick, ["NICK :#{new_nick}"], "#{old_nick}!<user>@<hostname>"}
            _ -> {new_nick, [], "#{old_nick}!<user>@<hostname>"}
          end
        else
          Elixirc.Connections.put({:via, Registry, {Registry.Connections, new_nick}}, :registered, true)
          Elixirc.Connections.put({:via, Registry, {Registry.Connections, new_nick}}, :host, hostname)
          {new_nick, Responses.response_registration(), "elixIRC"}
        end
    end
  end
  
  def handle_topic(nick, channel, topic) do
    case Registry.lookup(Registry.Channels, channel) do
      [] ->
        {nick, ["403 #{nick} #{channel} :No such channel"], "elixIRC"}
      _ ->
        topic = case topic do
          ":" <> rest -> rest
          _ -> topic
        end
        case topic do
          [] -> 
            curr_topic = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, channel}}, :topic)
            case curr_topic do
              "" ->
                {:error, {nick, ["331 #{nick} #{channel} :No topic is set"], "elixIRC"}}
              _ ->
                {:personal, "332 #{nick} #{channel} :#{curr_topic}"}
            end
          _ ->
            owner = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, channel}}, :owner)
            modes = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, channel}}, :modes)
            if owner == nick or not MapSet.member?(modes, "t") do
              Elixirc.ChannelState.put({:via, Registry, {Registry.ChannelState, channel}}, :topic, topic)
              {:ok, "332 #{nick} #{channel} :#{topic}"}
            else
              {:error, {nick, ["482 #{nick} #{channel} :You're not channel operator"], "elixIRC"}}
            end
        end
    end
  end 

  def handle_user("" = _nick, username, realname) do
    temp_nick = generate_good_nick()
    name = {:via, Registry, {Registry.Connections, temp_nick, self()}}
    {:ok, _} = Elixirc.Connections.start_link([name: name])
    Elixirc.Connections.put(name, :user, "~"<>username)
    Elixirc.Connections.put(name, :realname, realname)
    Elixirc.Connections.put(name, :nick, temp_nick)
    {temp_nick, [], "elixIRC"}
  end


  def handle_user(nick, username, realname) do
    name = {:via, Registry, {Registry.Connections, nick}}
    if Elixirc.Connections.get(name, :registered) == true do
      {nick, Responses.response_noreregister(), "elixIRC"}
    else
      Elixirc.Connections.put(name, :user, "~"<>username)
      Elixirc.Connections.put(name, :realname, realname)
      Elixirc.Connections.put(name, :registered, true)
      {nick, Responses.response_registration(), "elixIRC"}
    end
  end

  defp add_users_to_message(message, [head | tail], chan_owner) do
    message = if head == chan_owner do
        message <> "@"<>head <> " "
      else
        message <> "" <> head <> " "
    end
    case tail do
      [] -> message
      _ -> add_users_to_message(message, tail, chan_owner)
    end
  end

  def handle_names(nick, channel_list) do
    case channel_list do
      [] ->
        user_list = Registry.keys(Registry.Connections, self())
        Logger.info(inspect(user_list))
        {nick, ["366 #{nick} * :End of /NAMES list"], "elixIRC"}
      _ ->
        channel = hd(channel_list)
        result = Registry.lookup(Registry.Channels, channel)
        case Registry.lookup(Registry.Channels, channel) do 
          [] ->
            {nick, ["403 #{nick} #{channel} :No such channel"], "elixIRC"}
          _ ->
            channel_modes = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, channel}}, :modes)
            users = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, channel}}, :users)
            if not MapSet.member?(channel_modes, "s") or MapSet.member?(users, nick) do
              message = "353 #{nick}"
              message = if MapSet.member?(channel_modes, "s") do
                message <> " @ "
              else
                message <> " = "
              end
              message = message <> channel <> " :"
              user_list = MapSet.to_list(users)
              owner = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, channel}}, :owner)
              message = add_users_to_message(message, user_list, owner)
              {nick, [message, "366 #{nick} #{channel} :End of /NAMES list"], "#{nick}!<user>@<hostname>"}
            else
              {nick, ["442 #{nick} #{channel} :You're not on that channel"], "elixIRC"}
            end
        end
    end
  end

  def handle_join(nick, channelname) do
    [{pid, _}] = Registry.lookup(Registry.Connections, nick)
    channels = Registry.keys(Registry.Channels, self())
    if Enum.member?(channels, channelname) == false do 
      Registry.register(Registry.Channels, channelname, pid)
    end
    {nick, [], "elixIRC"}
  end

  def handle_mode(nick, mode_item, modestring) do
    case mode_item do
      "#" <> _channel ->
        case Registry.lookup(Registry.Channels, mode_item) do
          [] ->
            {nick, ["403 #{nick} #{mode_item} :No such channel"], "elixIRC"}
          _ ->
            oldmodes = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, mode_item}}, :modes)
            result = Elixirc.ChannelState.change_channel_mode({:via, Registry, {Registry.ChannelState, mode_item}}, modestring)
            case result do
              {:ok, nil} ->
                newmodes = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, mode_item}}, :modes)
                added = MapSet.difference(newmodes, oldmodes)
                subtracted = MapSet.difference(oldmodes, newmodes)
                resultstring = cond do
                   MapSet.size(added) > 0 and MapSet.size(subtracted) > 0 -> "+"<>Enum.join(MapSet.to_list(added), "")<>"-"<>Enum.join(MapSet.to_list(subtracted), "")
                   MapSet.size(added) > 0 -> "+"<>Enum.join(MapSet.to_list(added), "")
                   MapSet.size(subtracted) > 0 -> "-"<>Enum.join(MapSet.to_list(subtracted), "")
                   true -> ""
                end
                user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
                hostname = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
                if !MapSet.equal?(oldmodes, newmodes) do
                  broadcast_to_channel({:outgoing, "MODE #{mode_item} #{resultstring}", "#{nick}!#{user}@#{hostname}"}, mode_item)
                end
                {nick, [], "elixIRC"}
              {:return, spec_modes} ->
                created = Elixirc.ChannelState.get_created_time({:via, Registry, {Registry.ChannelState, mode_item}})
                {nick, ["324 #{nick} #{mode_item} +#{spec_modes}", "329 #{nick} #{mode_item} #{created}"], "elixIRC"}
            end
        end
      mode_nick ->
        case Registry.lookup(Registry.Connections, nick) do
          [{_pid, _}] ->
            Logger.info(mode_nick)
            if mode_nick == nick do
                oldmodes = Elixirc.Connections.get({:via, Registry, {Registry.Connections, mode_nick}}, :modes)
                result = Elixirc.Connections.change_user_mode({:via, Registry, {Registry.Connections, mode_nick}}, modestring)
                case result do
                  {:ok, nil} -> 
                    newmodes = Elixirc.Connections.get({:via, Registry, {Registry.Connections, mode_nick}}, :modes)
                    Logger.info(inspect(newmodes))
                    Logger.info(inspect(oldmodes))
                    added = MapSet.difference(newmodes, oldmodes)
                    subtracted = MapSet.difference(oldmodes, newmodes)
                    resultstring = cond do
                      MapSet.size(added) > 0 and MapSet.size(subtracted) > 0 -> "+"<>Enum.join(MapSet.to_list(added), "")<>"-"<>Enum.join(MapSet.to_list(subtracted), "")
                      MapSet.size(added) > 0 -> "+"<>Enum.join(MapSet.to_list(added), "")
                      MapSet.size(subtracted) > 0 -> "-"<>Enum.join(MapSet.to_list(subtracted), "")
                      true -> ""
                    end
                    user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
                    hostname = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
                    if !MapSet.equal?(oldmodes, newmodes) do
                      {nick, ["MODE #{nick} #{resultstring}"], "#{nick}!#{user}@#{hostname}"}
                    else
                      {nick, [], "elixIRC"}
                    end
                  {:return, spec_modes} ->
                    Logger.info(spec_modes)
                    {nick, ["221 #{nick} +#{spec_modes}"], "elixIRC"}
                end
            else
              {nick, ["502 #{nick} :Can't change mode for other users"], "elixIRC"}
            end
          _ ->
            {nick, ["401 #{nick} :No such nick"], "elixIRC"}
        end
    end
  end

  defp generate_good_nick() do
    temp_nick = Elixirc.Randstring.randomizer(20, :downcase)
    case Registry.lookup(Registry.Connections, temp_nick) do
      [{_pid, _pid2}] -> generate_good_nick()
      _ -> temp_nick
    end
  end

  def pong(body) do
    ["PONG elixIRC :" <> body]
  end

  def handle_quit("", socket) do
  	name = {:via, Registry, {Registry.Connections, ""}}
  	Elixirc.write_lines(Responses.response_quit(), socket, name, "")
  	exit(:shutdown)
  end
  
  def handle_quit(nick, socket) do
  	name = {:via, Registry, {Registry.Connections, nick}}
    user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
    hostname = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
    channels = Registry.keys(Registry.Channels, self())
    broadcast_to_all({:outgoing, "QUIT :Client Quit", "#{nick}!#{user}@#{hostname}"}, channels)
    Enum.each(channels, fn x -> Registry.unregister(Registry.Channels, x) end)
  	Elixirc.write_lines(Responses.message_quit(), socket, name, "<nick>!<user>@<hostname>")
  	Elixirc.write_lines(Responses.response_quit(), socket, name, "")
  	Elixirc.Connections.close(name)
  	exit(:shutdown)
  end

  def handle_part(nick, [channelname | tail] = _channels) do
    case Registry.lookup(Registry.Channels, channelname) do
      [] ->
        {:error, "403 #{nick} #{channelname} :No such channel"}
      _ ->
        user = user = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :user)
        host = Elixirc.Connections.get({:via, Registry, {Registry.Connections, nick}}, :host)
        users = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, channelname}}, :users)
        if Enum.find(users, fn x -> x == nick end) != nil do
          broadcast_to_channel({:outgoing, "PART #{channelname}", "#{nick}!#{user}@#{host}"}, channelname)
          leave_channels(nick, [channelname])
          case handle_part(nick, tail) do
            {:ok, "no channels"} -> {:ok, "good"}
            {:error, msg} -> {:error, msg}
          end
        else
          {:error, "442 #{nick} #{channelname} :You're not on that channel"}
        end
    end
  end

  def handle_part(_nick, [] = _channels) do
    {:ok, "no channels"}
  end

  def handle_unknown(nick, cmd) do
  	{nick, Responses.response_unknown(cmd), "elixIRC"}
  end

  def handle_privmsg(nick, target, message) do
    return = case target do
      "#"<>_channel ->
        case Registry.lookup(Registry.Channels, target) do
          [] ->
            {nick, ["403 #{nick} #{target} :No such channel"], "elixIRC"}
          _ ->
            chan_modes = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, target}}, :modes)
            users = Elixirc.ChannelState.get({:via, Registry, {Registry.ChannelState, target}}, :users)
            if not MapSet.member?(chan_modes, "n") or (MapSet.member?(chan_modes, "n") and MapSet.member?(users, nick)) do 
              targets = Registry.lookup(Registry.Channels, target)
              Enum.each(targets, fn {pid, _} -> 
                if pid != self() do
                  send pid, message
                end
              end)
              {:ok, nil}
            else
              {nick, ["404 #{nick} #{target} :Cannot send to channel"], "elixIRC"}
            end
        end
      _ ->
        user_lookup = Registry.lookup(Registry.Connections, target)
        case user_lookup do
          [{_, pid}] ->
            send pid, message
            {:ok, nil}
          [] ->
            {nick, ["403 #{nick} #{target} :No such nick"], "elixIRC"}
        end
    end
    case return do
      {:ok, _} ->
        {nick, [], "elixIRC"}
      _ -> return
    end
  end

  def broadcast_to_channel(message, channel) do
    Enum.each(Registry.lookup(Registry.Channels, channel), fn {pid, _} -> 
      send pid, message 
    end)
  end

  def broadcast_to_all(message, channels) do
    broadcastlist = build_broadcast_list(channels)
    Enum.each(broadcastlist, fn pid -> send pid, message end)
  end

  defp build_broadcast_list(channels) do
    MapSet.new(List.flatten(Enum.map(channels, fn name -> Registry.lookup(Registry.Channels, name) end)), fn {pid, _} -> 
      pid 
    end)
  end

  def leave_channels(nick, channels) do
    Enum.each(channels, fn chan -> 
      Elixirc.ChannelState.removeuser({:via, Registry, {Registry.ChannelState, chan}}, nick)
      Registry.unregister(Registry.Channels, chan)
    end)
  end

end