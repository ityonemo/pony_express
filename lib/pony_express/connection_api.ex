defmodule PonyExpress.ConnectionAPI do

  @moduledoc false

  @type socket :: :inet.socket | :ssl.sslsocket

  @callback upgrade(:inet.socket, keyword) :: socket
  @callback handshake(:inet.socket, keyword) :: socket
  @callback send(socket, iodata) :: :ok | {:error, any}
  @callback recv(socket, non_neg_integer, timeout) ::
    {:ok, any} | {:error, any}
end
