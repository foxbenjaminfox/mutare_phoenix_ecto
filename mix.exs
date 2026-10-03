defmodule Mutare.Phoenix.Ecto.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/foxbenjaminfox/mutare_phoenix_ecto"

  def project do
    [
      app: :mutare_phoenix_ecto,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Mutare test selection for Phoenix.Ecto's SQL sandbox"
  end

  # Hex package metadata. Only runtime and doc artifacts ship — never the test
  # suite or fixtures.
  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Benjamin Fox"],
      links: %{
        "GitHub" => @source_url,
        "Mutare" => "https://hexdocs.pm/mutare",
        "Changelog" => "https://hexdocs.pm/mutare_phoenix_ecto/changelog.html"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp deps do
    [
      # `Mutare.CoverageAttribution`, the behaviour this package implements and the one
      # function (`attribute_to/1`) it calls.
      {:mutare, "~> 0.5.0"},
      # `Phoenix.Ecto.SQL.Sandbox.decode_metadata/1` reads what the test put in the request.
      {:phoenix_ecto, "~> 4.6"},
      {:telemetry, "~> 1.0"},
      # Read for a connected LiveView's `connect_info`, when the project has LiveView.
      {:phoenix_live_view, "~> 1.0", optional: true},
      # The tests serve a real Phoenix endpoint (Bandit, LiveView, which brings Phoenix)
      # whose sandbox plug allows requests into a real sandboxed repo, so they need all of
      # it, and a database.
      {:bandit, "~> 1.5", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:ecto_sql, "~> 3.12", only: :test},
      {:ecto_sqlite3, "~> 0.17", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # `mix check` is the single quality gate: formatting, lint, and type analysis.
  # Any non-zero step aborts the rest, so a green run means all three passed.
  defp aliases do
    [check: ["format --check-formatted", "credo", "dialyzer"]]
  end

  # The PLT lives in a cacheable, gitignored directory; `:mix` and `:ex_unit` are
  # pulled in because `mix.exs` and `test/support` participate in the analysis.
  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      flags: [:error_handling, :unmatched_returns, :extra_return]
    ]
  end

  # ExDoc configuration. `mix docs` renders to `doc/` (gitignored). README is the
  # landing page.
  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
