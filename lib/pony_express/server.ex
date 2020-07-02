defmodule PonyExpress.Server do

  @moduledoc false

  use Multiverses, with: [GenServer, Phoenix.PubSub]
  use GenServer

  defstruct [:pubsub_server, :tcp_socket, :socket, :topic, :transport,
    buffer: <<>>,
    tls_opts: []]

  @type state :: %__MODULE__{
    pubsub_server: GenServer.server,
    tcp_socket: :inet.socket,
    socket: Transport.socket,
    topic: String.t | nil,
    transport: module,
    buffer: binary,
    tls_opts: [
      cacertfile: Path.t,
      certfile: Path.t,
      keyfile: Path.t
    ]
  }

  alias PonyExpress.Packet

  if Multiverses.active?() do
    @forward_callers [forward_callers: true]
  else
    @forward_callers []
  end

  @spec start_link(keyword) :: GenServer.on_start
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, @forward_callers)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary,
      shutdown: 500
    }
  end

  @spec init(keyword) :: {:ok, state}
  def init(opts) do
    {:ok, struct(__MODULE__, opts)}
  end

  # the server will be very gracious in how long it waits.
  @server_timeout 1000

  @spec allow(GenServer.server, :inet.socket) ::
    {:reply, :ok, state} | {:stop, any, :error, state}
  def allow(srv, socket), do: GenServer.cast(srv, {:allow, socket})
  defp allow_impl(socket, state = %{transport: transport}) do
    # perform ssl handshake, upgrade to TLS.
    # next, wait for the subscription signal and set up the phoenix
    # pubsub subscriptions.  This should arrive in a single packet.
    case transport.handshake(socket, tls_opts: state.tls_opts) do
      {:ok, upgraded} ->
        recv_loop()
        {:noreply, %{state | tcp_socket: socket, socket: upgraded}}
      error ->
        {:stop, error, state}
    end
  end

  def handle_tcp({:subscribe, topic}, state) do
    PubSub.subscribe(state.pubsub_server, topic)
    {:noreply, %{state | topic: topic}}
  end

  def handle_info(:recv, state) do
    case Packet.get_data(state.transport, state.socket, state.buffer) do
      {:ok, {:subscribe, topic}, buffer} when is_binary(topic) ->
        recv_loop()
        PubSub.subscribe(state.pubsub_server, topic)
        {:noreply, %{state | topic: topic, buffer: buffer}}
      {:ok, :keepalive, buffer} ->
        recv_loop()
        {:noreply, %{state | buffer: buffer}}
      {:ok, nil, buffer} ->
        recv_loop()
        {:noreply, %{state | buffer: buffer}}
      {:error, :timeout} ->
        recv_loop()
        {:noreply, state}
      ###########################################
      {:ok, _, _} ->
        # other packets are invalid.
        {:stop, :einval, state}
      {:error, :closed} ->
        {:stop, :normal, state}
      {:error, error} ->
        {:stop, error, state}
    end
  end
  def handle_info(pubsub_msg, state) do
    # handle any other pubsub messages.
    case send_term(state, pubsub_msg) do
      :ok ->
        {:noreply, state}
      {:error, :closed} ->
        {:stop, :normal, state}
    end
  end

  def handle_cast({:allow, socket}, state) do
    allow_impl(socket, state)
  end

  defp send_term(state = %{transport: transport}, data) do
    transport.send(state.socket, Packet.encode({:pubsub, data}))
  end

  defp recv_loop do
    Process.send_after(self(), :recv, 0)
  end

end
