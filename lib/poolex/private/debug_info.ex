defmodule Poolex.Private.DebugInfo do
  @moduledoc """
  Information with the current state of the pool.

  Can be used for debugging.
  """

  defstruct busy_workers_count: 0,
            busy_workers_impl: nil,
            busy_workers_pids: [],
            failed_to_start_workers_count: 0,
            idle_overflowed_workers_count: 0,
            idle_overflowed_workers_impl: nil,
            idle_overflowed_workers_pids: [],
            idle_workers_count: 0,
            idle_workers_impl: nil,
            idle_workers_pids: [],
            max_overflow: 0,
            overflow: 0,
            waiting_callers_impl: nil,
            waiting_callers: [],
            worker_args: [],
            worker_module: nil,
            worker_shutdown_delay: 0,
            worker_start_fun: nil

  @type t() :: %__MODULE__{
          busy_workers_count: non_neg_integer(),
          busy_workers_impl: module(),
          busy_workers_pids: list(pid()),
          failed_to_start_workers_count: non_neg_integer(),
          idle_workers_count: non_neg_integer(),
          idle_workers_impl: module(),
          idle_workers_pids: list(pid()),
          max_overflow: non_neg_integer(),
          overflow: non_neg_integer(),
          waiting_callers_impl: module(),
          waiting_callers: list(pid()),
          worker_args: list(any()),
          worker_module: module(),
          worker_shutdown_delay: timeout(),
          worker_start_fun: atom()
        }

  @doc """
  Returns detailed information about started pool.

  Primarily needed to help with debugging. **Avoid using this function in production.**

  ## Fields

      * `busy_workers_count` - how many workers are busy right now.
      * `busy_workers_impl` - implementation of busy workers.
      * `busy_workers_pids` - list of busy workers.
      * `failed_to_start_workers_count` - how many workers failed to start.
      * `idle_overflowed_workers_count` - how many idle overflowed workers are there.
      * `idle_overflowed_workers_impl` - implementation of idle overflowed workers.
      * `idle_overflowed_workers_pids` - list of idle overflowed workers.
      * `idle_workers_count` - how many workers are ready to work.
      * `idle_workers_impl` - implementation of idle workers.
      * `idle_workers_pids` - list of idle workers.
      * `max_overflow` - how many workers can be created over the limit.
      * `overflow` - current count of workers launched over limit.
      * `waiting_caller_pids` - list of callers processes.
      * `worker_args` - what parameters are used to start the worker.
      * `worker_module` - name of a module that describes a worker.
      * `worker_shutdown_delay` - how long to wait before shutting down a worker.
      * `worker_start_fun` - what function is used to start the worker.

  ## Examples

      iex> Poolex.start(pool_id: :my_pool_3, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> debug_info = %Poolex.Private.DebugInfo{} = Poolex.Private.DebugInfo.get_debug_info(:my_pool_3)
      iex> debug_info.busy_workers_count
      0
      iex> debug_info.idle_workers_count
      5
  """
  @spec get_debug_info(Poolex.pool_id()) :: t()
  def get_debug_info(pool_id) do
    GenServer.call(pool_id, :get_debug_info)
  end
end
