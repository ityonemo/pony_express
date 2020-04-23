# PonyExpress

## Securely extend a Phoenix PubSub over SSL.

PonyExpress creates two-way authenticated SSL connections over the WAN which are
intended to unidirectionally extend a PubSub over the internet.

The use case is when you have a trusted pair of nodes (for example a backend and
a BFF) that could use live-updating pubsub propagation.  These might be located in
distinct layer-2 networks, for example, a BFF in the cloud which services an
on-premises backend.  Or you may be wanting security in-depth with end-to-end
encryption in your layer-2 network to mitigate damage from a potential network
intrusion event.  In either case, if full erlang distribution is not right for you,
this is a low-footprint way of propagating those `Phoenix.PubSub` messages (without
writing a full `Phoenix.Channel` client).

SSL is required, except in `:test`.  See below for how to set up a series of
SSL certs in test, which can be adapted for deploying in `:prod`.  However, You
may want a more comprehensive CA provider solution, instead of manually
configuring CA roots and certs.

On the server side:

```elixir
iex> Phoenix.PubSub.PG2.start_link(:source, [])
iex> PonyExpress.Daemon.start_link(
       pubsub_server: :source,
       ssl_opts: [
         cacertfile: <ca_certfile>
         certfile: <certfile>
         keyfile: <keyfile>
       ])
```

On the client side:
```elixir
iex> Phoenix.PubSub.PG2.start_link(:dest, [])
iex> PonyExpress.Client.start_link(
       server: <server IP>
       topic: "my_topic",
       pubsub_server: :dest,
       ssl_opts: [
         cacertfile: <ca_certfile>
         certfile: <certfile>
         keyfile: <keyfile>
       ])
iex> Phoenix.PubSub.subscribe(:dest, "my_topic")
```

Then you can send a message on the server side:
```elixir
iex> Phoenix.PubSub.broadcast(:source, "my_topic", "my_message")
```

And it will appear on the client side:
```elixir
iex> flush()
"my_message"
:ok
```

Consult the documentation for more comprehensive OTP-compliant strategies for
using this library.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `pony_express` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pony_express, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/pony_express](https://hexdocs.pm/pony_express).

## Testing

To test PonyExpress, youll want to build a set of testing keys.


