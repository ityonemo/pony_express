defmodule PonyExpress.Client do

  @moduledoc """
  GenServer which initiates a TLS connection to a remote server and forwards
  `Phoenix.PubSub` subscription across the TLS connection.

  Note:  A client may be bound to a single remote server, and a single
  topic on a single PubSub server bound to that TCP port by the remote's
  `PonyExpress.Daemon` server.

  If you need to subscribe to multiple topics, you will need to establish
  multiple `PonyExpress.Client` connections.

  ### Usage

  Typically, you will want to start the client supervised in the application
  supervision tree as follows:

  ```elixir
  PonyExpress.Client.start_supervised(
    PonyExpress.Client.Supervisor,
    server: <server IP>,
    topic: "<pubsub topic>",
    pubsub_server: <pubsub>,
    ssl_opts: [
      cacertfile: <ca_certfile>
      certfile: <certfile>
      keyfile: <keyfile>
    ])
  ```

  `PonyExpress.Client.Supervisor` should probably be a named `DynamicSupervisor`
  in most cases.
  """

  defstruct [
    server: nil,
    port: 1860,
    sock: nil,
    pubsub_server: nil,
    topic: nil,
    protocol: PonyExpress.Tls,
    ssl_opts: nil
  ]

  @typedoc false
  @type state :: %__MODULE__{
    server: :inet.ip_address,
    port: :inet.port_number,
    sock: port,
    pubsub_server: GenServer.server,
    topic: String.t,
    protocol: module,
    ssl_opts: [
      cacertfile: Path.t,
      certfile: Path.t,
      keyfile: Path.t
    ]
  }

  use GenServer

  @spec start_link(keyword) :: GenServer.on_start
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  @doc false
  @spec init(keyword) :: {:ok, state} | {:stop, any}
  def init(opts) do
    state = struct(__MODULE__, opts)
    case :gen_tcp.connect(state.server, state.port, [:binary, active: false]) do
      {:ok, sock} ->
        # immediately upgrade to TLS, then send a subscription
        # request down to the server.
        upgraded_sock = state.protocol.upgrade(sock, state.ssl_opts)
        new_state = %{state | sock: upgraded_sock}
        send_term(new_state, {:subscribe, state.topic})
        Process.send_after(self(), :recv, 0)
        {:ok, new_state}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @spec send_term(state, term) :: any
  defp send_term(state = %{protocol: protocol}, data) do
    protocol.send(state.sock, :erlang.term_to_binary(data))
  end

  @impl true
  @spec handle_info(:recv, state) :: {:noreply, state} | {:stop, :normal, state}
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
