defmodule PonyExpress.Client do

  @moduledoc """
  GenServer which initiates a TLS connection to a remote `Phoenix.PubSub`
  server and forwards the subscription across the TLS connection to a local
  PubSub server.

  Note that PubSub messages are forwarded in one direction only, from server
  to client.  A future version may feature pushing messages to the remote
  server, but this may require considerations like request throttling.  In
  this case the security model is that the Client trusts the Server to
  not spam it.

  Note:  A client may be bound to a single remote server, and a single
  topic on a single PubSub server bound to that TCP port by the remote's
  `PonyExpress.Daemon` server.

  If you need to subscribe to multiple topics, you will need to establish
  multiple `PonyExpress.Client` connections.

  ### Usage

  Typically, you will want to start the client supervised in the application
  supervision tree as follows (or equivalent):

  ```elixir
  DynamicSupervisor.start_child({
    SomeSupervisor,
    server: <server IP>,
    port: <port>,
    topic: "<pubsub topic>",
    pubsub_server: <pubsub>,
    tls_opts: [
      cacertfile: <ca_certfile>
      certfile: <certfile>
      keyfile: <keyfile>
    ]})
  )
  ```

  the following parameters are required:
  - `:server` - remote server you're connecting to.
  - `:pubsub_server` - the atom describing the Phoenix PubSub server.
  - `:topic` - a string which describes the topic remotely subscribed to.
  - `:tls_opts` - cerificate authority pem file, client certificate, and
    client key. (requirement may depend on your transport strategy)

  the following optional parameters are accepted:
  - `:reconnect` - if the connection attempt fails, retry after that many
    milliseconds.
  - `:transport` - specify an alternative transport module besides TLS.  See `Transport`.
  """

  if Mix.env in [:dev, :test] do
    @default_transport Transport.Tcp
  else
    @default_transport Application.get_env(:pony_express, :transport, Transport.Tls)
  end

  @enforce_keys [:server, :port, :pubsub_server, :topic]

  defstruct @enforce_keys ++ [
    sock: nil,
    transport: @default_transport,
    tls_opts: [],
  ]

  # TODO: change internal state to "socket"

  @typedoc false
  @type state :: %__MODULE__{
    server: :inet.ip_address,
    port: :inet.port_number,
    sock: port,
    pubsub_server: GenServer.server,
    topic: String.t,
    transport: module,
    tls_opts: keyword
  }

  use Connection
  alias PonyExpress.Packet
  require Logger

  #############################################################################
  ## initialization and supervision boilerplate

  def child_spec(opts) do
    %{
      id: opts[:topic],
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :transient,
      shutdown: 500
    }
  end

  @gen_server_opts [:name, :timeout, :debug, :spawn_opt, :hibernate_after]

  def start(opts) do
    {gen_server_opts, inner_opts} = Keyword.split(opts, @gen_server_opts)
    is_binary(opts[:topic]) or raise "pony express client needs a topic"
    Connection.start(__MODULE__, inner_opts, gen_server_opts)
  end

  @spec start_link(keyword) :: GenServer.on_start
  def start_link(opts) do
    opts
    |> put_in([:spawn_opt], [:link | (opts[:spawn_opt] || [])])
    |> start
  end

  @impl true
  @spec init(keyword) :: {:connect, :init, state}
  def init(options!) do
    options! = Keyword.put_new(options!, :transport, @default_transport)
    Enum.each(@enforce_keys, fn key ->
      Keyword.has_key?(options!, key) or raise ArgumentError,
        "client initialization is missing option #{key}"
    end)
    {:connect, :init, struct(__MODULE__, options!)}
  end

  ##################################################################################
  ## connection implementation

  @impl true
  @spec connect(:init, state) :: {:ok, state} | {:backoff, timeout, state} | {:stop, any, state}
  def connect(_, state = %{transport: transport}) do
    with {:ok, socket} <- transport.connect(state.server, state.port),
         {:ok, upgraded} <- transport.upgrade(socket, tls_opts: state.tls_opts) do
      new_state = %{state | sock: upgraded}
      # send a subscription message to the server
      send_term(new_state, {:subscribe, state.topic})
      #then start the receive loop.
      trigger_receive()
      {:ok, new_state}
    else
      {:error, :econnrefused} ->
        {:backoff, 1000, state}
      {:error, message} ->
        Logger.error("connection error: #{logformat message}")
        {:stop, message, state}
    end
  end

  @impl true
  def disconnect(_, state), do: {:stop, :disconnected, state}

  ##################################################################################
  ## MESSAGE IMPLEMENTATIONS

  defp recv_impl(state = %{transport: transport}) do
    with {:ok, term} <- Packet.get_data(transport, state.sock),
         {:pubsub, pubsub_msg} <- term do
      Phoenix.PubSub.broadcast(state.pubsub_server, state.topic, pubsub_msg)
      trigger_receive()
      {:noreply, state}
    else
      {:error, :timeout} -> # normal receive timeout event
        trigger_receive()
        {:noreply, state}
      {:error, any} ->
        Logger.error("error receiving message #{logformat any}")
        # with any other error, trigger the client to reheal the connection by
        # restarting and reconnecting via init/1
        {:stop, any, state}
      any ->
        Logger.error("unexpected receive result #{inspect any }")
        {:stop, :error, state}
    end
  end

  ##################################################################################
  ## ROUTER

  @impl true
  @spec handle_info(:recv, state) :: {:noreply, state} | {:stop, :normal, state}
  def handle_info(:recv, state), do: recv_impl(state)

  ##################################################################################
  ## PRIVATE HELPER FUNCTIONS

  @spec send_term(state, term) :: any
  defp send_term(state = %{transport: transport}, data) do
    transport.send(state.sock, Packet.encode(data))
  end

  defp logformat(content) when is_binary(content), do: content
  defp logformat(content) when is_list(content), do: content
  defp logformat(content), do: inspect(content)

  defp trigger_receive do
    Process.send_after(self(), :recv, 0)
  end
end
