defmodule PonyExpress.Packet do

  @moduledoc false

  @magic_cookie <<1860::16, 1861::16>>

  require Logger

  @spec get_data(module, Transport.socket, binary, timeout)
    :: {:ok, term, binary} | {:error, term}

  def get_data(transport, socket, buffer, timeout \\ 100) do
    case buffer do
      @magic_cookie <> <<size :: 32>> <> rest when :erlang.size(rest) < size ->
        fetch_more_data(transport, socket, buffer, timeout)
      @magic_cookie <> <<size :: 32>> <> rest when :erlang.size(rest) == size ->
        term = Plug.Crypto.non_executable_binary_to_term(rest, [:safe])
        {:ok, term, <<>>}
      @magic_cookie <> <<size :: 32>> <> rest ->
        {first_part, new_buffer} = :erlang.split_binary(rest, size)
        term = Plug.Crypto.non_executable_binary_to_term(first_part, [:safe])
        {:ok, term, new_buffer}
      buffer when :erlang.size(buffer) < 8 ->
        # buffer is empty, so fetch more data.
        fetch_more_data(transport, socket, buffer, timeout)
      any ->
        # drop it on the floor.
        Logger.warn("improper binary received #{inspect any}")
        {:ok, nil, <<>>}
    end
  catch
    # return unsafe arguments as badarg.
    :error, :badarg ->
      {:error, :badarg}
  end

  defp fetch_more_data(transport, socket, buffer, timeout) do
    case transport.recv(socket, 0, timeout) do
      {:ok, data} ->
        {:ok, nil, buffer <> data}
      error -> error
    end
  end

  def encode(term) do
    binary = :erlang.term_to_binary(term)
    [@magic_cookie, <<:erlang.size(binary)::32>>, binary]
  end

end
