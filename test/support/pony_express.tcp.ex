defmodule PonyExpress.Tcp do

  @behaviour PonyExpress.ConnectionAPI

  def upgrade(sock), do: sock
  def handshake(sock), do: sock

  defdelegate send(sock, content), to: :gen_tcp
  defdelegate recv(sock, size, timeout), to: :gen_tcp

end
