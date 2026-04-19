defmodule Poolex.Private.State do
  @moduledoc """
  Internal structure containing the state of the pool.

  Can be used for debugging.
  """

  @typedoc """
  A point in time expressed in milliseconds as returned by `System.monotonic_time(:millisecond)`.

  Only meaningful for measuring durations against other values obtained from `System.monotonic_time/1`
  — not comparable with `DateTime` or `Time`.
  """
  @type monotonic_time() :: integer()

  @enforce_keys [
    :failed_workers_retry_interval,
    :max_overflow,
    :max_pool_size,
    :min_pool_size,
    :pool_id,
    :supervisor,
    :worker_args,
    :worker_module,
    :worker_start_fun,
    :worker_shutdown_delay
  ]

  defstruct @enforce_keys ++
              [
                busy_workers_impl: nil,
                busy_workers_state: nil,
                failed_to_start_workers_count: 0,
                idle_overflowed_workers_impl: nil,
                idle_overflowed_workers_last_touches: %{},
                idle_overflowed_workers_state: nil,
                idle_workers_impl: nil,
                idle_workers_state: nil,
                manual_monitors: %{},
                monitors: %{},
                overflow: 0,
                waiting_callers_impl: nil,
                waiting_callers_state: nil
              ]

  @type t() :: %__MODULE__{
          busy_workers_impl: module(),
          busy_workers_state: nil | Poolex.Workers.Behaviour.state(),
          failed_to_start_workers_count: non_neg_integer(),
          failed_workers_retry_interval: timeout() | nil,
          idle_overflowed_workers_impl: module(),
          idle_overflowed_workers_last_touches: %{pid() => monotonic_time()},
          idle_overflowed_workers_state: nil | Poolex.Workers.Behaviour.state(),
          idle_workers_impl: module(),
          idle_workers_state: nil | Poolex.Workers.Behaviour.state(),
          manual_monitors: %{(worker_pid :: pid()) => {caller_pid :: pid(), monitor_pid :: pid()}},
          max_overflow: non_neg_integer(),
          max_pool_size: pos_integer() | :infinity,
          min_pool_size: non_neg_integer(),
          monitors: %{reference() => Poolex.Private.Monitoring.kind_of_process()},
          overflow: non_neg_integer(),
          pool_id: Poolex.pool_id(),
          supervisor: pid(),
          waiting_callers_impl: module(),
          waiting_callers_state: nil | Poolex.Callers.Behaviour.state(),
          worker_args: list(any()),
          worker_module: module(),
          worker_shutdown_delay: timeout(),
          worker_start_fun: atom()
        }
end
