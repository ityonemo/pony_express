# PonyExpress

## Securely extend a Phoenix PubSub over SSL.

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

first, make the directory `test_ssl_assets`.

In this directory, perform the following steps:

- generate 2048-bit rsa key for the root CA.
  `openssl genrsa -des3 -out rootCA.key 2048`

- self-sign the root certificate.
  `openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1024 -outootCA.pem`

- generate cert rsa key (this shouldn't have a password)
  `openssl genrsa -out server.key 2048`

- create the cert signing request to be signed by your fictional CA:
  `openssl req -new -key server.key -out server.csr`
  note, that the certificate needs to have the correct common name for your
  host.  For testing, `127.0.0.1` is probably a good choice.

- sign the certificate request, generating the cert:
  `openssl x509 -req -in server.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out server.cert -days 500 -sha256`

- repeat the process for the client.
  `openssl genrsa -out client.key 2048`
  `openssl req -new -key client.key -out client.csr`
  `openssl x509 -req -in client.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out client.cert -days 500 -sha256`
