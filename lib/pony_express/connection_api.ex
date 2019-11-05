defmodule PonyExpress.ConnectionAPI do

  @type socket :: :inet.socket | :ssl.sslsocket

  @callback upgrade(:inet.socket) :: socket
  @callback handshake(:inet.socket) :: socket
  @callback send(socket, iodata) :: :ok | {:error, any}
  @callback recv(socket, non_neg_integer, timeout) ::
    {:ok, any} | {:error, any}
end
