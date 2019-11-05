defmodule PonyExpress.OtpTest do
  #
  # Tests to make sure that pony express does
  # the right thing (in an OTP sense)
  #

  alias PonyExpress.Daemon
  alias PonyExpress.Client

  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  @localhost {127, 0, 0, 1}

  describe "if you kill the server component" do
    test "daemon, the connection self-heals" do
      # cache the test_pid
      test_pid = self()

      Phoenix.PubSub.PG2.start_link(:otp_srv_1, [])
      Phoenix.PubSub.PG2.start_link(:otp_cli_1, [])

      # subscribe to the client pubsub server only.
      Phoenix.PubSub.subscribe(:otp_cli_1, "otp_test_1")

      # supervision needs to happen out of band from the test because
      # we're going to send a test kill signal to the daemon.
      supervisors = spawn(fn ->
        # for this one, use the default port.  We can't use port 0
        # because on restart, the server's port will change, and
        # the client won't be able to find it again.

        DynamicSupervisor.start_link(strategy: :one_for_one, name: SrvSupervisor1)

        {:ok, daemon_sup} = Supervisor.start_link([{Daemon,
          pubsub_server: :otp_srv_1,
          protocol: PonyExpress.Tcp,
          server_supervisor: SrvSupervisor1
        }], strategy: :one_for_one)

        [{_, daemon_pid, _, _}] = Supervisor.which_children(daemon_sup)


        DynamicSupervisor.start_link(strategy: :one_for_one, name: CliSupervisor1)

        # connect a supervised client.
        {:ok, _client_pid} = DynamicSupervisor.start_child(
          CliSupervisor1,
          {Client,
            server: @localhost,
            pubsub_server: :otp_cli_1,
            topic: "otp_test_1",
            protocol: PonyExpress.Tcp,
          })

        send(test_pid, {:daemon, daemon_pid})
        receive do :done -> :ok end
      end)

      daemon_pid = receive do {:daemon, daemon_pid} -> daemon_pid end
      Process.sleep(200)

      # test the normal broadcast route
      Phoenix.PubSub.broadcast(:otp_srv_1, "otp_test_1", {:test, "otp_test_1a"})
      assert_receive {:test, "otp_test_1a"}, 500

      # now, kill the daemon and repeat the process.
      Process.exit(daemon_pid, :kill)
      Process.sleep(200)

      refute Process.alive?(daemon_pid)

      Phoenix.PubSub.broadcast(:otp_srv_1, "otp_test_1", {:test, "otp_test_1b"})
      assert_receive {:test, "otp_test_1b"}, 500

      send(supervisors, :done)
    end

    test "server, the connection self-heals" do
      # cache the test_pid
      test_pid = self()

      Phoenix.PubSub.PG2.start_link(:otp_srv_2, [])
      Phoenix.PubSub.PG2.start_link(:otp_cli_2, [])

      # subscribe to the client pubsub server only.
      Phoenix.PubSub.subscribe(:otp_cli_2, "otp_test_2")

      # supervision needs to happen out of band from the test because
      # we're going to send a test kill signal to the daemon.
      supervisors = spawn(fn ->
        # start up a dynamic supervisor for the servers.
        DynamicSupervisor.start_link(strategy: :one_for_one, name: SrvSupervisor2)

        {:ok, daemon_sup} = Supervisor.start_link([{Daemon,
          port: 0,
          pubsub_server: :otp_srv_2,
          protocol: PonyExpress.Tcp,
          server_supervisor: SrvSupervisor2
        }], strategy: :one_for_one)

        [{_, daemon_pid, _, _}] = Supervisor.which_children(daemon_sup)
        port = Daemon.port(daemon_pid)

        DynamicSupervisor.start_link(strategy: :one_for_one, name: CliSupervisor2)

        # connect a supervised client.
        {:ok, _client_pid} = DynamicSupervisor.start_child(
          CliSupervisor2,
          {Client,
            server: @localhost,
            port: port,
            pubsub_server: :otp_cli_2,
            topic: "otp_test_2",
            protocol: PonyExpress.Tcp,
          })

        # wait for the connection to complete.
        Process.sleep(200)
        [{_, server_pid, _, _}] = DynamicSupervisor.which_children(SrvSupervisor2)

        send(test_pid, {:server, server_pid})
        receive do :done -> :ok end
      end)

      server_pid = receive do {:server, server_pid} -> server_pid end

      # test the normal broadcast route
      Phoenix.PubSub.broadcast(:otp_srv_2, "otp_test_2", {:test, "otp_test_2a"})
      assert_receive {:test, "otp_test_2a"}, 500

      # now, kill the server. This will trigger the
      assert capture_log(fn ->
        Process.exit(server_pid, :kill)
        Process.sleep(300)
      end) =~ "(stop) :closed"

      refute Process.alive?(server_pid)

      Phoenix.PubSub.broadcast(:otp_srv_2, "otp_test_2", {:test, "otp_test_2b"})
      assert_receive {:test, "otp_test_2b"}, 500

      send(supervisors, :done)
    end
  end

  describe "if you kill the client component" do
    test "the connection self-heals" do
      # cache the test_pid
      test_pid = self()

      Phoenix.PubSub.PG2.start_link(:otp_srv_3, [])
      Phoenix.PubSub.PG2.start_link(:otp_cli_3, [])

      # subscribe to the client pubsub server only.
      Phoenix.PubSub.subscribe(:otp_cli_3, "otp_test_3")

      # supervision needs to happen out of band from the test because
      # we're going to send a test kill signal to the daemon.
      supervisors = spawn(fn ->
        # for this one, use the default port.  We can't use port 0
        # because on restart, the server's port will change, and
        # the client won't be able to find it again.

        DynamicSupervisor.start_link(strategy: :one_for_one, name: SrvSupervisor3)

        {:ok, daemon_sup} = Supervisor.start_link([{Daemon,
          port: 0,
          pubsub_server: :otp_srv_3,
          protocol: PonyExpress.Tcp,
          server_supervisor: SrvSupervisor3
        }], strategy: :one_for_one)

        [{_, daemon_pid, _, _}] = Supervisor.which_children(daemon_sup)
        port = Daemon.port(daemon_pid)

        DynamicSupervisor.start_link(strategy: :one_for_one, name: CliSupervisor3)

        # connect a supervised client.
        {:ok, client_pid} = DynamicSupervisor.start_child(
          CliSupervisor3,
          {Client,
            server: @localhost,
            port: port,
            pubsub_server: :otp_cli_3,
            topic: "otp_test_3",
            protocol: PonyExpress.Tcp,
          })

        send(test_pid, {:client, client_pid})
        receive do :done -> :ok end
      end)

      client_pid = receive do {:client, client_pid} -> client_pid end
      Process.sleep(200)

      # test the normal broadcast route
      Phoenix.PubSub.broadcast(:otp_srv_3, "otp_test_3", {:test, "otp_test_3a"})
      assert_receive {:test, "otp_test_3a"}, 500

      # now, kill the client and repeat the process.
      Process.exit(client_pid, :kill)
      Process.sleep(200)

      refute Process.alive?(client_pid)

      Phoenix.PubSub.broadcast(:otp_srv_3, "otp_test_3", {:test, "otp_test_3b"})
      assert_receive {:test, "otp_test_3b"}, 500

      send(supervisors, :done)
    end
  end

end
