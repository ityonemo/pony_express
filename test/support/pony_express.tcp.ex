defmodule PonyExpress.Tcp do

  @behaviour PonyExpress.ConnectionAPI

  @impl true
  @spec upgrade(:inet.socket, keyword) :: :inet.socket
  def upgrade(sock, _), do: sock

  @impl true
  @spec handshake(:inet.socket, keyword) :: :inet.socket
  def handshake(sock, _), do: sock

  defdelegate send(sock, content), to: :gen_tcp
  defdelegate recv(sock, size, timeout), to: :gen_tcp

end
