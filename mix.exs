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
      version: "1.2.0"
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
      {:telemetry, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      # Development dependencies
      {:credo, "1.7.11", only: [:dev], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev], runtime: false},
      {:doctor, ">= 0.0.0", only: [:dev], runtime: false},
      {:ex_check, "~> 0.16.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:makeup_diff, ">= 0.0.0", only: [:dev], runtime: false},
      {:styler, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib mix.exs LICENSE),
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://github.com/general-CbIC/poolex/blob/develop/CHANGELOG.md",
        "GitHub" => "https://github.com/general-CbIC/poolex",
        "Sponsor" => "https://github.com/sponsors/general-CbIC"
      },
      maintainers: ["Aleksandr Sysoev"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/guides/getting-started.cheatmd",
        "docs/guides/migration-from-poolboy.cheatmd",
        "docs/guides/example-of-use.cheatmd",
        "docs/guides/pool-metrics.cheatmd",
        "docs/guides/workers-and-callers-implementations.md",
        "docs/CONTRIBUTING.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("docs/guides/*md")
      ],
      skip_undefined_reference_warnings_on: ["Poolex.Private.State"]
    ]
  end
end
