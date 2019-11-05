defmodule PonyExpress.Daemon do

  use GenServer

  defstruct [
    port: 1860,
    sock: nil,
    timeout: 1000,
    pubsub_server: nil,
    protocol: PonyExpress.Tls
  ]

  @type state :: %__MODULE__{
    port: :inet.port_number,
    sock: port,
    timeout: timeout,
    pubsub_server: GenServer.server
  }

  @spec start_link(keyword) :: GenServer.on_start
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

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

  #############################################################################
  ## Reentrant function that lets us keep accepting forever.

  def handle_info(:accept, state) do
    with {:ok, child_sock} <- :gen_tcp.accept(state.sock, state.timeout),
         # TODO: change this to start_supervised:
         {:ok, srv_pid} <- PonyExpress.Server.start_link(
                             sock: child_sock,
                             pubsub_server: state.pubsub_server,
                             protocol: state.protocol) do
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

end
