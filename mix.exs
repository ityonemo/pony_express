defmodule PonyExpress.MixProject do
  use Mix.Project

  def project do
    [
      app: :pony_express,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env),
      description: "securely extend phoenix pubsub over SSL",
      package: package(),
      source_url: "https://github.com/ityonemo/pony_express"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.21.2", only: :dev, runtime: :false},
      {:phoenix_pubsub, "~> 1.1"}
    ]
  end

  defp package, do: [
    name: "pony_express",
    licenses: ["MIT"],
    links: %{"GitHub" => "https://github.com/ityonemo/pony_express"}
  ]
end
