defmodule PoolexMetricsTest do
  use Poolex.MetricsCase

  import PoolHelpers

  alias Poolex.Private.Metrics

  @tag telemetry_events: [[:poolex, :metrics, :pool_size]]
  test "pool size metrics" do
    pool_id = SomeWorker

    start_pool(
      pool_id: pool_id,
      worker_module: SomeWorker,
      workers_count: 5,
      pool_size_metrics: true,
      max_overflow: 5
    )

    assert_telemetry_event(
      [:poolex, :metrics, :pool_size],
      %{idle_workers_count: 5, busy_workers_count: 0, overflowed: 0},
      %{pool_id: ^pool_id}
    )

    launch_long_task(pool_id)

    Metrics.dispatch_pool_size_metrics(pool_id)

    assert_telemetry_event(
      [:poolex, :metrics, :pool_size],
      %{idle_workers_count: 4, busy_workers_count: 1, overflowed: 0},
      %{pool_id: ^pool_id}
    )

    Enum.each(1..5, fn _ ->
      launch_long_task(pool_id)
    end)

    Metrics.dispatch_pool_size_metrics(pool_id)

    assert_telemetry_event(
      [:poolex, :metrics, :pool_size],
      %{idle_workers_count: 0, busy_workers_count: 6, overflowed: 1},
      %{pool_id: ^pool_id}
    )
  end
end
