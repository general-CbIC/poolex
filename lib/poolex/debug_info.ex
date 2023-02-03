defmodule Poolex.DebugInfo do
  @moduledoc """
  Information with the current state of the pool.

  Can be used for debugging.
  """

  defstruct busy_workers_count: 0,
            busy_workers_pids: [],
            idle_workers_count: 0,
            idle_workers_pids: [],
            worker_module: nil,
            worker_args: [],
            worker_start_fun: :start,
            waiting_callers: []

  @type t() :: %__MODULE__{
          busy_workers_count: non_neg_integer(),
          busy_workers_pids: list(pid()),
          idle_workers_count: non_neg_integer(),
          idle_workers_pids: list(pid()),
          worker_module: module(),
          worker_args: list(any()),
          worker_start_fun: atom(),
          waiting_callers: list(pid())
        }
end
