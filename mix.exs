defmodule PonyExpress.MixProject do
  use Mix.Project

  def project do
    [
      app: :pony_express,
      version: "0.2.1",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env),
      description: "securely extend phoenix pubsub over SSL",
      package: package(),
      source_url: "https://github.com/ityonemo/pony_express"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.21.2", only: :dev, runtime: :false},
      {:phoenix_pubsub, "~> 1.1"},
      {:plug_crypto, "~> 1.1.2"},

      # uses x509 for cert generation
      {:x509, "~> 0.8.0", only: [:dev, :test]},
      # uses ERPS for its TCP/TLS abstractions (this may be broken out later).
      {:erps, "~> 0.3.4"}
    ]
  end

  defp package, do: [
    name: "pony_express",
    licenses: ["MIT"],
    links: %{"GitHub" => "https://github.com/ityonemo/pony_express"}
  ]
end
