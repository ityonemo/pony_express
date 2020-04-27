defmodule PonyExpress.Packet do

  @magic_cookie <<1860::16, 1861::16>>
  @full_packet_timeout 500

  def get_data(transport, socket, timeout \\ 100) do
    case transport.recv(socket, 0, timeout) do
      {:ok, @magic_cookie <> <<size::32>> <> rest} when :erlang.size(rest) < size ->
        get_more(transport, socket, rest, size)
      {:ok, @magic_cookie <> <<size::32>> <> rest} when :erlang.size(rest) == size ->
        term = Plug.Crypto.non_executable_binary_to_term(rest, [:safe])
        {:ok, term}
      {:ok, _} ->
        {:error, :einval}
      error -> error
    end

  catch
    # return unsafe arguments as badarg.
    :error, :badarg ->
      {:error, :badarg}
  end

  defp get_more(transport, socket, first, size) do
    leftover_size = size - :erlang.size(first)
    case transport.recv(socket, leftover_size, @full_packet_timeout) do
      {:ok, rest} when :erlang.size(rest) == leftover_size ->
        term = [first, rest]
        |> IO.iodata_to_binary()
        |> Plug.Crypto.non_executable_binary_to_term([:safe])

        {:ok, term}
      {:ok, _} ->
        {:error, :einval}
      error -> error
    end

  catch
    # return unsafe arguments as badarg.
    :error, :badarg ->
      {:error, :badarg}
  end

  def encode(term) do
    binary = :erlang.term_to_binary(term)
    [@magic_cookie, <<:erlang.size(binary)::32>>, binary]
  end

end
