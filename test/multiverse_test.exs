defmodule PonyExpressTest.MultiverseTest do
  use ExUnit.Case, async: true

  # tests to see that IP transmissions can be a wormhole between
  # universes.

  use Multiverses, with: Phoenix.PubSub
  alias PonyExpress.Daemon
  alias PonyExpress.Client

  @localhost IP.localhost

  setup_all do
    # set up our pubsub server.
    PubSubStarter.start_link([:multiverse])
    :ok
  end

  @tag :one
  test "pony express can bridge multiverses" do
    # cache the test_pid
    test_pid = self()

    # subscribe to the multiverse pubsub serer.
    PubSub.subscribe(:multiverse, "test")

    subuniverse = spawn_link fn ->
      {:ok, daemon} = Daemon.start_link(port: 0,
                                        pubsub_server: :multiverse,
                                        forward_callers: true)
      {:ok, port} = Daemon.port(daemon)

      send(test_pid, {:port, port})
      assert_receive :unhold, 500

      PubSub.broadcast(:multiverse, "test", :ping)

      receive do :never -> :die end
    end

    # make sure can can connect into daemon.
    assert_receive {:port, port}

    Client.start_link(server: @localhost,
                      port: port,
                      topic: "test",
                      pubsub_server: :multiverse,
                      forward_callers: true)

    Process.sleep(100)

    send(subuniverse, :unhold)

    assert_receive :ping
  end

end
