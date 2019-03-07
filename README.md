# Elixirc

## Goals and Description

### Functionality

The purpose of this project was to build an IRC Server that supports the basic functions of an IRC server plus a subset of the commands that are supported in a normal IRC client.  We support the following command:

- NICK
- USER
- PRVMSG (between individual users and between channels)
- JOIN
- PART
- TOPIC
- NAMES
- PING
- PONG
- QUIT

### Language and Usage

This is built with the Elixir lanuage, which is a functional programming lanugage that utilizes the Erlang VM to run a highly concurrent environment to run individual tasks, supervisors, state agents and processes.

We make extensive use of the concurrent process-oriented nature of the Elixir language by creating a Registry process that contains a mapping to an Agent process for each user to maintain TCP Connections, two Registry processes for channels, one for state and one for mapping to process ids. Additionally, we use supervisor task processes to ensure that a lost connection or erorr will not bring down the entire server as well as to ensure that messages are sent to each channel as needed.

We also make use of the "Domain Specific Language" nature of the language, by using regular expressions and various data structures to encode information in a such a way, that it can easily create rules to parse and validate the commands that are input from the IRC clients.

## Installation

To install this server, simply clone the repository, then from the top level directory run `mix run --no-halt`.  This will start the server listening on port 6667.
