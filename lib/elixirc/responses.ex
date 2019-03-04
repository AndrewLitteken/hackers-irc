defmodule Elixirc.Responses do
	Module.register_attribute(__MODULE__, :server_start_date, presist: true)

	@server_start_date DateTime.utc_now()

	def response_registration() do
    [
      "001 <nick> :Welcome to the elixIRC Network <nick>",
      "002 <nick> :Your host is elixIRC, running version elixIRC-v0.1",
      "003 <nick> :This server was created #{@server_start_date.month}-#{@server_start_date.day}-#{@server_start_date.year} at #{@server_start_date.hour}:#{@server_start_date.minute}:#{@server_start_date.second} UTC",
      "004 <nick> elixIRC elixIRC-v0.1 ??? ??? ???", #TODO: add user and channel modes
      "005 <nick> CHARSET=utf-8 :are supported by this server" #TODO: add support params
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
end