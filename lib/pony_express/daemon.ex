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
  - `:port` - port to listen on.  Defaults to 1860, a value of 0 will pick "any available port"
  - `:server_supervisor` - one of the following:
    - `nil` (default), your servers will be unsupervised **do not release with this setting**
    - `:<atom>`, a DynamicSupervisor named `<atom>`
    - `{module, term}`, an dynamic supervisor behaviour module with the following
      that will be called in the following fashion:
      `module.start_child(term, {PonyExpress.Server, opts})`.  See
      `c:DynamicSupervisor.start_child/2`
  """

  use GenServer

  # defaults the transport to TLS for library users.  This can be
  # overridden by a (gasp!) environment variable, but mostly you should
  # do this on a case-by-case basis on `start_link`.  For internal
  # library testing, this defaults to Tcp

  if Mix.env in [:dev, :test] do
    @default_transport Erps.Transport.Tcp
  else
    @default_transport Application.get_env(:pony_express, :transport, Erps.Transport.Tls)
  end

  defstruct [
    port:              0,
    sock:              nil,
    timeout:           1000,
    pubsub_server:     nil,
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

  @spec start_link(keyword) :: GenServer.on_start
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
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

  @doc false
  @spec init(keyword) :: {:ok, state} | {:stop, :error}
  def init(opts) do
    state = struct(__MODULE__, opts)
    transport = state.transport
    listen_opts = [:binary, active: false, reuseaddr: true, tls_opts: opts[:tls_opts]]
    case transport.listen(state.port, listen_opts) do
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
      {:ok, port} -> {:reply, port, state}
      {:error, e} -> raise "error: #{e}"
    end
  end
  defp port_impl(state) do
    {:reply, state.port, state}
  end

  @doc false
  @spec info(GenServer.server) :: state
  def info(srv), do: GenServer.call(srv, :info)

  @spec info_impl(state) :: {:reply, state, state}
  defp info_impl(state), do: {:reply, state, state}

  #############################################################################
  ## utilities
  defp to_server(state, child_sock) do
    state
    |> Map.from_struct
    |> Map.put(:sock, child_sock)
  end

  defp do_start_server(state = %{server_supervisor: nil}, child_sock) do
    # unsupervised case.  Not recommended, except for testing purposes.
    state
    |> to_server(child_sock)
    |> PonyExpress.Server.start_link()
  end
  defp do_start_server(state = %{server_supervisor: {module, name}}, child_sock) do
    # custom supervisor case.
    module.start_child(name,
      {PonyExpress.Server, to_server(state, child_sock)})
  end
  defp do_start_server(state = %{server_supervisor: sup}, child_sock) do
    # default, DynamicSupervisor case
    DynamicSupervisor.start_child(sup,
      {PonyExpress.Server, to_server(state, child_sock)})
  end

  #############################################################################
  ## Reentrant function that lets us keep accepting forever.

  def handle_info(:accept, state = %{transport: transport}) do
    with {:ok, child_sock} <- transport.accept(state.sock, state.timeout),
         {:ok, srv_pid} <- do_start_server(state, child_sock) do
      # transfer ownership to the child server.
      :gen_tcp.controlling_process(child_sock, srv_pid)
      # signal to the child server that the ownership has been transferred.
      PonyExpress.Server.allow(srv_pid)
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
