defmodule PonyExpress.Client do

  defstruct [
    server: nil,
    port: 1860,
    sock: nil,
    pubsub_server: nil,
    topic: nil,
    protocol: PonyExpress.Tls
  ]

  @type state :: %__MODULE__{
    server: :inet.ip_address,
    port: :inet.port_number,
    sock: port,
    pubsub_server: GenServer.server,
    topic: String.t,
    protocol: module
  }

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    state = struct(__MODULE__, opts)
    case :gen_tcp.connect(state.server, state.port, [:binary, active: false]) do
      {:ok, sock} ->
        # immediately upgrade to TLS, then send a subscription
        # request down to the server.
        upgraded_sock = state.protocol.upgrade(sock)
        new_state = %{state | sock: upgraded_sock}
        send_term(new_state, {:subscribe, state.topic})
        Process.send_after(self(), :recv, 0)
        {:ok, new_state}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp send_term(state = %{protocol: protocol}, data) do
    protocol.send(state.sock, :erlang.term_to_binary(data))
  end

  def handle_info(:recv, state = %{protocol: protocol}) do
    with {:ok, data} <- protocol.recv(state.sock, 0, 100),
         {:pubsub, term} <- :erlang.binary_to_term(data) do
      Phoenix.PubSub.broadcast(state.pubsub_server, state.topic, term)
      Process.send_after(self(), :recv, 0)
      {:noreply, state}
    else
      {:error, :timeout} ->
        Process.send_after(self(), :recv, 0)
        {:noreply, state}
      {:error, :closed} ->
        {:stop, :normal, state}
    end
  end

end
