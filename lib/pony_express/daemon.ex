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
      ssl_opts: [
        cacertfile: <ca_certfile>
        certfile: <certfile>
        keyfile: <keyfile>
    }])
  ```

  the following parameters are required:
  - `:pubsub_server` - the atom describing the Phoenix PubSub server.
  - `:ssl_opts` - cerificate authority pem file, server certificate, and server key.

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

  defstruct [
    port: 1860,
    sock: nil,
    timeout: 1000,
    pubsub_server: nil,
    protocol: PonyExpress.Tls,
    ssl_opts: nil,
    server_supervisor: nil
  ]

  @typedoc false
  @type state :: %__MODULE__{
    port: :inet.port_number,
    sock: port,
    timeout: timeout,
    pubsub_server: GenServer.server,
    protocol: module,
    server_supervisor: GenServer.server | {module, term},
    ssl_opts: [
      cacertfile: Path.t,
      certfile: Path.t,
      keyfile: Path.t
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
    case :gen_tcp.listen(state.port, [:binary, active: false, reuseaddr: true]) do
      {:ok, sock} ->
        Process.send_after(self(), :accept, 0)
        {:ok, %{state | sock: sock}}
      _ ->
        {:stop, :error}
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
  defp do_start_server(state = %{server_supervisor: nil}, child_sock) do
    # unsupervised case.  Not recommended, except for testing purposes.
    PonyExpress.Server.start_link(
                             sock: child_sock,
                             pubsub_server: state.pubsub_server,
                             protocol: state.protocol,
                             ssl_opts: state.ssl_opts)
  end
  defp do_start_server(state = %{server_supervisor: {module, term}}, child_sock) do
    # custom supervisor case.
    module.start_child(term,
      {PonyExpress.Server,
        sock: child_sock,
        pubsub_server: state.pubsub_server,
        protocol: state.protocol,
        ssl_opts: state.ssl_opts})
  end
  defp do_start_server(state = %{server_supervisor: sup}, child_sock) do
    # default, DynamicSupervisor case
    DynamicSupervisor.start_child(sup,
      {PonyExpress.Server,
        sock: child_sock,
        pubsub_server: state.pubsub_server,
        protocol: state.protocol,
        ssl_opts: state.ssl_opts})
  end

  #############################################################################
  ## Reentrant function that lets us keep accepting forever.

  def handle_info(:accept, state) do
    with {:ok, child_sock} <- :gen_tcp.accept(state.sock, state.timeout),
         # TODO: change this to start_supervised:
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
