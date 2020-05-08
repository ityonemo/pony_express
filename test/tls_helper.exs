require Logger

tempdir_name = Base.encode16(:crypto.strong_rand_bytes(32))
tempdir = Path.join([System.tmp_dir!(), ".pony-express-test", tempdir_name])

defmodule PonyExpressTest.TlsFiles do
  @path tempdir
  def path, do: @path
  def cleanup do
    File.rm_rf!(@path)
  end
end

ExUnit.after_suite(fn %{failures: 0} ->
  # only clean up our temporary directory if it was succesful
  PonyExpressTest.TlsFiles.cleanup()
  :ok
  _ -> :ok
end)

File.mkdir_p!(tempdir)

Logger.info("test certificates path: #{tempdir}")

# make your own CA
{ca, ca_key} = PonyExpressTest.TlsFileGen.generate_root(tempdir, "rootCA")
# generate server authentications
PonyExpressTest.TlsFileGen.generate_cert(tempdir, "server", ca, ca_key)
# generate client authentications
PonyExpressTest.TlsFileGen.generate_cert(tempdir, "client", ca, ca_key)

# generate a key that is unrelated to the correct keys.
PonyExpressTest.TlsFileGen.generate_key(tempdir, "wrong-key")

# generate a client and cert that has wrong hosts.
PonyExpressTest.TlsFileGen.generate_cert(tempdir, "wrong-host", ca, ca_key, host: "1.1.1.1")

# make a chain of content that comes from the wrong CA root
{wrong_ca, wrong_ca_key} = PonyExpressTest.TlsFileGen.generate_root(tempdir, "wrong-rootCA")
# generate server authentications
PonyExpressTest.TlsFileGen.generate_cert(tempdir, "wrong-root", wrong_ca, wrong_ca_key)

defmodule PonyExpressTest.TlsOpts do
  def path(file), do: Path.join(PonyExpressTest.TlsFiles.path(), file)

  # for tests we don't have actual fqdns for our server (which is tied
  # to a self-signed certificate authority internal to the tests).  We've
  # branded the "dns" as 127.0.0.1, so verify_server_identity/2 will make
  # that match.
  defp verify_server_identity({:ip, ip}, {:dNSName, dnsname}) do
    :inet.ntoa(ip) == dnsname
  end

  # this function is imported by client modules.
  def tls_opts(who) do
    [tls_opts: [
      cacertfile: path("rootCA.pem"),
      certfile:   path("#{who}.cert"),
      keyfile:    path("#{who}.key"),
      customize_hostname_check: [match_fun: &verify_server_identity/2]]]
  end
end
