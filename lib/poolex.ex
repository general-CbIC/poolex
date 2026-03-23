defmodule Poolex do
  @moduledoc """
  ## Usage

  In the most typical use of Poolex, you only need to start pool of workers as a child of your application.

  ```elixir
  children = [
    {Poolex,
      pool_id: :worker_pool,
      worker_module: SomeWorker,
      workers_count: 5}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
  ```

  Then you can execute any code on the workers with `run/3`:

  ```elixir
  Poolex.run(:worker_pool, &(is_pid?(&1)), checkout_timeout: 1_000)
  {:ok, true}
  ```

  For more information see [Getting Started](https://hexdocs.pm/poolex/getting-started.html)
  """

  use GenServer, shutdown: :infinity

  alias Poolex.Private.BusyWorkers
  alias Poolex.Private.DebugInfo
  alias Poolex.Private.IdleOverflowedWorkers
  alias Poolex.Private.IdleWorkers
  alias Poolex.Private.Metrics
  alias Poolex.Private.Monitoring
  alias Poolex.Private.Options.Parser, as: OptionsParser
  alias Poolex.Private.State
  alias Poolex.Private.WaitingCallers

  require Logger

  @default_checkout_timeout to_timeout(second: 5)

  @poolex_options_table """
  | Option                           | Description                                                        | Example                         | Default value                     |
  |----------------------------------|--------------------------------------------------------------------|---------------------------------|-----------------------------------|
  | `busy_workers_impl`              | Module that describes how to work with busy workers                | `SomeBusyWorkersImpl`           | `Poolex.Workers.Impl.List`        |
  | `failed_workers_retry_interval`  | Interval in milliseconds between retry attempts for failed workers | `5_000`                         | `1_000`                           |
  | `idle_workers_impl`              | Module that describes how to work with idle workers                | `SomeIdleWorkersImpl`           | `Poolex.Workers.Impl.List`        |
  | `idle_overflowed_workers_impl`   | Module that describes how to work with idle overflowed workers     | `SomeIdleOverflowedWorkersImpl` | `Poolex.Workers.Impl.List`        |
  | `max_overflow`                   | How many workers can be created over the limit                     | `2`                             | `0`                               |
  | `max_pool_size`                  | Maximum total workers count in the pool                            | `100`                           | `:infinity`                       |
  | `min_pool_size`                  | Minimum total workers count in the pool                            | `50`                            | `0`                               |
  | `worker_shutdown_delay`          | Delay (ms) before shutting down overflow worker after release      | `5000`                          | `0`                               |
  | `pool_id`                        | Identifier by which you will access the pool                       | `:my_pool`                      | `worker_module` value             |
  | `pool_size_metrics`              | Whether to dispatch pool size metrics                              | `true`                          | `false`                           |
  | `waiting_callers_impl`           | Module that describes how to work with callers queue               | `WaitingCallersImpl`            | `Poolex.Callers.Impl.ErlangQueue` |
  | `worker_args`                    | List of arguments passed to the start function                     | `[:gg, "wp"]`                   | `[]`                              |
  | `worker_module`                  | Name of module that implements our worker                          | `MyApp.Worker`                  | **option is required**            |
  | `worker_start_fun`               | Name of the function that starts the worker                        | `:run`                          | `:start_link`                     |
  | `workers_count`                  | How many workers should be running in the pool                     | `5`                             | **option is required**            |
  """

  @typedoc """
  Any valid GenServer's name. It may be an atom like `:some_pool` or a tuple {:via, Registry, {MyApp.Registry, "pool"}
  if you want to use Registry.
  """
  @type pool_id() :: GenServer.name() | pid()
  @typedoc """
  #{@poolex_options_table}
  """
  @type poolex_option() ::
          {:busy_workers_impl, module()}
          | {:failed_workers_retry_interval, timeout()}
          | {:idle_overflowed_workers_impl, module()}
          | {:idle_workers_impl, module()}
          | {:max_overflow, non_neg_integer()}
          | {:max_pool_size, pos_integer() | :infinity}
          | {:min_pool_size, non_neg_integer()}
          | {:pool_id, pool_id()}
          | {:pool_size_metrics, boolean()}
          | {:waiting_callers_impl, module()}
          | {:worker_args, list(any())}
          | {:worker_module, module()}
          | {:worker_shutdown_delay, timeout()}
          | {:worker_start_fun, atom()}
          | {:workers_count, non_neg_integer()}

  @typedoc """
  Process id of `worker`.

  **Workers** are processes launched in a pool.
  """
  @type worker() :: pid()

  @typedoc """
  | Option           | Description                                        | Example  | Default value                  |
  |------------------|----------------------------------------------------|----------|--------------------------------|
  | checkout_timeout | How long we can wait for a worker on the call site | `60_000` | `#{@default_checkout_timeout}` |
  """
  @type run_option() :: {:checkout_timeout, timeout()}

  @spawn_opts [priority: :high]

  @doc """
  Starts a Poolex process without links (outside of a supervision tree).

  See start_link/1 for more information.

  ## Examples

      iex> Poolex.start(pool_id: :my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> %Poolex.Private.State{worker_module: worker_module} = :sys.get_state(:my_pool)
      iex> worker_module
      Agent
  """
  @spec start(list(poolex_option())) :: GenServer.on_start()
  def start(opts) do
    GenServer.start(__MODULE__, opts, name: OptionsParser.parse_pool_id(opts), spawn_opt: @spawn_opts)
  end

  @doc """
  Starts a Poolex process linked to the current process.

  This is often used to start the Poolex as part of a supervision tree.

  After the process is started, you can access it using the previously specified `pool_id`.

  ## Options

  #{@poolex_options_table}

  ## Examples

      iex> Poolex.start_link(pool_id: :other_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> %Poolex.Private.State{worker_module: worker_module} = :sys.get_state(:other_pool)
      iex> worker_module
      Agent
  """
  @spec start_link(list(poolex_option())) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: OptionsParser.parse_pool_id(opts), spawn_opt: @spawn_opts)
  end

  @doc """
  Returns a specification to start this module under a supervisor.

  ## Options

  #{@poolex_options_table}

  ## Examples

      children = [
        Poolex.child_spec(worker_module: SomeWorker, workers_count: 5),
        # or in another way
        {Poolex, worker_module: SomeOtherWorker, workers_count: 5}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """
  @spec child_spec(list(poolex_option())) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: OptionsParser.parse_pool_id(opts), start: {Poolex, :start_link, [opts]}}
  end

  @doc """
  The main function for working with the pool.

  It takes a pool identifier, a function that takes a worker process id as an argument and returns any value.
  When executed, an attempt is made to find a free worker with specified timeout (5 seconds by default).
  You can set the timeout using the `checkout_timeout` option.

  Returns:
    * `{:ok, result}` if the worker was found and the function was executed successfully.
    * `{:error, :checkout_timeout}` if no free worker was found before the timeout.

  ## Examples

      iex> Poolex.start_link(pool_id: :some_pool, worker_module: Agent, worker_args: [fn -> 5 end], workers_count: 1)
      iex> Poolex.run(:some_pool, fn pid -> Agent.get(pid, &(&1)) end)
      {:ok, 5}
  """
  @spec run(pool_id(), (worker :: pid() -> any()), list(run_option())) ::
          {:ok, any()} | {:error, :checkout_timeout}
  def run(pool_id, fun, options \\ []) do
    case acquire(pool_id, options) do
      {:ok, worker_pid} ->
        try do
          {:ok, fun.(worker_pid)}
        after
          release(pool_id, worker_pid)
        end

      {:error, :checkout_timeout} ->
        {:error, :checkout_timeout}
    end
  end

  @doc """
  Acquires a worker from the pool for manual management.

  This function checks out a worker from the pool and returns its PID. Unlike `run/3`,
  the worker must be manually released using `release/2`. If the calling process crashes
  before releasing the worker, it will be automatically returned to the pool.

  This is useful for long-running operations where you need to hold onto a worker
  for an extended period, such as maintaining a database connection for the lifetime
  of a TCP session.

  ## Options

  Same as `run/3`:
    * `checkout_timeout` - How long to wait for a worker (default: #{@default_checkout_timeout}ms)

  ## Returns

    * `{:ok, worker_pid}` - Successfully acquired a worker
    * `{:error, :checkout_timeout}` - No worker available within timeout

  ## Examples

      iex> Poolex.start_link(pool_id: :my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 2)
      iex> {:ok, worker} = Poolex.acquire(:my_pool)
      iex> Agent.get(worker, & &1)
      0
      iex> Poolex.release(:my_pool, worker)
      :ok

  ## Safety

  If the caller process crashes before calling `release/2`, the worker will be automatically
  killed and restarted by the supervisor. This ensures that the next caller gets a clean worker,
  not one potentially stuck in a long-running operation.

  For graceful cleanup, always explicitly call `release/2` when done with the worker.

  ## Multiple Workers

  A single process can acquire multiple workers from the same pool:

      {:ok, worker1} = Poolex.acquire(:my_pool)
      {:ok, worker2} = Poolex.acquire(:my_pool)
      # ... use both workers ...
      Poolex.release(:my_pool, worker1)
      Poolex.release(:my_pool, worker2)
  """
  @spec acquire(pool_id(), list(run_option())) :: {:ok, worker()} | {:error, :checkout_timeout}
  def acquire(pool_id, options \\ []) do
    checkout_timeout = Keyword.get(options, :checkout_timeout, @default_checkout_timeout)

    case get_idle_worker(pool_id, checkout_timeout) do
      {:ok, worker_pid} ->
        GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})
        {:ok, worker_pid}

      {:error, :checkout_timeout} ->
        {:error, :checkout_timeout}
    end
  end

  @doc """
  Releases a manually acquired worker back to the pool.

  This function returns a worker that was previously acquired with `acquire/2`
  back to the pool, making it available for other callers.

  ## Parameters

    * `pool_id` - The pool identifier
    * `worker_pid` - The PID of the worker to release

  ## Returns

    * `:ok` - Always returns `:ok`, even if the worker was already released or doesn't exist

  ## Examples

      {:ok, worker} = Poolex.acquire(:my_pool)
      # ... use worker ...
      Poolex.release(:my_pool, worker)

  ## Notes

    * It's safe to call `release/2` multiple times for the same worker
    * If there are callers waiting for a worker, the released worker is provided to them
    * Otherwise, the worker is returned to the idle pool
    * The monitor process created during `acquire/2` is automatically cleaned up
  """
  @spec release(pool_id(), worker()) :: :ok
  def release(pool_id, worker_pid) do
    GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})
    :ok
  end

  @spec get_idle_worker(pool_id(), timeout()) :: {:ok, worker()} | {:error, :checkout_timeout}
  defp get_idle_worker(pool_id, checkout_timeout) do
    caller_reference = make_ref()

    try do
      GenServer.call(pool_id, {:get_idle_worker, caller_reference}, checkout_timeout)
    catch
      :exit, {:timeout, {GenServer, :call, [_pool_id, {:get_idle_worker, ^caller_reference}, _timeout]}} ->
        {:error, :checkout_timeout}
    after
      GenServer.cast(pool_id, {:cancel_waiting, caller_reference})
    end
  end

  @doc """
  Adds some idle workers to existing pool.
  """
  @spec add_idle_workers!(pool_id(), pos_integer()) :: :ok | no_return()
  def add_idle_workers!(_pool_id, workers_count) when workers_count < 1 do
    message = "workers_count must be positive number, received: #{inspect(workers_count)}"

    raise ArgumentError, message
  end

  def add_idle_workers!(pool_id, workers_count) when is_integer(workers_count) do
    GenServer.call(pool_id, {:add_idle_workers, workers_count})
  end

  @doc """
  Removes some idle workers from existing pool.
  If the number of workers to remove is greater than the number of idle workers, all idle workers will be removed.
  """
  @spec remove_idle_workers!(pool_id(), pos_integer()) :: :ok | no_return()
  def remove_idle_workers!(_pool_id, workers_count) when workers_count < 1 do
    message = "workers_count must be positive number, received: #{inspect(workers_count)}"

    raise ArgumentError, message
  end

  def remove_idle_workers!(pool_id, workers_count) when is_integer(workers_count) do
    GenServer.call(pool_id, {:remove_idle_workers, workers_count})
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    parsed_options = OptionsParser.parse(opts)

    {:ok, supervisor} = Poolex.Private.Supervisor.start_link()

    state =
      %State{
        failed_workers_retry_interval: parsed_options.failed_workers_retry_interval,
        max_overflow: parsed_options.max_overflow,
        max_pool_size: parsed_options.max_pool_size,
        min_pool_size: parsed_options.min_pool_size,
        pool_id: parsed_options.pool_id,
        supervisor: supervisor,
        worker_args: parsed_options.worker_args,
        worker_module: parsed_options.worker_module,
        worker_start_fun: parsed_options.worker_start_fun,
        worker_shutdown_delay: parsed_options.worker_shutdown_delay
      }

    {initial_workers_pids, state} = start_workers(parsed_options.workers_count, state)

    state =
      state
      |> IdleWorkers.init(parsed_options.idle_workers_impl, initial_workers_pids)
      |> BusyWorkers.init(parsed_options.busy_workers_impl)
      |> IdleOverflowedWorkers.init(parsed_options.idle_overflowed_workers_impl)
      |> WaitingCallers.init(parsed_options.waiting_callers_impl)

    {:ok, state, {:continue, opts}}
  end

  @impl GenServer
  def handle_continue(opts, state) do
    Metrics.start_poller(opts)

    schedule_retry_failed_workers(state)

    {:noreply, state}
  end

  @spec base_workers_count(State.t()) :: non_neg_integer()
  defp base_workers_count(%State{} = state) do
    IdleWorkers.count(state) + BusyWorkers.count(state)
  end

  @spec available_to_add_count(State.t(), non_neg_integer()) :: non_neg_integer()
  defp available_to_add_count(%State{max_pool_size: :infinity}, workers_count), do: workers_count

  defp available_to_add_count(%State{max_pool_size: max} = state, workers_count) do
    max(0, min(workers_count, max - base_workers_count(state)))
  end

  @spec available_to_remove_count(State.t(), non_neg_integer()) :: non_neg_integer()
  defp available_to_remove_count(%State{min_pool_size: 0}, workers_count), do: workers_count

  defp available_to_remove_count(%State{min_pool_size: min} = state, workers_count) do
    max(0, min(workers_count, base_workers_count(state) - min))
  end

  @spec start_workers(non_neg_integer(), State.t()) :: {[pid], State.t()}
  defp start_workers(0, state) do
    {[], state}
  end

  defp start_workers(workers_count, state) when is_integer(workers_count) and workers_count >= 1 do
    Enum.reduce(1..workers_count, {[], state}, fn _iterator, {workers_pids, state} ->
      case start_worker(state) do
        {:ok, worker_pid, state} ->
          {[worker_pid | workers_pids], state}

        {:error, :failed_to_start_worker, state} ->
          {workers_pids, state}
      end
    end)
  end

  defp start_workers(workers_count, _state) do
    msg = "workers_count must be non negative integer, received: #{inspect(workers_count)}"
    raise ArgumentError, msg
  end

  @spec start_worker(State.t()) :: {:ok, pid(), State.t()} | {:error, :failed_to_start_worker, State.t()}
  defp start_worker(%State{} = state) do
    case DynamicSupervisor.start_child(state.supervisor, %{
           id: make_ref(),
           start: {state.worker_module, state.worker_start_fun, state.worker_args},
           restart: :temporary
         }) do
      {:ok, worker_pid} ->
        state = Monitoring.add(state, worker_pid, :worker)
        {:ok, worker_pid, state}

      {:error, reason} ->
        Logger.error("[Poolex] Failed to start worker. Reason: #{inspect(reason)}")
        state = %{state | failed_to_start_workers_count: state.failed_to_start_workers_count + 1}
        {:error, :failed_to_start_worker, state}
    end
  end

  @spec stop_worker(Supervisor.supervisor(), pid()) :: :ok | {:error, :not_found}
  defp stop_worker(supervisor, worker_pid) do
    DynamicSupervisor.terminate_child(supervisor, worker_pid)
  end

  @impl GenServer
  def handle_call({:get_idle_worker, caller_reference}, {from_pid, _} = caller, %State{} = state) do
    cond do
      not IdleOverflowedWorkers.empty?(state) ->
        # If there are overflowed idle workers, we can immediately provide one to the caller
        {overflowed_worker_pid, state} = IdleOverflowedWorkers.pop(state)
        state = BusyWorkers.add(state, overflowed_worker_pid)

        {:reply, {:ok, overflowed_worker_pid}, state}

      not IdleWorkers.empty?(state) ->
        # If there are idle workers, we can immediately provide one to the caller
        {idle_worker_pid, state} = IdleWorkers.pop(state)
        state = BusyWorkers.add(state, idle_worker_pid)

        {:reply, {:ok, idle_worker_pid}, state}

      state.overflow < state.max_overflow ->
        # We can create a new worker if we are not at the max overflow limit
        case start_worker(state) do
          {:ok, new_worker, state} ->
            # When worker created successfully
            state = BusyWorkers.add(state, new_worker)

            {:reply, {:ok, new_worker}, %{state | overflow: state.overflow + 1}}

          # When something went wrong, the caller will wait while worker retries to start
          {:error, :failed_to_start_worker, state} ->
            state =
              state
              |> Monitoring.add(from_pid, :waiting_caller)
              |> WaitingCallers.add(%Poolex.Caller{reference: caller_reference, from: caller})

            {:noreply, state}
        end

      true ->
        # We can't provide a worker immediately, so we need to add the caller to the waiting list
        state =
          state
          |> Monitoring.add(from_pid, :waiting_caller)
          |> WaitingCallers.add(%Poolex.Caller{reference: caller_reference, from: caller})

        {:noreply, state}
    end
  end

  def handle_call({:register_manual_acquisition, caller_pid, worker_pid}, _from, %State{} = state) do
    monitor_pid = start_manual_monitor(state.pool_id, caller_pid, worker_pid)
    new_state = put_in(state.manual_monitors[worker_pid], {caller_pid, monitor_pid})
    {:reply, :ok, new_state}
  end

  def handle_call(:get_debug_info, _from, %State{} = state) do
    idle_workers_count = IdleWorkers.count(state)
    busy_workers_count = BusyWorkers.count(state)

    debug_info = %DebugInfo{
      busy_workers_count: busy_workers_count,
      busy_workers_impl: state.busy_workers_impl,
      busy_workers_pids: BusyWorkers.to_list(state),
      failed_to_start_workers_count: state.failed_to_start_workers_count,
      idle_overflowed_workers_count: IdleOverflowedWorkers.count(state),
      idle_overflowed_workers_impl: state.idle_overflowed_workers_impl,
      idle_overflowed_workers_pids: IdleOverflowedWorkers.to_list(state),
      idle_workers_count: idle_workers_count,
      idle_workers_impl: state.idle_workers_impl,
      idle_workers_pids: IdleWorkers.to_list(state),
      max_overflow: state.max_overflow,
      max_pool_size: state.max_pool_size,
      min_pool_size: state.min_pool_size,
      overflow: state.overflow,
      total_workers_count: idle_workers_count + busy_workers_count,
      waiting_callers: WaitingCallers.to_list(state),
      waiting_callers_impl: state.waiting_callers_impl,
      worker_args: state.worker_args,
      worker_module: state.worker_module,
      worker_shutdown_delay: state.worker_shutdown_delay,
      worker_start_fun: state.worker_start_fun
    }

    {:reply, debug_info, state}
  end

  @impl GenServer
  def handle_call({:add_idle_workers, workers_count}, _from, %State{} = state) do
    allowed = available_to_add_count(state, workers_count)
    skipped = workers_count - allowed

    if skipped > 0 do
      Logger.error("Failed to add #{skipped} worker(s): max_pool_size limit of #{state.max_pool_size} reached")
    end

    {workers, state} = start_workers(allowed, state)

    state =
      Enum.reduce(workers, state, fn worker, acc_state ->
        if WaitingCallers.empty?(acc_state) do
          IdleWorkers.add(acc_state, worker)
        else
          acc_state
          |> BusyWorkers.add(worker)
          |> provide_worker_to_waiting_caller(worker)
        end
      end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:remove_idle_workers, workers_count}, _from, %State{} = state) do
    # removable is capped by idle count (can't remove workers that aren't idle)
    removable = min(workers_count, IdleWorkers.count(state))
    allowed = available_to_remove_count(state, removable)

    skipped = removable - allowed

    if skipped > 0 do
      Logger.error("Failed to remove #{skipped} worker(s): min_pool_size limit of #{state.min_pool_size} reached")
    end

    new_state =
      state
      |> IdleWorkers.to_list()
      |> Enum.take(allowed)
      |> Enum.reduce(state, fn worker, acc_state ->
        IdleWorkers.remove(acc_state, worker)
      end)

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_cast({:release_busy_worker, worker}, %State{} = state) do
    if WaitingCallers.empty?(state) do
      new_state = release_busy_worker(state, worker)
      {:noreply, new_state}
    else
      new_state = provide_worker_to_waiting_caller(state, worker)
      {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_cast({:release_manual_worker, caller_pid, worker_pid}, %State{} = state) do
    # Check if caller is the owner and clean up monitor
    {state, caller_is_owner} =
      case Map.get(state.manual_monitors, worker_pid) do
        nil ->
          # Worker not in manual_monitors
          {state, false}

        {^caller_pid, monitor_pid} ->
          # Caller is the owner, kill monitor and remove from map
          Process.exit(monitor_pid, :kill)
          new_state = %{state | manual_monitors: Map.delete(state.manual_monitors, worker_pid)}
          {new_state, true}

        {_other_caller, _monitor_pid} ->
          # Different caller owns this worker
          {state, false}
      end

    # Only release worker if caller was the owner
    new_state =
      if caller_is_owner do
        if WaitingCallers.empty?(state) do
          release_busy_worker(state, worker_pid)
        else
          provide_worker_to_waiting_caller(state, worker_pid)
        end
      else
        state
      end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:stop_worker, worker_pid}, %State{} = state) do
    stop_worker(state.supervisor, worker_pid)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:cleanup_manual_monitor, worker_pid}, %State{} = state) do
    # Clean up manual monitor when worker is killed due to caller crash
    state =
      case Map.get(state.manual_monitors, worker_pid) do
        nil ->
          state

        {_caller_pid, monitor_pid} ->
          Process.exit(monitor_pid, :kill)
          %{state | manual_monitors: Map.delete(state.manual_monitors, worker_pid)}
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:cancel_waiting, caller_reference}, %State{} = state) do
    {:noreply, WaitingCallers.remove_by_reference(state, caller_reference)}
  end

  @impl GenServer
  def handle_info({:DOWN, monitoring_reference, _process, dead_process_pid, _reason}, %State{} = state) do
    case Monitoring.remove(state, monitoring_reference) do
      {:worker, state} ->
        {:noreply, handle_down_worker(state, dead_process_pid)}

      {:waiting_caller, state} ->
        {:noreply, handle_down_waiting_caller(state, dead_process_pid)}
    end
  end

  @impl GenServer
  def handle_info(:retry_failed_workers, state) do
    # Try to start workers that failed to initialize
    state =
      if state.failed_to_start_workers_count > 0 do
        retry_failed_workers(state)
      else
        state
      end

    schedule_retry_failed_workers(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:delayed_stop_worker, worker}, %State{} = state) do
    if IdleOverflowedWorkers.expired?(state, worker) do
      # Stop the worker if it has been idle for too long
      stop_worker(state.supervisor, worker)

      {:noreply, IdleOverflowedWorkers.remove(state, worker)}
    else
      # Otherwise, just ignore the message
      {:noreply, state}
    end
  end

  @spec release_busy_worker(State.t(), worker()) :: State.t()
  defp release_busy_worker(%State{} = state, worker) do
    if BusyWorkers.member?(state, worker) do
      state = BusyWorkers.remove(state, worker)

      if state.overflow > 0 do
        release_overflowed_worker(state, worker)
      else
        IdleWorkers.add(state, worker)
      end
    else
      state
    end
  end

  defp release_overflowed_worker(%State{} = state, worker) do
    if state.worker_shutdown_delay > 0 do
      # We add 10 ms to the delay to ensure that message will be processed after the expiration
      Process.send_after(self(), {:delayed_stop_worker, worker}, state.worker_shutdown_delay + 10)

      IdleOverflowedWorkers.add(state, worker)
    else
      stop_worker(state.supervisor, worker)

      state
    end
  end

  @spec provide_worker_to_waiting_caller(State.t(), worker()) :: State.t()
  defp provide_worker_to_waiting_caller(%State{} = state, worker) do
    {caller, state} = WaitingCallers.pop(state)

    GenServer.reply(caller.from, {:ok, worker})

    state
  end

  @spec handle_down_worker(State.t(), pid()) :: State.t()
  defp handle_down_worker(%State{} = state, dead_process_pid) do
    state =
      state
      |> IdleWorkers.remove(dead_process_pid)
      |> BusyWorkers.remove(dead_process_pid)
      |> IdleOverflowedWorkers.remove(dead_process_pid)

    cond do
      not WaitingCallers.empty?(state) ->
        handle_down_worker_with_waiting_callers(state)

      state.overflow > 0 ->
        %{state | overflow: state.overflow - 1}

      true ->
        handle_down_worker_without_overflow(state)
    end
  end

  defp handle_down_worker_with_waiting_callers(state) do
    case start_worker(state) do
      {:ok, new_worker, state} ->
        state
        |> BusyWorkers.add(new_worker)
        |> provide_worker_to_waiting_caller(new_worker)

      {:error, :failed_to_start_worker, state} ->
        state
    end
  end

  defp handle_down_worker_without_overflow(state) do
    case start_worker(state) do
      {:ok, new_worker, state} -> IdleWorkers.add(state, new_worker)
      {:error, :failed_to_start_worker, state} -> state
    end
  end

  @spec handle_down_waiting_caller(State.t(), pid()) :: State.t()
  defp handle_down_waiting_caller(%State{} = state, dead_process_pid) do
    WaitingCallers.remove_by_pid(state, dead_process_pid)
  end

  @impl GenServer
  def terminate(reason, %State{} = state) do
    DynamicSupervisor.stop(state.supervisor, reason)

    :ok
  end

  # Monitor the `caller`. Kill attached worker if caller dies unexpectedly.
  # This ensures the next caller gets a clean worker, not one potentially stuck in a long operation.
  # Used by both run/3 (via acquire/release) and manual acquire/release workflows.
  @spec start_manual_monitor(pool_id(), caller :: pid(), worker :: pid()) :: monitor_process :: pid()
  defp start_manual_monitor(pool_id, caller, worker) do
    spawn(fn ->
      reference = Process.monitor(caller)

      receive do
        {:DOWN, ^reference, :process, ^caller, reason} ->
          # Only kill worker if caller died abnormally (not :normal shutdown)
          # Normal shutdown means release/2 was called explicitly
          if reason != :normal do
            GenServer.cast(pool_id, {:stop_worker, worker})
            GenServer.cast(pool_id, {:cleanup_manual_monitor, worker})
          end
      end
    end)
  end

  @spec schedule_retry_failed_workers(State.t()) :: :ok
  defp schedule_retry_failed_workers(state) do
    Process.send_after(self(), :retry_failed_workers, state.failed_workers_retry_interval)

    :ok
  end

  @spec retry_failed_workers(State.t()) :: State.t()
  defp retry_failed_workers(%State{} = state) do
    workers_to_retry = state.failed_to_start_workers_count

    Logger.info("[Poolex] Attempting to restart #{workers_to_retry} failed workers")

    # Reset the failed workers counter
    state = %{state | failed_to_start_workers_count: 0}

    # Start the specified number of workers
    {workers, updated_state} = start_workers(workers_to_retry, state)

    # Add successfully started workers to the pool
    Enum.reduce(workers, updated_state, fn worker, acc_state ->
      if WaitingCallers.empty?(acc_state) do
        # If there are no waiting callers, add to idle workers list
        IdleWorkers.add(acc_state, worker)
      else
        # If there are waiting callers, give them the worker
        acc_state
        |> BusyWorkers.add(worker)
        |> provide_worker_to_waiting_caller(worker)
      end
    end)
  end
end
