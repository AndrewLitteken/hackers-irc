defmodule Elixirc.Responses do
	Module.register_attribute(__MODULE__, :server_start_date, presist: true)

	@server_start_date DateTime.utc_now()

	def response_registration() do
    [
      "001 <nick> :Welcome to the elixIRC Network <nick>",
      "002 <nick> :Your host is elixIRC, running version elixIRC-v0.1",
      "003 <nick> :This server was created #{@server_start_date.month}-#{@server_start_date.day}-#{@server_start_date.year} at #{@server_start_date.hour}:#{@server_start_date.minute}:#{@server_start_date.second} UTC",
      "004 <nick> elixIRC elixIRC-v0.1 Oiosw imstn",
      "005 <nick> AWAYLEN=307 CASEMAPPING=ascii CHANLIMIT=#:25 CHANMODES=,,,imstn CHANNELLEN=32 CHANTYPES=# ELIST HOSTLEN=64 KICKLEN=307 NETWORK=HackersNode PREFIX=(o)@ STATUSMSG=@ CHARSET=utf-8 :are supported by this server",
      "005 <nick> TOPICLEN=307 USERLEN=15 :are supppored by this server"
    ] ++ response_LUSERS() ++ response_MOTD()
  end

  def response_LUSERS do
    [] #TODO LUSERS response
  end

  def response_MOTD do
    [
      "375 <nick> :- ElixIRC Message of the day -",
      "372 <nick> :- ElixIRC is the Hackers project of",
      "372 <nick> :- Andrew Litteken, Kyle Miller, and Ethan Williams",
      "376 <nick> :End of /MOTD command."
    ]
  end

  def response_nickclash(key) do
    [
      "433 * #{key} :Nickname already in use"
    ]
  end

  def message_quit() do
  	[
  		"QUIT :Client Quit"
  	]
  end

  def response_quit() do
  	[
  		"ERROR :Closing Link: <hostname> (Client Quit)"
  	]
  end

  def response_unknown(cmd) do
  	[
  		"421 <nick> #{cmd} :Unknown Command"
  	]
  end

  def response_userspec(_params) do
    [
    ]
  end

  def response_nickspec(params) do
    case params do
      ["" | _ ] -> 
        [ "431 <nick> :No nickname given"]
      _ -> 
        [ "432 <nick> :Erroneus nickname" ]
    end 
  end

  def response_nosuchchannel(channel) do
    [
      "403 <nick> #{channel} :No such channel"
    ]
  end

  def response_noreregister() do
    [
      "462 <nick> :You may not reregister"
    ]
  end

end
