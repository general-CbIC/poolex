defmodule Poolex.Private.Metrics do
  @moduledoc """
  Functions for dispatching metrics.
  """

  @doc """
  Dispatches metrics with current count of idle workers.
  """
  @spec dispatch_pool_size_metrics(Poolex.pool_id()) :: :ok
  def dispatch_pool_size_metrics(pool_id) do
    debug_info = Poolex.get_debug_info(pool_id)

    :telemetry.execute(
      [:poolex, :metrics, :pool_size],
      %{
        idle_workers_count: debug_info.idle_workers_count,
        busy_workers_count: debug_info.busy_workers_count,
        overflowed: convert_overflow_to_number(debug_info.overflow > 0)
      },
      %{pool_id: pool_id}
    )
  end

  @spec convert_overflow_to_number(boolean()) :: integer()
  defp convert_overflow_to_number(true), do: 1
  defp convert_overflow_to_number(false), do: 0

  @doc """
  Starts a telemetry poller for dispatching metrics.
  """
  @spec start_poller(list(Poolex.poolex_option())) :: GenServer.on_start()
  def start_poller(opts) do
    pool_id = Poolex.get_pool_id(opts)
    measurements = collect_measurements(opts)

    if measurements == [] do
      :ok
    else
      :telemetry_poller.start_link(
        measurements: measurements,
        period: :timer.seconds(1),
        name: :"#{pool_id}_metrics_poller"
      )
    end
  end

  @spec collect_measurements(list(Poolex.poolex_option())) :: list()
  defp collect_measurements(opts) do
    pool_id = Poolex.get_pool_id(opts)

    if Keyword.get(opts, :pool_size_metrics, false) do
      [
        {Poolex.Private.Metrics, :dispatch_pool_size_metrics, [pool_id]}
      ]
    else
      []
    end
  end
end
