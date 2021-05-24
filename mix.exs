defmodule TusPlug.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :tus_plug,
      version: "0.1.0",
      elixir: "~> 1.9",
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
      {:plug, "~> 1.11"},
      {:persistent_ets, "~> 0.2"},
      {:timex, "~> 3.2"},
      # development stuff,
      {:stream_data, "~> 0.5", only: :test},
      {:excoveralls, "~> 0.14", only: :test, runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 0.9", only: [:dev, :test], runtime: false}
    ]
  end
end
