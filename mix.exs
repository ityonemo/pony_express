defmodule PonyExpress.MixProject do
  use Mix.Project

  def project do
    [
      app: :pony_express,
      version: "0.4.3",
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
      {:credo, "~> 1.2", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 0.5.1", only: :dev, runtime: false},
      {:ex_doc, "~> 0.21.2", only: :dev, runtime: :false},
      {:multiverses, "~> 0.5.2", runtime: :false},
      {:multiverses_pubsub, "~> 0.1.0", runtime: :false},
      {:net_address, "~> 0.2.0", only: :test},

      # direct dependencies
      {:phoenix_pubsub, "~> 2.0"},
      # connection and transport primitives
      {:connection, "~> 1.0"},
      {:transport, "~> 0.1.0"},
      # over-the-wire encoding
      {:plug_crypto, "~> 1.1.2"},
      # uses x509 for cert generation
      {:x509, "~> 0.8.0", only: [:dev, :test]},
    ]
  end

  defp package, do: [
    name: "pony_express",
    licenses: ["MIT"],
    links: %{"GitHub" => "https://github.com/ityonemo/pony_express"}
  ]
end
