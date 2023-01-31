defmodule Poolex.State do
  @moduledoc false
  defstruct busy_workers_state: nil,
            idle_workers_state: nil,
            worker_module: nil,
            worker_start_fun: nil,
            worker_args: [],
            waiting_callers: :queue.new(),
            monitor_id: nil,
            supervisor: nil

  @type t() :: %__MODULE__{
          busy_workers_state: Poolex.Workers.Behaviour.state(),
          idle_workers_state: Poolex.Workers.Behaviour.state(),
          worker_module: module(),
          worker_start_fun: atom(),
          worker_args: list(any()),
          waiting_callers: :queue.queue(),
          monitor_id: atom() | reference(),
          supervisor: pid()
        }
end
