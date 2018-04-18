defmodule TusPlug.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :tus_plug,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {TusPlug.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.5"},
      {:persistent_ets, "~> 0.1"},
      # development stuff,
      {:stream_data, "~> 0.4", only: :test},
      {:excoveralls, "~> 0.8", only: :test, runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false}
    ]
  end
end
