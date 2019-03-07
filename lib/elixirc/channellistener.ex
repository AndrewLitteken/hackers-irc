defmodule Elixirc.ChannelListener do
	use Task, restart: :permanent
	require Logger

	def start_link(arg) do
    Task.start_link(__MODULE__, :run, [arg])
  end

	def run(arg) do
		Process.register(self(), arg[:name])
		listen()
	end

	def listen() do
		receive do
			{:register, _registry, key, pid, value} ->
				name = {:via, Registry, {Registry.ChannelState, key}}
				case Registry.lookup(Registry.Channels, key) do
					[{_,_}] ->
						case DynamicSupervisor.start_child(Elixirc.ChannelsSupervisor, Elixirc.ChannelState.child_spec(name: name)) do
							{:error, {:already_started, _}} -> 
								Elixirc.ChannelState.close(name)
								DynamicSupervisor.start_child(Elixirc.ChannelsSupervisor, Elixirc.ChannelState.child_spec(name: name))
								Logger.info("Channel State Restarted")
							_ ->
								Logger.info("Channel State Created")
						end
						nick = Elixirc.Connections.get(value, :nick)
						user = Elixirc.Connections.get(value, :user)
						host = Elixirc.Connections.get(value, :host)
						Elixirc.ChannelState.put(name, :owner, nick)
						Elixirc.ChannelState.adduser(name, nick)
						send pid, {:outgoing, message_join(key), "#{nick}!#{user}@#{host}"}
						send pid, {:outgoing, "MODE #{key} +ns", "elixIRC"}
						send pid, {:outgoing, rpl_namereply(name, nick, key), "elixIRC"}
						send pid, {:outgoing, message_endnames(nick, key), "elixIRC"}
					_ ->
						nick = Elixirc.Connections.get(value, :nick)
						user = Elixirc.Connections.get(value, :user)
						host = Elixirc.Connections.get(value, :host)
						Elixirc.ChannelState.adduser(name, nick)
						Enum.each(Registry.lookup(Registry.Channels, key), fn {pid, _value} -> send pid, {:outgoing, message_join(key), "#{nick}!#{user}@#{host}"} end)
						send pid, {:outgoing, rpl_namereply(name, nick, key), "elixIRC"}
						send pid, {:outgoing, message_endnames(nick, key), "elixIRC"}
				end
			{:unregister, _registry, key, _pid} ->
				name = {:via, Registry, {Registry.ChannelState, key}}
				case Registry.lookup(Registry.Channels, key) do
					[] ->
						Elixirc.ChannelState.close(name)
				end
			anything_else ->
				Logger.info(inspect(anything_else))
		end
		listen()
	end

	defp rpl_namereply(channelstate, nick, channelname) do
		owner = Elixirc.ChannelState.get(channelstate, :owner)
		#TODO Break this up as this will be too much for one command at some point
		users = Enum.join(Elixirc.ChannelState.get(channelstate, :users), " ") |> String.replace(owner, "@"<>owner)
		cond do
			MapSet.member?(Elixirc.ChannelState.get(channelstate,:modes), "s") ->
				 "353 #{nick} @ #{channelname} :#{users}"
			true ->
				"353 #{nick} = #{channelname} :#{users}"
		end
	end

	defp message_join(channelname) do
		"JOIN #{channelname}"
	end

	defp message_endnames(nick, channelname) do
		"366 #{nick} #{channelname} :End of /NAMES list."
	end


end
