defmodule PonyExpressTest do
  use ExUnit.Case

  alias Phoenix.PubSub
  alias PonyExpress.Daemon
  alias PonyExpress.Client

  @localhost {127, 0, 0, 1}

  test "full stack pony express experience, but unencryped (for testing)" do
    # create pubsubs locally
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

  @ca_certfile     Path.expand("test_ssl_assets/rootCA.pem")
  @srv_certfile    Path.expand("test_ssl_assets/server.cert")
  @srv_keyfile     Path.expand("test_ssl_assets/server.key")
  @client_certfile Path.expand("test_ssl_assets/client.cert")
  @client_keyfile  Path.expand("test_ssl_assets/client.key")

  @tag :tls
  test "pony express with ssl activated" do
    # create pubsubs locally
    PubSub.PG2.start_link(:test_ssl_src, [])
    PubSub.PG2.start_link(:test_ssl_tgt, [])

    PubSub.subscribe(:test_ssl_tgt, "pony_express")

    Daemon.start_link(pubsub_server: :test_ssl_src,
                      ssl_opts: [cacertfile: @ca_certfile,
                                 certfile: @srv_certfile,
                                 keyfile: @srv_keyfile])

    Client.start_link(server: @localhost,
                      topic: "pony_express",
                      pubsub_server: :test_ssl_tgt,
                      ssl_opts: [cacertfile: @ca_certfile,
                                 certfile: @client_certfile,
                                 keyfile: @client_keyfile])

    # give the system some time to settle.
    # TODO: make this a call query on the client.
    Process.sleep(100)

    PubSub.broadcast(:test_ssl_src, "pony_express", :ping)

    assert_receive :ping, 500
  end
end
