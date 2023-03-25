defmodule PoolexExample.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Poolex,
       pool_id: :worker_pool,
       worker_module: PoolexExample.Worker,
       workers_count: 5,
       max_overflow: 2}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
