defmodule PonyExpress.Daemon do

  @moduledoc """
  GenServer which listens on a TCP port waiting for inbound PonyExpress subscriptions.

  These connections are then forwarded to `PonyExpress.Server` servers which
  then handle `Phoenix.PubSub` transactions between server and client nodes.
  Only one PubSub server may be bound to any given port.  If you need to forward
  multiple PubSub servers, you will need to listen on multiple ports.

  ### Usage

  Typically, you will want to start the daemon supervised in the application
  supervision tree as follows:

  ```elixir

  Supervisor.start_link(
    [{PonyExpress.Daemon,
      pubsub_server: <pubsub_server>,
      server_supervisor: <supervisor for servers>
      tls_opts: [
        cacertfile: <ca_certfile>
        certfile: <certfile>
        keyfile: <keyfile>
    }])
  ```

  the following parameters are required:
  - `:pubsub_server` - the atom describing the Phoenix PubSub server.
  - `:tls_opts` - cerificate authority pem file, server certificate, and server key.

  the following parameters might be useful:
  - `:port` - port to listen on.  Defaults to 0, which will pick "any available port"
  - `:server_supervisor` - one of the following:
    - `nil` (default), your servers will be unsupervised **do not release with this setting**
    - `:<atom>`, a DynamicSupervisor named `<atom>`
    - `{module, term}`, an dynamic supervisor behaviour module with the following
      that will be called in the following fashion:
      `module.start_child(term, {PonyExpress.Server, opts})`.  See
      `c:DynamicSupervisor.start_child/2`
  - `:transport` - specify an alternative transport module besides TLS.  See `Transport`.
  """

  use Multiverses, with: [DynamicSupervisor, GenServer]
  use GenServer

  alias PonyExpress.Server

  # defaults the transport to TLS for library users. For internal library
  # testing, this defaults to Tcp.  If you're testing your own pony_express
  # server, you can override this with the transport argument.

  if Mix.env in [:dev, :test] do
    @default_transport Transport.Tcp
  else
    @default_transport Transport.Tls
  end

  @enforce_keys [:pubsub_server]

  defstruct @enforce_keys ++ [
    port:              0,
    sock:              nil,
    timeout:           1000,
    transport:         @default_transport,
    tls_opts:          [],
    server_supervisor: nil
  ]

  @type socket :: :inet.socket | :ssl.socket

  @typedoc false
  @type state :: %__MODULE__{
    port:              :inet.port_number,
    sock:              socket,
    timeout:           timeout,
    pubsub_server:     GenServer.server,
    transport:         module,
    server_supervisor: GenServer.server | {module, term} | nil,
    tls_opts: [
      cacertfile:      Path.t,
      certfile:        Path.t,
      keyfile:         Path.t
    ]
  }

  if Application.compile_env(:pony_express, :use_multiverses) do
    @forward_callers [:forward_callers]
  else
    @forward_callers []
  end

  @gen_server_opts [:debug, :timeout, :hibernate_after, :spawn_opt, :name] ++ @forward_callers

  @spec start(keyword) :: GenServer.on_start
  def start(options) do
    gen_server_options = Keyword.take(options, @gen_server_opts)
    GenServer.start(__MODULE__, options, gen_server_options)
  end

  @spec start_link(keyword) :: GenServer.on_start
  def start_link(options) do
    options
    |> put_in([:spawn_opt], [:link | Keyword.get(options, :spawn_opt, [])])
    |> start
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  # TODO: move this filtering to `Transport`
  @default_listen_opts [reuseaddr: true]
  @tcp_listen_opts [:buffer, :delay_send, :deliver, :dontroute, :exit_on_close,
  :header, :highmsgq_watermark, :high_watermark, :keepalive, :linger,
  :low_msgq_watermark, :low_watermark, :nodelay, :packet, :packet_size, :priority,
  :recbuf, :reuseaddr, :send_timeout, :send_timeout_close, :show_econnreset,
  :sndbuf, :tos, :tclass, :ttl, :recvtos, :recvtclass, :recvttl, :ipv6_v6only]

  @doc false
  @spec init(keyword) :: {:ok, state} | {:stop, any}
  def init(opts) do
    opts[:pubsub_server] || raise "you must provide a pubsub server to subscribe to"
    state = struct(__MODULE__, opts)
    listen_opts = @default_listen_opts
    |> Keyword.merge(opts)
    |> Keyword.take(@tcp_listen_opts)

    case state.transport.listen(state.port, listen_opts) do
      {:ok, sock} ->
        Process.send_after(self(), :accept, 0)
        {:ok, %{state | sock: sock}}
      {:error, what} ->
        {:stop, what}
    end
  end

  #############################################################################
  ## API

  @doc """
  retrieve the TCP port that the pony express server is bound to.

  Useful for tests - when we want to assign it a port of 0 so that it gets
  "any free port" of the system.
  """
  @spec port(GenServer.server) :: :inet.port_number
  def port(srv), do: GenServer.call(srv, :port)

  @spec port_impl(state) :: {:reply, :inet.port_number, state}
  defp port_impl(state = %{port: 0}) do
    case :inet.port(state.sock) do
      {:ok, port} -> {:reply, {:ok, port}, state}
      {:error, e} -> raise "error: #{e}"
    end
  end
  defp port_impl(state) do
    {:reply, {:ok, state.port}, state}
  end

  # internal function (but also available for public use) that gives you
  # visibility into the internals of the pony express daemon.  Results of
  # this function should not be relied upon for forward compatibility.
  @doc false
  @spec info(GenServer.server) :: state
  def info(srv), do: GenServer.call(srv, :info)

  @spec info_impl(state) :: {:reply, state, state}
  defp info_impl(state), do: {:reply, state, state}

  #############################################################################
  ## utilities

  defp do_start_server(state = %{server_supervisor: nil}) do
    # unsupervised case.  Not recommended, except for testing purposes.
    state
    |> Map.from_struct
    |> Enum.map(&(&1))
    |> Server.start_link
  end
  defp do_start_server(state = %{server_supervisor: {module, name}}) do
    # custom supervisor case.
    module.start_child(name, {Server, Map.from_struct(state)})
  end
  defp do_start_server(state = %{server_supervisor: sup}) do
    # default, DynamicSupervisor case
    DynamicSupervisor.start_child(sup,
      {Server, Map.from_struct(state)})
  end

  #############################################################################
  ## Reentrant function that lets us keep accepting forever.

  def handle_info(:accept, state = %{transport: transport}) do
    with {:ok, child_sock} <- transport.accept(state.sock, state.timeout),
         {:ok, srv_pid} <- do_start_server(state) do
      # transfer ownership to the child server.
      :gen_tcp.controlling_process(child_sock, srv_pid)
      # transfer ownership to the server, and send it to the server
      Server.allow(srv_pid, child_sock)
    else
      {:error, :timeout} ->
        # this is normal.  Just quit out and enter the accept loop.
        :ok
    end
    Process.send_after(self(), :accept, 0)
    {:noreply, state}
  end

  #############################################################################
  ## Router

  def handle_call(:port, _from, state), do: port_impl(state)
  def handle_call(:info, _from, state), do: info_impl(state)

end
