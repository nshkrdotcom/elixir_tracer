defmodule ElixirTracer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ElixirTracer.Storage
    ]

    opts = [strategy: :one_for_one, name: ElixirTracer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
