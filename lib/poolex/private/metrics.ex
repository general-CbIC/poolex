defmodule Poolex.Private.Metrics do
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

  @spec start_poller(Poolex.pool_id()) :: GenServer.on_start()
  def start_poller(pool_id) do
    name = :"#{pool_id}_metrics_poller"

    :telemetry_poller.start_link(
      measurements: [
        {Poolex.Private.Metrics, :dispatch_pool_size_metrics, [pool_id]}
      ],
      period: :timer.seconds(1),
      name: name
    )
  end
end
