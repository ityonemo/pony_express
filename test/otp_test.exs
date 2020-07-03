defmodule PonyExpress.OtpTest do
  #
  # Tests to make sure that pony express does
  # the right thing (in an OTP sense)
  #
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  use Multiverses, with: [Phoenix.PubSub, DynamicSupervisor]
  require Multiverses.Supervisor
  alias PonyExpress.Daemon
  alias PonyExpress.Client

  @localhost IP.localhost

  defmodule DaemonSupervisor do
    use Multiverses, with: Supervisor
    use Supervisor

    def start_link(opts) do
      Supervisor.start_link(__MODULE__, nil, opts ++ [forward_callers: true])
    end

    def init(_) do
      children = [{Daemon,
        pubsub_server: :otp_server,
        server_supervisor: ServerSupervisor,
        forward_callers: true}]
      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  setup_all do
    # set up our pubsub server.
    PubSubStarter.start_link([:otp_client, :otp_server])
    # set up a dynamic supervisor for the servers
    :ok
  end

  setup do
    DynamicSupervisor.start_link(name: ServerSupervisor, strategy: :one_for_one)
    DynamicSupervisor.start_link(name: ClientSupervisor, strategy: :one_for_one)
    :ok
  end

  describe "if you kill the server component" do
    test "daemon, the connection self-heals" do
      # subscribe to the client pubsub server only.
      PubSub.subscribe(:otp_client, "test")

      # daemon operations.
      {:ok, daemon_sup} = DaemonSupervisor.start_link(strategy: :one_for_one)

      # find the daemon inside the supervisor.
      [{_, daemon_pid, _, _}] = Supervisor.which_children(daemon_sup)
      {:ok, port} = PonyExpress.Daemon.port(daemon_pid)

      # connect a supervised client.
      DynamicSupervisor.start_child(
        ClientSupervisor,
        {Client,
          port: port,
          server: @localhost,
          pubsub_server: :otp_client,
          topic: "test",
          forward_callers: true
        })

      # allow the client to warm up.
      Process.sleep(200)

      # test the normal broadcast route
      PubSub.broadcast(:otp_server, "test", {:test, "otp_test_1a"})
      assert_receive {:test, "otp_test_1a"}, 500

      # now, kill the daemon and repeat the process.
      Process.exit(daemon_pid, :kill)
      Process.sleep(200)

      refute Process.alive?(daemon_pid)

      PubSub.broadcast(:otp_server, "test", {:test, "otp_test_1b"})
      assert_receive {:test, "otp_test_1b"}, 500
    end

    test "server, the connection self-heals" do
      # subscribe to the client pubsub server only.
      PubSub.subscribe(:otp_client, "test")

      # daemon operations.
      {:ok, daemon_sup} = DaemonSupervisor.start_link(strategy: :one_for_one)
      [{_, daemon_pid, _, _}] = Supervisor.which_children(daemon_sup)
      {:ok, port} = Daemon.port(daemon_pid)

      # connect a supervised client.
      DynamicSupervisor.start_child(
        ClientSupervisor,
        {Client,
          server: @localhost,
          port: port,
          pubsub_server: :otp_client,
          topic: "test",
          forward_callers: true
        })

      # wait for the connection to complete.
      Process.sleep(200)
      [{_, server_pid, _, _}] = DynamicSupervisor.which_children(ServerSupervisor)

      # test the normal broadcast route
      PubSub.broadcast(:otp_server, "test", {:test, "otp_test_2a"})
      assert_receive {:test, "otp_test_2a"}, 500

      # now, kill the server. This will trigger the
      assert capture_log(fn ->
        Process.exit(server_pid, :kill)
        Process.sleep(300)
      end) =~ "(stop) :closed"

      refute Process.alive?(server_pid)

      PubSub.broadcast(:otp_server, "test", {:test, "otp_test_2b"})
      assert_receive {:test, "otp_test_2b"}, 500
    end
  end

  describe "if you kill the client component" do
    test "the connection self-heals" do
      # subscribe to the client pubsub server only.
      PubSub.subscribe(:otp_client, "test")

      # daemon operations.
      {:ok, daemon_sup} = DaemonSupervisor.start_link(strategy: :one_for_one)
      [{_, daemon_pid, _, _}] = Supervisor.which_children(daemon_sup)
      {:ok, port} = Daemon.port(daemon_pid)

      DynamicSupervisor.start_link(strategy: :one_for_one, name: CliSupervisor3)

      # connect a supervised client.
      {:ok, client_pid} = DynamicSupervisor.start_child(
        ClientSupervisor,
        {Client,
          server: @localhost,
          port: port,
          pubsub_server: :otp_client,
          topic: "test",
          forward_callers: true
        })

      Process.sleep(200)

      # test the normal broadcast route
      PubSub.broadcast(:otp_server, "test", {:test, "otp_test_3a"})
      assert_receive {:test, "otp_test_3a"}, 500

      # now, kill the client and repeat the process.
      Process.exit(client_pid, :kill)
      Process.sleep(200)

      refute Process.alive?(client_pid)

      PubSub.broadcast(:otp_server, "test", {:test, "otp_test_3b"})
      assert_receive {:test, "otp_test_3b"}, 500
    end
  end

end
