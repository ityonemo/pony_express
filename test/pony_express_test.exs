defmodule PonyExpressTest do
  use ExUnit.Case

  alias Phoenix.PubSub
  alias PonyExpress.Daemon
  alias PonyExpress.Client

  @localhost {127, 0, 0, 1}

  @tag :one
  test "full stack pony express experience, but unencryped (for testing)" do
    # create pubsubs locally
    PubSub.PG2.start_link(:test_src, [])
    PubSub.PG2.start_link(:test_tgt, [])

    PubSub.subscribe(:test_tgt, "pony_express")

    {:ok, daemon} = Daemon.start_link(port: 0,
                                      pubsub_server: :test_src)

    dport = Daemon.port(daemon)

    Client.start_link(server: @localhost,
                      port: dport,
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
    # create pubsubs locally
    PubSub.PG2.start_link(:test_ssl_src, [])
    PubSub.PG2.start_link(:test_ssl_tgt, [])

    import PonyExpressTest.TlsOpts

    PubSub.subscribe(:test_ssl_tgt, "pony_express")

    daemon_opts = [
      pubsub_server: :test_ssl_src,
      port: 0
      ] ++ tls_opts("server")

    {:ok, daemon} = Daemon.start_link(daemon_opts)

    dport = Daemon.port(daemon)

    client_opts = [
      server: @localhost,
      port: dport,
      topic: "pony_express",
      pubsub_server: :test_ssl_tgt] ++ tls_opts("server")

    Client.start_link(client_opts)

    # give the system some time to settle.
    # TODO: make this a call query on the client.
    Process.sleep(100)

    PubSub.broadcast(:test_ssl_src, "pony_express", :ping)

    assert_receive :ping, 500
  end
end
