defmodule PonyExpress.Tls do

  @moduledoc """
  default module for dropping in TLS over the erlang sockets library.

  the TLS protocol has a very convienient way of upgrading to an SSL
  connection.  This enables the use of the common `:gen_tcp` library except:

  - on the server side, a `handshake` directive allows the client to negotiate
  an upgrade to a secure `tls` connection.  Although tls does support one-way
  encryption, since `PonyExpress` requires two-way encryption, the handshake
  enforces peer verfication.

  - on the client side, an `upgrade` directive which negotiates an unencrypted
  `:tcp` socket's connection to an encrypted `tls` connection.
  """

  @behaviour PonyExpress.ConnectionAPI

  @spec upgrade(:inet.socket, keyword) :: :ssl.sslsocket
  def upgrade(sock, ssl_opts) do
    case :ssl.connect(sock, ssl_opts) do

    {:ok, sock} -> sock
    _ -> raise "ssl socket upgrade error"
    end
  end

  @spec handshake(:inet.socket, keyword) :: :ssl.sslsocket
  def handshake(sock, ssl_opts) do
    case :ssl.handshake(sock,
      ssl_opts ++ [
      verify: :verify_peer,
      fail_if_no_peer_cert: true]) do
    {:ok, sock} -> sock
    _ -> raise "ssl handshake error"
    end
  end

  defdelegate send(sock, content), to: :ssl
  defdelegate recv(sock, size, timeout), to: :ssl

end
