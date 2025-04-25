defmodule Poolex.Private.State do
  @moduledoc """
  Internal structure containing the state of the pool.

  Can be used for debugging.
  """

  @enforce_keys [
    :failed_workers_retry_interval,
    :max_overflow,
    :pool_id,
    :supervisor,
    :worker_args,
    :worker_module,
    :worker_start_fun
  ]

  defstruct @enforce_keys ++
              [
                busy_workers_impl: nil,
                busy_workers_state: nil,
                failed_to_start_workers_count: 0,
                idle_workers_impl: nil,
                idle_workers_state: nil,
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
          idle_workers_impl: module(),
          idle_workers_state: nil | Poolex.Workers.Behaviour.state(),
          max_overflow: non_neg_integer(),
          monitors: %{reference() => Poolex.Private.Monitoring.kind_of_process()},
          overflow: non_neg_integer(),
          pool_id: Poolex.pool_id(),
          supervisor: pid(),
          waiting_callers_impl: module(),
          waiting_callers_state: nil | Poolex.Callers.Behaviour.state(),
          worker_args: list(any()),
          worker_module: module(),
          worker_start_fun: atom()
        }
end
