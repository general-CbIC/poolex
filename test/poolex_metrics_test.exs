defmodule PoolexMetricsTest do
  use Poolex.MetricsCase

  @tag telemetry_events: [[:poolex, :metrics, :pool_size]]
  test "pool size metrics" do
    start_supervised(
      {Poolex,
       [
         pool_id: :test_pool,
         worker_module: SomeWorker,
         workers_count: 5,
         pool_size_metrics: true
       ]}
    )

    assert_telemetry_event(
      [:poolex, :metrics, :pool_size],
      %{idle_workers_count: 5},
      %{pool_id: :test_pool}
    )
  end
end
