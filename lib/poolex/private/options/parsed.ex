defmodule Poolex.Private.Options.Parsed do
  @moduledoc false
  @enforce_keys [
    :busy_workers_impl,
    :failed_workers_retry_interval,
    :idle_overflowed_workers_impl,
    :idle_workers_impl,
    :max_overflow,
    :pool_id,
    :pool_size_metrics,
    :waiting_callers_impl,
    :worker_args,
    :worker_module,
    :worker_shutdown_delay,
    :worker_start_fun,
    :workers_count
  ]

  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          busy_workers_impl: module(),
          failed_workers_retry_interval: timeout(),
          idle_overflowed_workers_impl: module(),
          idle_workers_impl: module(),
          max_overflow: non_neg_integer(),
          pool_id: Poolex.pool_id(),
          pool_size_metrics: boolean(),
          waiting_callers_impl: module(),
          worker_args: list(any()),
          worker_module: module(),
          worker_shutdown_delay: timeout(),
          worker_start_fun: atom(),
          workers_count: non_neg_integer()
        }
end
