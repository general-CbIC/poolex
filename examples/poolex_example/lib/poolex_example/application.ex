defmodule PoolexExample.Application do
  @moduledoc false

  use Application

  defp worker_config do
    [
      worker_module: PoolexExample.Worker,
      workers_count: 5,
      max_overflow: 2
    ]
  end

  def start(_type, _args) do
    children = [
      %{
        id: :worker_pool,
        start: {Poolex, :start_link, [:worker_pool, worker_config()]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
