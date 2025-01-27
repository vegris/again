defmodule Again.MixProject do
  use Mix.Project

  def project do
    [
      app: :again,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:excoveralls, "~> 0.18.3", only: :test},
      {:ex_doc, "~> 0.36.1", only: :docs, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_local_path: "priv/plts",
      flags: ~w[error_handling extra_return missing_return underspecs unmatched_returns]a
    ]
  end

  defp docs do
    [
      main: "Again",
      extras: ["docs/Migrating from Retry.md", "docs/Problems with Retry.md"]
    ]
  end
end
