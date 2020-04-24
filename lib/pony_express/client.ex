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
  - `:pubsub_server` - the atom describing the Phoenix PubSub server.
  - `:topic` - a string which describes the topic remotely subscribed to.
  - `:tls_opts` - cerificate authority pem file, client certificate, and
    client key.
  """

  if Mix.env in [:dev, :test] do
    @default_transport Erps.Transport.Tcp
  else
    @default_transport Application.get_env(:pony_express, :transport, Erps.Transport.Tls)
  end

  defstruct [
    server: nil,
    port: 0,
    sock: nil,
    pubsub_server: nil,
    topic: nil,
    transport: @default_transport,
    tls_opts: []
  ]

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

  use GenServer

  @gen_server_opts [:name, :timeout, :debug, :spawn_opt, :hibernate_after]

  def start(opts) do
    {gen_server_opts, inner_opts} = Keyword.split(opts, @gen_server_opts)
    GenServer.start(__MODULE__, inner_opts, gen_server_opts)
  end

  @spec start_link(keyword) :: GenServer.on_start
  def start_link(opts) do
    {gen_server_opts, inner_opts} = Keyword.split(opts, @gen_server_opts)
    GenServer.start_link(__MODULE__, inner_opts, gen_server_opts)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :transient,
      shutdown: 500
    }
  end

  @impl true
  @doc false
  @spec init(keyword) :: {:ok, state} | {:stop, any}
  def init(opts) do
    state = struct(__MODULE__, opts)

    transport = state.transport

    with {:ok, sock} <- transport.connect(state.server, state.port, [:binary, active: false]),
         {:ok, upgraded} <- transport.upgrade(sock, state.tls_opts) do
      new_state = %{state | sock: upgraded}
      send_term(new_state, {:subscribe, state.topic})
      Process.send_after(self(), :recv, 0)
      {:ok, new_state}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @spec send_term(state, term) :: any
  defp send_term(state = %{transport: transport}, data) do
    transport.send(state.sock, :erlang.term_to_binary(data))
  end

  @impl true
  @spec handle_info(:recv, state) :: {:noreply, state} | {:stop, :normal, state}
  def handle_info(:recv, state = %{transport: transport}) do
    with {:ok, data} <- transport.recv(state.sock, 0, 100),
         {:pubsub, term} <- Plug.Crypto.non_executable_binary_to_term(data, [:safe]) do
      Phoenix.PubSub.broadcast(state.pubsub_server, state.topic, term)
      Process.send_after(self(), :recv, 0)
      {:noreply, state}
    else
      {:error, :timeout} ->
        Process.send_after(self(), :recv, 0)
        {:noreply, state}
      {:error, any} ->
        # we don't expect the remote side to close the connection.
        # this should trigger the client to attempt to reheal the
        # connection by restarting and triggering a reconnection
        # via `init/1`
        {:stop, any, state}
      _some_other_term ->
        {:noreply, state}
    end
  end

end
