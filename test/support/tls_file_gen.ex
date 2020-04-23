# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc

defmodule PonyExpressTest.TlsFileGen do

  # taken from the Erps utilities.  This might get broken out for DRY reasons

  alias X509.Certificate
  alias X509.Certificate.Extension
  alias X509.CSR
  alias X509.PrivateKey

  def generate_key(dir, name) do
    ca_key = PrivateKey.new_ec(:secp256r1)
    ca_key_pem_path = Path.join(dir, "#{name}.key")
    File.write!(ca_key_pem_path, PrivateKey.to_pem(ca_key))
    ca_key
  end

  def generate_root(dir, name) do
    ca_key = generate_key(dir, name)

    ca = Certificate.self_signed(ca_key,
      "/C=US/ST=CA/L=San Francisco/O=Acme/CN=CA_ROOT",
      template: :root_ca)
    ca_pem_path = Path.join(dir, "#{name}.pem")
    File.write!(ca_pem_path, Certificate.to_pem(ca))

    {ca, ca_key}
  end

  def generate_cert(dir, name, ca, ca_key, opts \\ []) do
    key_bin = generate_key(dir, name)

    host = opts[:host] || "127.0.0.1"

    csr = CSR.new(key_bin,
      "/C=US/ST=CA/L=San Francisco/O=Acme",
      extension_request: [
        Extension.subject_alt_name([host])])
    csr_path = Path.join(dir, "#{name}.csr")
    File.write!(csr_path, CSR.to_pem(csr))

    cert = csr
    |> CSR.public_key
    |> Certificate.new(
      "/C=US/ST=CA/L=San Francisco/O=Acme",
      ca, ca_key, extensions: [
        subject_alt_name: Extension.subject_alt_name([host])
      ]
    )
    cert_path = Path.join(dir, "#{name}.cert")
    File.write!(cert_path, Certificate.to_pem(cert))
  end
end
