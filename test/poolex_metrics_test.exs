defmodule PoolexMetricsTest do
  use Poolex.MetricsCase

  import PoolHelpers

  alias Poolex.Private.Metrics

  @tag telemetry_events: [[:poolex, :metrics, :pool_size]]
  test "pool size metrics" do
    pool_id = start_pool(worker_module: SomeWorker, workers_count: 5, pool_size_metrics: true)

    assert_telemetry_event(
      [:poolex, :metrics, :pool_size],
      %{idle_workers_count: 5},
      %{pool_id: ^pool_id}
    )

    launch_long_task(pool_id)

    Metrics.dispatch_pool_size_metrics(pool_id)

    assert_telemetry_event(
      [:poolex, :metrics, :pool_size],
      %{idle_workers_count: 4},
      %{pool_id: ^pool_id}
    )
  end
end
