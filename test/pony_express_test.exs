defmodule PonyExpressTest do
  use ExUnit.Case

  alias PonyExpress.Daemon
  alias PonyExpress.Client

  use Multiverses, with: Phoenix.PubSub

  @localhost IP.localhost

  test "full stack pony express experience, but unencryped (for testing)" do
    # create pubsubs locally

    PubSubStarter.start_link([:test_src, :test_tgt])

    PubSub.subscribe(:test_tgt, "pony_express")

    {:ok, daemon} = Daemon.start_link(port: 0,
                                      pubsub_server: :test_src,
                                      forward_callers: true)

    {:ok, port} = Daemon.port(daemon)

    Client.start_link(server: @localhost,
                      port: port,
                      topic: "pony_express",
                      pubsub_server: :test_tgt,
                      forward_callers: true)

    # give the system some time to settle.
    # TODO: make this a call query on the client.
    Process.sleep(100)

    PubSub.broadcast(:test_src, "pony_express", :ping)

    assert_receive :ping, 500
  end

  @tag :tls
  test "pony express with ssl activated" do
    # create pubsubs locally
    PubSubStarter.start_link([:test_ssl_src, :test_ssl_tgt])

    import PonyExpressTest.TlsOpts

    PubSub.subscribe(:test_ssl_tgt, "pony_express")

    daemon_opts = [
      pubsub_server: :test_ssl_src,
      port: 0,
      transport: Transport.Tls,
      forward_callers: true
      ] ++ tls_opts("server")

    {:ok, daemon} = Daemon.start_link(daemon_opts)

    {:ok, port} = Daemon.port(daemon)

    client_opts = [
      server: @localhost,
      port: port,
      topic: "pony_express",
      transport: Transport.Tls,
      pubsub_server: :test_ssl_tgt,
      forward_callers: true] ++ tls_opts("server")

    Client.start_link(client_opts)

    # give the system some time to settle.
    # TODO: make this a call query on the client.
    Process.sleep(200)

    PubSub.broadcast(:test_ssl_src, "pony_express", :ping)

    assert_receive :ping, 500
  end
end
