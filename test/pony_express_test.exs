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

  def path(file) do
    Path.join(PonyExpressTest.TlsFiles.path(), file)
  end

  @tag :tls
  test "pony express with ssl activated" do
    # create pubsubs locally
    PubSub.PG2.start_link(:test_ssl_src, [])
    PubSub.PG2.start_link(:test_ssl_tgt, [])

    PubSub.subscribe(:test_ssl_tgt, "pony_express")

    {:ok, daemon} = Daemon.start_link(pubsub_server: :test_ssl_src,
                                      port: 0,
                                      tls_opts: [cacertfile: path("rootCA.pem"),
                                                 certfile: path("server.cert"),
                                                 keyfile: path("server.key")])

    dport = Daemon.port(daemon)

    Client.start_link(server: @localhost,
                      port: dport,
                      topic: "pony_express",
                      pubsub_server: :test_ssl_tgt,
                      tls_opts: [cacertfile: path("rootCA.pem"),
                                 certfile: path("client.cert"),
                                 keyfile: path("client.key")])

    # give the system some time to settle.
    # TODO: make this a call query on the client.
    Process.sleep(100)

    PubSub.broadcast(:test_ssl_src, "pony_express", :ping)

    assert_receive :ping, 500
  end
end
