defmodule PonyExpress.Tls do

  @behaviour PonyExpress.ConnectionAPI

  @client_cacert Path.expand("./test_ssl_assets/rootCA.pem")
  @client_cert Path.expand("./test_ssl_assets/client.cert")
  @client_key Path.expand("./test_ssl_assets/client.key")

  @server_cacert Path.expand("./test_ssl_assets/rootCA.pem")
  @server_cert Path.expand("./test_ssl_assets/server.cert")
  @server_key Path.expand("./test_ssl_assets/server.key")

  @spec upgrade(:inet.socket) :: :ssl.sslsocket
  def upgrade(sock) do
    case :ssl.connect(sock,
      cacertfile: @client_cacert,
      certfile: @client_cert,
      keyfile: @client_key) do

    {:ok, sock} -> sock
    _ -> raise "ssl socket upgrade error"
    end
  end

  @spec handshake(:inet.socket) :: :ssl.sslsocket
  def handshake(sock) do
    case :ssl.handshake(sock,
      cacertfile: @server_cacert,
      certfile: @server_cert,
      keyfile: @server_key,
      verify: :verify_peer,
      fail_if_no_peer_cert: true) do
    {:ok, sock} -> sock
    _ -> raise "ssl handshake error"
    end
  end

  defdelegate send(sock, content), to: :ssl
  defdelegate recv(sock, size, timeout), to: :ssl

end
