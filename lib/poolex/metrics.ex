defmodule Poolex.Metrics do
  @moduledoc """
  Functions for dispatching metrics.
  """

  @spec dispatch_pool_size_metrics(Poolex.pool_id()) :: :ok
  def dispatch_pool_size_metrics(pool_id) do
    debug_info = Poolex.get_debug_info(pool_id)

    :telemetry.execute(
      [:poolex, :metrics, :pool_size],
      %{
        idle_workers_count: debug_info.idle_workers_count
      },
      %{pool_id: pool_id}
    )
  end
end
