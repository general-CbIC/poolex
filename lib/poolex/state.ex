defmodule Poolex.State do
  @moduledoc """
  Internal structure containing the state of the pool.

  Can be used for debugging.
  """

  defstruct busy_workers_state: nil,
            idle_workers_impl: nil,
            idle_workers_state: nil,
            max_overflow: 0,
            monitor_id: nil,
            overflow: 0,
            pool_id: nil,
            supervisor: nil,
            waiting_callers_impl: nil,
            waiting_callers_state: nil,
            worker_args: [],
            worker_module: nil,
            worker_start_fun: nil

  @type t() :: %__MODULE__{
          busy_workers_state: Poolex.Workers.Behaviour.state(),
          idle_workers_impl: module(),
          idle_workers_state: Poolex.Workers.Behaviour.state(),
          max_overflow: non_neg_integer(),
          monitor_id: atom() | reference(),
          overflow: non_neg_integer(),
          pool_id: Poolex.pool_id(),
          supervisor: pid(),
          waiting_callers_impl: module(),
          waiting_callers_state: Poolex.Callers.Behaviour.state(),
          worker_args: list(any()),
          worker_module: module(),
          worker_start_fun: atom()
        }
end
