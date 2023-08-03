defmodule Poolex.Private.DebugInfo do
  @moduledoc """
  Information with the current state of the pool.

  Can be used for debugging.
  """

  defstruct busy_workers_count: 0,
            busy_workers_impl: nil,
            busy_workers_pids: [],
            idle_workers_count: 0,
            idle_workers_impl: nil,
            idle_workers_pids: [],
            max_overflow: 0,
            overflow: 0,
            waiting_callers_impl: nil,
            waiting_callers: [],
            worker_args: [],
            worker_module: nil,
            worker_start_fun: nil

  @type t() :: %__MODULE__{
          busy_workers_count: non_neg_integer(),
          busy_workers_impl: module(),
          busy_workers_pids: list(pid()),
          idle_workers_count: non_neg_integer(),
          idle_workers_impl: module(),
          idle_workers_pids: list(pid()),
          max_overflow: non_neg_integer(),
          overflow: non_neg_integer(),
          waiting_callers_impl: module(),
          waiting_callers: list(pid()),
          worker_args: list(any()),
          worker_module: module(),
          worker_start_fun: atom()
        }
end
