defmodule PoolexExample.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Poolex,
       pool_id: :worker_pool,
       worker_module: PoolexExample.Worker,
       workers_count: 5,
       max_overflow: 2,
       pool_size_metrics: true}
    ]

    :telemetry.attach(
      "poolex_metrics",
      [:poolex, :metrics, :pool_size],
      &PoolexExample.MetricsHandler.handle_event/4,
      nil
    )

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
