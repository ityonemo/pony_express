defmodule PonyExpressTest do
  use ExUnit.Case

  alias Phoenix.PubSub
  alias PonyExpress.Daemon
  alias PonyExpress.Client

  @localhost {127, 0, 0, 1}

  test "full stack pony express experience" do
    # create a pubsub locally
    PubSub.PG2.start_link(:test_src, [])
    PubSub.PG2.start_link(:test_tgt, [])

    PubSub.subscribe(:test_tgt, "pony_express")

    {:ok, daemon} = Daemon.start_link(port: 0,
                                      pubsub_server: :test_src,
                                      protocol: PonyExpress.Tcp)

    dport = Daemon.port(daemon)

    Client.start_link(server: @localhost,
                      port: dport,
                      protocol: PonyExpress.Tcp,
                      topic: "pony_express",
                      pubsub_server: :test_tgt)

    # give the system some time to settle.
    # TODO: make this a call query on the client.
    Process.sleep(100)

    PubSub.broadcast(:test_src, "pony_express", :ping)

    assert_receive :ping, 500
  end

  @tag :tls
  test "pony express with ssl activated" do
    # create a pubsub locally
    PubSub.PG2.start_link(:test_ssl_src, [])
    PubSub.PG2.start_link(:test_ssl_tgt, [])

    PubSub.subscribe(:test_ssl_tgt, "pony_express")

    Daemon.start_link(pubsub_server: :test_ssl_src)

    Client.start_link(server: @localhost,
                      topic: "pony_express",
                      pubsub_server: :test_ssl_tgt)

    # give the system some time to settle.
    # TODO: make this a call query on the client.
    Process.sleep(100)

    PubSub.broadcast(:test_ssl_src, "pony_express", :ping)

    assert_receive :ping, 500
  end
end
