defmodule Poolex.MixProject do
  use Mix.Project

  def project do
    [
      app: :poolex,
      deps: deps(),
      description: "The library for managing pools of workers.",
      docs: docs(),
      elixir: "~> 1.7",
      elixirc_options: [
        warnings_as_errors: true
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      source_url: "https://github.com/general-CbIC/poolex",
      start_permanent: Mix.env() == :prod,
      version: "0.5.1"
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
      {:credo, ">= 0.0.0", only: [:dev], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev], runtime: false},
      {:doctor, ">= 0.0.0", only: [:dev], runtime: false},
      {:ex_check, "~> 0.15.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/general-CbIC/poolex",
        "Changelog" => "https://github.com/general-CbIC/poolex/blob/develop/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "docs/CONTRIBUTING.md",
        "docs/guides.md",
        "docs/guides/custom-implementations.md",
        "docs/guides/migration-from-poolboy.md",
        "docs/guides/example-of-use.md",
        "docs/guides/getting-started.md",
        "README.md"
      ]
    ]
  end
end
