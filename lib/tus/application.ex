defmodule Tus.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Tus.Plug.Cache, []}
    ]

    opts = [strategy: :one_for_one, name: Tus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
