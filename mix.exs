defmodule OplogPublisher.MixProject do
  use Mix.Project

  def project do
    [
      app: :oplog_publisher,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {OplogPublisher.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mongodb_driver, "~> 1.5"},
      {:gnat, "~> 1.10"},
      {:broadway, "~> 1.2"},
      {:jason, "~> 1.4"}
    ]
  end
end
