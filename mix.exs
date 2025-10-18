defmodule ElixirTracer.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/elixir_tracer"

  def project do
    [
      app: :elixir_tracer,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ElixirTracer",
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ElixirTracer.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4", optional: true},

      # Testing with Supertester
      {:supertester, "~> 0.2.1", only: :test},

      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    """
    Local-first observability for Elixir with New Relic API parity.
    A complete tracing and observability solution that works entirely offline
    while maintaining compatibility with New Relic's API surface.
    """
  end

  defp package do
    [
      name: "elixir_tracer",
      description: description(),
      files:
        ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md API_EXAMPLES.md NEW_RELIC_FEATURE_ANALYSIS.md assets),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Online documentation" => "https://hexdocs.pm/elixir_tracer",
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"],
      exclude_patterns: [
        "priv/plts",
        ".DS_Store"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "ElixirTracer",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/elixir_tracer.svg",
      extras: [
        "README.md",
        "API_EXAMPLES.md",
        "NEW_RELIC_FEATURE_ANALYSIS.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        "Getting Started": ["README.md", "API_EXAMPLES.md"],
        Reference: ["NEW_RELIC_FEATURE_ANALYSIS.md"],
        "Release Notes": ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        "Core API": [
          ElixirTracer,
          ElixirTracer.Transaction,
          ElixirTracer.OtherTransaction,
          ElixirTracer.Span,
          ElixirTracer.Error,
          ElixirTracer.Metric,
          ElixirTracer.Query,
          ElixirTracer.DistributedTrace
        ],
        Reporters: [
          ElixirTracer.Transaction.Reporter,
          ElixirTracer.Span.Reporter,
          ElixirTracer.Error.Reporter,
          ElixirTracer.Metric.Reporter,
          ElixirTracer.CustomEvent.Reporter
        ],
        "Telemetry Handlers": [
          ElixirTracer.Telemetry.PhoenixHandler,
          ElixirTracer.Telemetry.PlugHandler,
          ElixirTracer.Telemetry.EctoHandler
        ],
        Infrastructure: [
          ElixirTracer.Application,
          ElixirTracer.Storage
        ]
      ]
    ]
  end
end
