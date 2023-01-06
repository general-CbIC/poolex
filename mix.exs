defmodule Poolex.MixProject do
  use Mix.Project

  def project do
    [
      app: :poolex,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "The library for managing a pool of processes.",
      package: package(),
      deps: deps(),
      source_url: "https://github.com/general-CbIC/poolex"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.6.7", runtime: false, optional: true}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/general-CbIC/poolex"}
    ]
  end
end
