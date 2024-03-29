defmodule PoolexExample.MetricsHandler do
  def handle_event([:poolex, :metrics, :pool_size], measurements, metadata, _config) do
    IO.puts("""
    [Pool: #{metadata.pool_id}]:
    - Idle workers: #{measurements.idle_workers_count}
    - Busy workers: #{measurements.busy_workers_count}
    - Overflowed: #{measurements.overflowed}
    """)
  end
end
