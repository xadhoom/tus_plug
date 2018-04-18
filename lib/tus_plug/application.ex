defmodule TusPlug.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {TusPlug.Cache, []}
    ]

    opts = [strategy: :one_for_one, name: TusPlug.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
