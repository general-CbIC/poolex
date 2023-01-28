defmodule Poolex.MixProject do
  use Mix.Project

  def project do
    [
      app: :poolex,
      version: "0.2.1",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "The library for managing a pool of processes.",
      package: package(),
      deps: deps(),
      source_url: "https://github.com/general-CbIC/poolex",
      docs: docs()
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
      {:ex_check, "~> 0.15.0", only: [:dev], runtime: false},
      {:credo, ">= 0.0.0", only: [:dev], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev], runtime: false},
      {:doctor, ">= 0.0.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/general-CbIC/poolex"}
    ]
  end

  defp docs do
    [
      main: "Poolex",
      extras: ["README.md"]
    ]
  end
end
