defmodule Elixirc.ChannelListener do
	use Task, restart: :permanent

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
						{:ok, _} = DynamicSupervisor.start_child(Elixirc.ChannelsSupervisor, Elixirc.ChannelState.child_spec(name: name))
						nick = Elixirc.Connections.get(value, :nick)
						user = Elixirc.Connections.get(value, :user)
						host = Elixirc.Connections.get(value, :host)
						Elixirc.ChannelState.put(name, :owner, nick)
						Elixirc.ChannelState.adduser(name, nick)
						send pid, {:outgoing, ":#{nick}!#{user}@#{host} JOIN #{key}\r\n"}
						send pid, {:outgoing, ":elixIRC MODE #{key} +ns\r\n"}
						send pid, {:outgoing, rpl_namereply(name, nick, key)}
						send pid, {:outgoing, ":elixIRC 366 #{nick} #{key} :End of /NAMES list.\r\n"}
					_ ->
						nick = Elixirc.Connections.get(value, :nick)
						user = Elixirc.Connections.get(value, :user)
						host = Elixirc.Connections.get(value, :host)
						Elixirc.ChannelState.adduser(name, nick)
						Enum.each(Registry.lookup(Registry.Channels, key), fn {pid, _value} -> send pid, {:outgoing, "#{nick}!#{user}@#{host} JOIN #{key}\r\n"} end)
						send pid, {:outgoing, rpl_namereply(name, nick, key)}
						send pid, {:outgoing, ":elixIRC 366 #{nick} #{key} :End of /NAMES list.\r\n"}
				end
			{:unregister, _registry, key, _pid, _value} ->
				:ok #delete channel
		end
		listen()
	end

	defp rpl_namereply(channelstate, nick, channelname) do
		#TODO Implement Logic to chekc if channel is public or secret!
		owner = Elixirc.ChannelState.get(channelstate, :owner)
		#TODO Break this up as this will be too much for one command at some point
		users = Enum.join(Elixirc.ChannelState.get(channelstate, :users), " ") |> String.replace(owner, "@"<>owner)
		cond do
			MapSet.member?(Elixirc.ChannelState.get(channelstate,:modes), :s) -> 
				":elixIRC 353 #{nick} @ #{channelname} :#{users}\r\n"
			true ->
				":elixIRC 353 #{nick} = #{channelname} :#{users}\r\n"
		end
	end
end
