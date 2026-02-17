defmodule PoolexExample.MetricsHandler do
  use Agent

  def start_link(_args) do
    Agent.start_link(fn -> false end, name: __MODULE__)
  end

  def turn_on_logs do
    Agent.update(__MODULE__, fn _state -> true end)
  end

  def turn_off_logs do
    Agent.update(__MODULE__, fn _state -> false end)
  end

  def handle_event([:poolex, :metrics, :pool_size], measurements, metadata, _config) do
    if current_state() do
      IO.puts("""
      [Pool: #{metadata.pool_id}]:
      - Idle workers: #{measurements.idle_workers_count}
      - Busy workers: #{measurements.busy_workers_count}
      - Overflowed: #{measurements.overflowed}
      """)
    end
  end

  defp current_state do
    Agent.get(__MODULE__, fn state -> state end)
  end
end
