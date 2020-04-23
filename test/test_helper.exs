__ENV__.file
|> Path.dirname
|> Path.join("scripts/tls_test_setup.exs")
|> Code.require_file

ExUnit.start()
