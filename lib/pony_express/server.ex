defmodule PonyExpress.Server do

  @moduledoc false

  defstruct [
    pubsub_server: nil,
    sock: nil,
    topic: nil,
    protocol: PonyExpress.Tls,
    ssl_opts: nil
  ]

  @type state :: %__MODULE__{
    pubsub_server: GenServer.server,
    sock: port,
    topic: String.t | nil,
    protocol: module,
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
      restart: :temporary,
      shutdown: 500
    }
  end

  @spec init(keyword) :: {:ok, state}
  def init(opts) do
    state = struct(__MODULE__, opts)
    {:ok, state}
  end

  @spec allow(GenServer.server) :: {:reply, :ok, state} | {:stop, any, :error, state}
  def allow(srv), do: GenServer.call(srv, :allow)
  defp allow_impl(state = %{protocol: protocol}) do
    # perform ssl handshake, upgrade to TLS.
    upgraded_sock = protocol.handshake(state.sock, state.ssl_opts)
    # next, wait for the subscription signal and set up the phoenix
    # pubsub subscriptions.
    with {:ok, data} <- protocol.recv(upgraded_sock, 0, 1000),
         {:subscribe, topic} <- :erlang.binary_to_term(data) do
      Phoenix.PubSub.subscribe(state.pubsub_server, topic)
      Process.send_after(self(), :recv, 0)
      {:reply, :ok, %{state | sock: upgraded_sock}}
    else
      error -> {:stop, error, :error, state}
    end
  end

  def handle_tcp({:subscribe, topic}, state) do
    Phoenix.PubSub.subscribe(state.pubsub_server, topic)
    {:noreply, %{state | topic: topic}}
  end

  def handle_info(:recv, state = %{protocol: protocol}) do
    case protocol.recv(state.sock, 0, 100) do
      {:ok, _data} ->
        Process.send_after(self(), :recv, 0)
        {:noreply, state}
      {:error, :timeout} ->
        Process.send_after(self(), :recv, 0)
        {:noreply, state}
      {:error, :closed} ->
        {:stop, :normal, state}
      err ->
        {:stop, err, state}
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

  def handle_call(:allow, _from, state) do
    allow_impl(state)
  end

  defp send_term(state = %{protocol: protocol}, data) do
    protocol.send(state.sock, :erlang.term_to_binary({:pubsub, data}))
  end

end
