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
  alias Poolex.Private.IdleWorkers
  alias Poolex.Private.Metrics
  alias Poolex.Private.Monitoring
  alias Poolex.Private.State
  alias Poolex.Private.WaitingCallers

  require Logger

  @default_checkout_timeout :timer.seconds(5)

  # Interval between retry attempts for workers that failed to start (1 second by default)
  @default_failed_workers_retry_interval :timer.seconds(1)

  @poolex_options_table """
  | Option                 | Description                                          | Example               | Default value                     |
  |------------------------|------------------------------------------------------|-----------------------|-----------------------------------|
  | `pool_id`              | Identifier by which you will access the pool         | `:my_pool`            | `worker_module` value             |
  | `worker_module`        | Name of module that implements our worker            | `MyApp.Worker`        | **option is required**            |
  | `workers_count`        | How many workers should be running in the pool       | `5`                   | **option is required**            |
  | `max_overflow`         | How many workers can be created over the limit       | `2`                   | `0`                               |
  | `worker_args`          | List of arguments passed to the start function       | `[:gg, "wp"]`         | `[]`                              |
  | `worker_start_fun`     | Name of the function that starts the worker          | `:run`                | `:start_link`                     |
  | `busy_workers_impl`    | Module that describes how to work with busy workers  | `SomeBusyWorkersImpl` | `Poolex.Workers.Impl.List`        |
  | `idle_workers_impl`    | Module that describes how to work with idle workers  | `SomeIdleWorkersImpl` | `Poolex.Workers.Impl.List`        |
  | `waiting_callers_impl` | Module that describes how to work with callers queue | `WaitingCallersImpl`  | `Poolex.Callers.Impl.ErlangQueue` |
  | `pool_size_metrics`    | Whether to dispatch pool size metrics                | `true`                | `false`                           |
  | `failed_workers_retry_interval` | Interval in milliseconds between retry attempts for failed workers | `5_000`               | `1_000`                           |
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
          {:pool_id, pool_id()}
          | {:worker_module, module()}
          | {:workers_count, non_neg_integer()}
          | {:max_overflow, non_neg_integer()}
          | {:worker_args, list(any())}
          | {:worker_start_fun, atom()}
          | {:busy_workers_impl, module()}
          | {:idle_workers_impl, module()}
          | {:waiting_callers_impl, module()}
          | {:pool_size_metrics, boolean()}
          | {:failed_workers_retry_interval, timeout()}

  @typedoc """
  Process id of `worker`.

  **Workers** are processes launched in a pool.
  """
  @type worker() :: pid()

  @typedoc """
  | Option  | Description                                        | Example  | Default value                           |
  |---------|----------------------------------------------------|----------|-----------------------------------------|
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
    GenServer.start(__MODULE__, opts, name: get_pool_id(opts), spawn_opt: @spawn_opts)
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
    GenServer.start_link(__MODULE__, opts, name: get_pool_id(opts), spawn_opt: @spawn_opts)
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
    %{id: get_pool_id(opts), start: {Poolex, :start_link, [opts]}}
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
    checkout_timeout = Keyword.get(options, :checkout_timeout, @default_checkout_timeout)

    case get_idle_worker(pool_id, checkout_timeout) do
      {:ok, worker_pid} ->
        monitor_process = monitor_caller(pool_id, self(), worker_pid)

        try do
          {:ok, fun.(worker_pid)}
        after
          Process.exit(monitor_process, :kill)
          GenServer.cast(pool_id, {:release_busy_worker, worker_pid})
        end

      {:error, :checkout_timeout} ->
        {:error, :checkout_timeout}
    end
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

  @deprecated "Use :sys.get_state/1 instead"
  @doc false
  def get_state(name) do
    :sys.get_state(name)
  end

  @doc """
  Returns detailed information about started pool.

  Primarily needed to help with debugging. **Avoid using this function in production.**

  ## Fields

      * `busy_workers_count` - how many workers are busy right now.
      * `busy_workers_pids` - list of busy workers.
      * `failed_to_start_workers_count` - how many workers failed to start.
      * `idle_workers_count` - how many workers are ready to work.
      * `idle_workers_pids` - list of idle workers.
      * `max_overflow` - how many workers can be created over the limit.
      * `overflow` - current count of workers launched over limit.
      * `waiting_caller_pids` - list of callers processes.
      * `worker_args` - what parameters are used to start the worker.
      * `worker_module` - name of a module that describes a worker.
      * `worker_start_fun` - what function is used to start the worker.

  ## Examples

      iex> Poolex.start(pool_id: :my_pool_3, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> debug_info = %Poolex.Private.DebugInfo{} = Poolex.get_debug_info(:my_pool_3)
      iex> debug_info.busy_workers_count
      0
      iex> debug_info.idle_workers_count
      5
  """
  @spec get_debug_info(pool_id()) :: DebugInfo.t()
  def get_debug_info(pool_id) do
    GenServer.call(pool_id, :get_debug_info)
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

    pool_id = get_pool_id(opts)
    worker_module = Keyword.fetch!(opts, :worker_module)
    workers_count = Keyword.fetch!(opts, :workers_count)

    max_overflow = Keyword.get(opts, :max_overflow, 0)
    worker_args = Keyword.get(opts, :worker_args, [])
    worker_start_fun = Keyword.get(opts, :worker_start_fun, :start_link)

    busy_workers_impl = Keyword.get(opts, :busy_workers_impl, Poolex.Workers.Impl.List)
    idle_workers_impl = Keyword.get(opts, :idle_workers_impl, Poolex.Workers.Impl.List)

    waiting_callers_impl =
      Keyword.get(opts, :waiting_callers_impl, Poolex.Callers.Impl.ErlangQueue)

    failed_workers_retry_interval =
      Keyword.get(opts, :failed_workers_retry_interval, @default_failed_workers_retry_interval)

    {:ok, supervisor} = Poolex.Private.Supervisor.start_link()

    state =
      %State{
        failed_workers_retry_interval: failed_workers_retry_interval,
        max_overflow: max_overflow,
        pool_id: pool_id,
        supervisor: supervisor,
        worker_args: worker_args,
        worker_module: worker_module,
        worker_start_fun: worker_start_fun
      }

    {initial_workers_pids, state} = start_workers(workers_count, state)

    state =
      state
      |> IdleWorkers.init(idle_workers_impl, initial_workers_pids)
      |> BusyWorkers.init(busy_workers_impl)
      |> WaitingCallers.init(waiting_callers_impl)

    {:ok, state, {:continue, opts}}
  end

  @doc """
  Returns pool identifier from initialization options.
  """
  @spec get_pool_id(list(poolex_option())) :: pool_id()
  def get_pool_id(options) do
    case Keyword.get(options, :pool_id) do
      nil -> Keyword.fetch!(options, :worker_module)
      pool_id -> pool_id
    end
  end

  @impl GenServer
  def handle_continue(opts, state) do
    Metrics.start_poller(opts)

    state = schedule_retry_failed_workers(state, state.failed_workers_retry_interval)

    {:noreply, state}
  end

  @spec start_workers(non_neg_integer(), State.t()) :: {[pid], State.t()}
  defp start_workers(0, state) do
    {[], state}
  end

  defp start_workers(workers_count, state) when is_integer(workers_count) and workers_count >= 1 do
    Enum.reduce(1..workers_count, {[], state}, fn _iterator, {workers_pids, state} ->
      case start_worker(state) do
        {:ok, worker_pid} ->
          state = Monitoring.add(state, worker_pid, :worker)
          {[worker_pid | workers_pids], state}

        {:error, :failed_to_start_worker} ->
          state = %{state | failed_to_start_workers_count: state.failed_to_start_workers_count + 1}
          {workers_pids, state}
      end
    end)
  end

  defp start_workers(workers_count, _state) do
    msg = "workers_count must be non negative integer, received: #{inspect(workers_count)}"
    raise ArgumentError, msg
  end

  @spec start_worker(State.t()) :: {:ok, pid()} | {:error, :failed_to_start_worker}
  defp start_worker(%State{} = state) do
    case DynamicSupervisor.start_child(state.supervisor, %{
           id: make_ref(),
           start: {state.worker_module, state.worker_start_fun, state.worker_args},
           restart: :temporary
         }) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error("[Poolex] Failed to start worker. Reason: #{inspect(reason)}")
        {:error, :failed_to_start_worker}
    end
  end

  @spec stop_worker(Supervisor.supervisor(), pid()) :: :ok | {:error, :not_found}
  defp stop_worker(supervisor, worker_pid) do
    DynamicSupervisor.terminate_child(supervisor, worker_pid)
  end

  @impl GenServer
  def handle_call({:get_idle_worker, caller_reference}, {from_pid, _} = caller, %State{} = state) do
    if IdleWorkers.empty?(state) do
      if state.overflow < state.max_overflow do
        {:ok, new_worker} = start_worker(state)

        state =
          state
          |> Monitoring.add(new_worker, :worker)
          |> BusyWorkers.add(new_worker)

        {:reply, {:ok, new_worker}, %State{state | overflow: state.overflow + 1}}
      else
        state =
          state
          |> Monitoring.add(from_pid, :waiting_caller)
          |> WaitingCallers.add(%Poolex.Caller{reference: caller_reference, from: caller})

        {:noreply, state}
      end
    else
      {idle_worker_pid, state} = IdleWorkers.pop(state)
      state = BusyWorkers.add(state, idle_worker_pid)

      {:reply, {:ok, idle_worker_pid}, state}
    end
  end

  def handle_call(:get_debug_info, _from, %State{} = state) do
    debug_info = %DebugInfo{
      busy_workers_count: BusyWorkers.count(state),
      busy_workers_impl: state.busy_workers_impl,
      busy_workers_pids: BusyWorkers.to_list(state),
      failed_to_start_workers_count: state.failed_to_start_workers_count,
      idle_workers_count: IdleWorkers.count(state),
      idle_workers_impl: state.idle_workers_impl,
      idle_workers_pids: IdleWorkers.to_list(state),
      max_overflow: state.max_overflow,
      overflow: state.overflow,
      waiting_callers: WaitingCallers.to_list(state),
      waiting_callers_impl: state.waiting_callers_impl,
      worker_args: state.worker_args,
      worker_module: state.worker_module,
      worker_start_fun: state.worker_start_fun
    }

    {:reply, debug_info, state}
  end

  @impl GenServer
  def handle_call({:add_idle_workers, workers_count}, _from, %State{} = state) do
    {workers, state} = start_workers(workers_count, state)

    state =
      Enum.reduce(workers, state, fn worker, acc_state ->
        if WaitingCallers.empty?(acc_state) do
          IdleWorkers.add(acc_state, worker)
        else
          acc_state
          |> Monitoring.add(worker, :worker)
          |> BusyWorkers.add(worker)
          |> provide_worker_to_waiting_caller(worker)
        end
      end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:remove_idle_workers, workers_count}, _from, %State{} = state) do
    new_state =
      state
      |> IdleWorkers.to_list()
      |> Enum.take(workers_count)
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
  def handle_cast({:stop_worker, worker_pid}, %State{} = state) do
    stop_worker(state.supervisor, worker_pid)
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
  def handle_info(:retry_failed_workers, %{failed_workers_retry_interval: retry_interval} = state) do
    # Try to start workers that failed to initialize
    state =
      if state.failed_to_start_workers_count > 0 do
        retry_failed_workers(state)
      else
        state
      end

    # Schedule next check
    state = schedule_retry_failed_workers(state, retry_interval)

    {:noreply, state}
  end

  @spec release_busy_worker(State.t(), worker()) :: State.t()
  defp release_busy_worker(%State{} = state, worker) do
    if BusyWorkers.member?(state, worker) do
      state = BusyWorkers.remove(state, worker)

      if state.overflow > 0 do
        stop_worker(state.supervisor, worker)

        state
      else
        IdleWorkers.add(state, worker)
      end
    else
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

    if WaitingCallers.empty?(state) do
      if state.overflow > 0 do
        %State{state | overflow: state.overflow - 1}
      else
        {:ok, new_worker} = start_worker(state)

        state
        |> Monitoring.add(new_worker, :worker)
        |> IdleWorkers.add(new_worker)
      end
    else
      {:ok, new_worker} = start_worker(state)

      state
      |> Monitoring.add(new_worker, :worker)
      |> BusyWorkers.add(new_worker)
      |> provide_worker_to_waiting_caller(new_worker)
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

  # Monitor the `caller`. Release attached worker in case of caller's death.
  @spec monitor_caller(pool_id(), caller :: pid(), worker :: pid()) :: monitor_process :: pid()
  defp monitor_caller(pool_id, caller, worker) do
    spawn(fn ->
      reference = Process.monitor(caller)

      receive do
        {:DOWN, ^reference, :process, ^caller, _reason} ->
          # Send message to stop worker if caller is dead
          # After that worker will be restarted
          GenServer.cast(pool_id, {:stop_worker, worker})
      end
    end)
  end

  @spec schedule_retry_failed_workers(State.t(), timeout()) :: State.t()
  defp schedule_retry_failed_workers(state, retry_interval) do
    Process.send_after(self(), :retry_failed_workers, retry_interval)
    %{state | failed_workers_retry_interval: retry_interval}
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
        |> Monitoring.add(worker, :worker)
        |> BusyWorkers.add(worker)
        |> provide_worker_to_waiting_caller(worker)
      end
    end)
  end
end
