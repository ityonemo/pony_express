defmodule PonyExpressTest.MtuTest do
  use ExUnit.Case

  alias Phoenix.PubSub
  alias PonyExpress.Daemon
  alias PonyExpress.Client

  @localhost {127, 0, 0, 1}

  @moduletag :mtu

  test "test that we can send results that exceed the MTU" do
    # create pubsubs locally
    PubSubStarter.start_link([:mtu_test_src, :mtu_test_tgt])

    Process.sleep(100)

    PubSub.subscribe(:mtu_test_tgt, "pony_express")

    {:ok, daemon} = Daemon.start_link(port: 0,
                                      pubsub_server: :mtu_test_src)

    dport = Daemon.port(daemon)

    Client.start_link(server: @localhost,
                      port: dport,
                      topic: "pony_express",
                      pubsub_server: :mtu_test_tgt)

    # give the system some time to settle.
    # TODO: make this a call query on the client.
    Process.sleep(100)

    more_than_mtu = <<0::10240 * 8>>

    PubSub.broadcast(:mtu_test_src, "pony_express", more_than_mtu)

    assert_receive ^more_than_mtu, 500
  end
end
