defmodule Poolex.State do
  @moduledoc false
  defstruct busy_workers_count: 0,
            busy_workers_pids: [],
            idle_workers_count: 0,
            idle_workers_pids: [],
            worker_module: nil,
            worker_start_fun: nil,
            worker_args: [],
            waiting_callers: :queue.new(),
            monitor_id: nil,
            supervisor: nil

  @type t() :: %__MODULE__{
          busy_workers_count: non_neg_integer(),
          busy_workers_pids: list(pid()),
          idle_workers_count: non_neg_integer(),
          idle_workers_pids: list(pid()),
          worker_module: module(),
          worker_start_fun: atom(),
          worker_args: list(any()),
          waiting_callers: :queue.queue(),
          monitor_id: atom() | reference(),
          supervisor: pid()
        }
end
