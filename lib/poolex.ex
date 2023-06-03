defmodule Poolex do
  @moduledoc """
  ## Usage

  In the most typical use of Poolex, you only need to start pool of workers as a child of your application.

  ```elixir
  children = [
    Poolex.child_spec(
      pool_id: :worker_pool,
      worker_module: SomeWorker,
      workers_count: 5
    )
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
  ```

  Then you can execute any code on the workers with `run/3`:

  ```elixir
  Poolex.run(:worker_pool, &(is_pid?(&1)), timeout: 1_000)
  {:ok, true}
  ```

  Fore more information see [Getting Started](https://hexdocs.pm/poolex/getting-started.html)
  """

  use GenServer

  alias Poolex.BusyWorkers
  alias Poolex.DebugInfo
  alias Poolex.IdleWorkers
  alias Poolex.Monitoring
  alias Poolex.Settings
  alias Poolex.State
  alias Poolex.WaitingCallers

  @default_wait_timeout :timer.seconds(5)
  @poolex_options_table """
  | Option                 | Description                                          | Example               | Default value                     |
  |------------------------|------------------------------------------------------|-----------------------|-----------------------------------|
  | `pool_id`              | Identifier by which you will access the pool         | `:my_pool`            | **option is required**            |
  | `worker_module`        | Name of module that implements our worker            | `MyApp.Worker`        | **option is required**            |
  | `workers_count`        | How many workers should be running in the pool       | `5`                   | **option is required**            |
  | `max_overflow`         | How many workers can be created over the limit       | `2`                   | `0`                               |
  | `worker_args`          | List of arguments passed to the start function       | `[:gg, "wp"]`         | `[]`                              |
  | `worker_start_fun`     | Name of the function that starts the worker          | `:run`                | `:start_link`                     |
  | `busy_workers_impl`    | Module that describes how to work with busy workers  | `SomeBusyWorkersImpl` | `Poolex.Workers.Impl.List`        |
  | `idle_workers_impl`    | Module that describes how to work with idle workers  | `SomeIdleWorkersImpl` | `Poolex.Workers.Impl.List`        |
  | `waiting_callers_impl` | Module that describes how to work with callers queue | `WaitingCallersImpl`  | `Poolex.Callers.Impl.ErlangQueue` |
  """

  @typedoc """
  Any atom naming your pool, e.g. `:my_pool`.
  """
  @type pool_id() :: atom()
  @typedoc """
  #{@poolex_options_table}
  """
  @type poolex_option() ::
          {:pool_id, pool_id()}
          | {:worker_module, module()}
          | {:workers_count, pos_integer()}
          | {:max_overflow, non_neg_integer()}
          | {:worker_args, list(any())}
          | {:worker_start_fun, atom()}
          | {:busy_workers_impl, module()}
          | {:idle_workers_impl, module()}
          | {:waiting_callers_impl, module()}

  @typedoc """
  Process id of `worker`.

  **Workers** are processes launched in a pool.
  """
  @type worker() :: pid()

  @typedoc """
  Tuple describing the `caller`.

  **Callers** are processes that have requested to get a worker.
  """
  @type caller() :: GenServer.from()

  @typedoc """
  | Option  | Description                                        | Example  | Default value              |
  |---------|----------------------------------------------------|----------|----------------------------|
  | timeout | How long we can wait for a worker on the call site | `60_000` | `#{@default_wait_timeout}` |
  """
  @type run_option() :: {:timeout, timeout()}

  @doc """
  Starts a Poolex process without links (outside of a supervision tree).

  See start_link/1 for more information.

  ## Examples

      iex> Poolex.start(pool_id: :my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> %Poolex.State{worker_module: worker_module} = Poolex.get_state(:my_pool)
      iex> worker_module
      Agent
  """
  @spec start(list(poolex_option())) :: GenServer.on_start()
  def start(opts) do
    pool_id = Keyword.fetch!(opts, :pool_id)
    GenServer.start(__MODULE__, opts, name: pool_id)
  end

  @doc """
  Starts a Poolex process linked to the current process.

  This is often used to start the Poolex as part of a supervision tree.

  After the process is started, you can access it using the previously specified `pool_id`.

  ## Options

  #{@poolex_options_table}

  ## Examples

      iex> Poolex.start_link(pool_id: :other_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> %Poolex.State{worker_module: worker_module} = Poolex.get_state(:other_pool)
      iex> worker_module
      Agent
  """
  @spec start_link(list(poolex_option())) :: GenServer.on_start()
  def start_link(opts) do
    pool_id = Keyword.fetch!(opts, :pool_id)
    GenServer.start_link(__MODULE__, opts, name: pool_id)
  end

  @doc """
  Returns a specification to start this module under a supervisor.

  ## Options

  #{@poolex_options_table}

  ## Examples

      children = [
        Poolex.child_spec(pool_id: :worker_pool_1, worker_module: SomeWorker, workers_count: 5),
        # or in another way
        {Poolex, [pool_id: :worker_pool_2, worker_module: SomeOtherWorker, workers_count: 5]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """
  @spec child_spec(list(poolex_option())) :: Supervisor.child_spec()
  def child_spec(opts) do
    pool_id = Keyword.fetch!(opts, :pool_id)
    %{id: pool_id, start: {Poolex, :start_link, [opts]}}
  end

  @doc """
  Same as `run!/3` but handles runtime_errors.

  Returns:
    * `{:runtime_error, reason}` on errors.
    * `:all_workers_are_busy` if no free worker was found before the timeout.

  See `run!/3` for more information.

  ## Examples

      iex> Poolex.start_link(pool_id: :some_pool, worker_module: Agent, worker_args: [fn -> 5 end], workers_count: 1)
      iex> Poolex.run(:some_pool, fn _pid -> raise RuntimeError end)
      {:runtime_error, %RuntimeError{message: "runtime error"}}
      iex> Poolex.run(:some_pool, fn pid -> Agent.get(pid, &(&1)) end)
      {:ok, 5}
  """
  @spec run(pool_id(), (worker :: pid() -> any()), list(run_option())) ::
          {:ok, any()} | :all_workers_are_busy | {:runtime_error, any()}
  def run(pool_id, fun, options \\ []) do
    {:ok, run!(pool_id, fun, options)}
  rescue
    runtime_error -> {:runtime_error, runtime_error}
  catch
    :exit, {:timeout, _meta} -> :all_workers_are_busy
    :exit, reason -> {:runtime_error, reason}
  end

  @doc """
  The main function for working with the pool.

  When executed, an attempt is made to obtain a worker with the specified timeout (5 seconds by default).
  In case of successful execution of the passed function, the result will be returned, otherwise an error will be raised.

  ## Examples

      iex> Poolex.start_link(pool_id: :some_pool, worker_module: Agent, worker_args: [fn -> 5 end], workers_count: 1)
      iex> Poolex.run!(:some_pool, fn pid -> Agent.get(pid, &(&1)) end)
      5
  """
  @spec run!(pool_id(), (worker :: pid() -> any()), list(run_option())) :: any()
  def run!(pool_id, fun, options \\ []) do
    timeout = Keyword.get(options, :timeout, @default_wait_timeout)

    {:ok, pid} = GenServer.call(pool_id, :get_idle_worker, timeout)

    try do
      fun.(pid)
    after
      GenServer.cast(pool_id, {:release_busy_worker, pid})
    end
  end

  @doc """
  Returns current state of started pool.

  Primarily needed to help with debugging. **Avoid using this function in production.**

  ## Examples

      iex> Poolex.start(pool_id: :my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> state = %Poolex.State{} = Poolex.get_state(:my_pool)
      iex> state.worker_module
      Agent
      iex> is_pid(state.supervisor)
      true
  """
  @spec get_state(pool_id()) :: State.t()
  def get_state(pool_id) do
    GenServer.call(pool_id, :get_state)
  end

  @doc """
  Returns detailed information about started pool.

  Primarily needed to help with debugging. **Avoid using this function in production.**

  ## Fields

      * `busy_workers_count` - how many workers are busy right now.
      * `busy_workers_pids` - list of busy workers.
      * `idle_workers_count` - how many workers are ready to work.
      * `idle_workers_pids` - list of idle workers.
      * `max_overflow` - how many workers can be created over the limit.
      * `overflow` - current count of workers launched over limit.
      * `waiting_caller_pids` - list of callers processes.
      * `worker_args` - what parameters are used to start the worker.
      * `worker_module` - name of a module that describes a worker.
      * `worker_start_fun` - what function is used to start the worker.

  ## Examples

      iex> Poolex.start(pool_id: :my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> debug_info = %Poolex.DebugInfo{} = Poolex.get_debug_info(:my_pool)
      iex> debug_info.busy_workers_count
      0
      iex> debug_info.idle_workers_count
      5
  """
  @spec get_debug_info(pool_id()) :: DebugInfo.t()
  def get_debug_info(pool_id) do
    GenServer.call(pool_id, :get_debug_info)
  end

  @impl GenServer
  def init(opts) do
    pool_id = Keyword.fetch!(opts, :pool_id)
    worker_module = Keyword.fetch!(opts, :worker_module)
    workers_count = Keyword.fetch!(opts, :workers_count)

    max_overflow = Keyword.get(opts, :max_overflow, 0)
    worker_args = Keyword.get(opts, :worker_args, [])
    worker_start_fun = Keyword.get(opts, :worker_start_fun, :start_link)

    busy_workers_impl = Keyword.get(opts, :busy_workers_impl, Poolex.Workers.Impl.List)
    idle_workers_impl = Keyword.get(opts, :idle_workers_impl, Poolex.Workers.Impl.List)

    waiting_callers_impl =
      Keyword.get(opts, :waiting_callers_impl, Poolex.Callers.Impl.ErlangQueue)

    :ok = Settings.init()
    {:ok, monitor_id} = Monitoring.init(pool_id)
    {:ok, supervisor} = Poolex.Supervisor.start_link()

    state = %State{
      busy_workers_state: BusyWorkers.init(pool_id, busy_workers_impl),
      max_overflow: max_overflow,
      monitor_id: monitor_id,
      pool_id: pool_id,
      supervisor: supervisor,
      waiting_callers_state: WaitingCallers.init(pool_id, waiting_callers_impl),
      worker_args: worker_args,
      worker_module: worker_module,
      worker_start_fun: worker_start_fun
    }

    worker_pids =
      Enum.map(1..workers_count, fn _ ->
        {:ok, worker_pid} = start_worker(state)
        Monitoring.add(monitor_id, worker_pid, :worker)

        worker_pid
      end)

    {:ok,
     %State{state | idle_workers_state: IdleWorkers.init(pool_id, idle_workers_impl, worker_pids)}}
  end

  @spec start_worker(State.t()) :: {:ok, pid()}
  defp start_worker(%State{} = state) do
    DynamicSupervisor.start_child(state.supervisor, %{
      id: make_ref(),
      start: {state.worker_module, state.worker_start_fun, state.worker_args}
    })
  end

  @spec stop_worker(Supervisor.supervisor(), pid()) :: :ok | {:error, :not_found}
  defp stop_worker(supervisor, worker_pid) do
    DynamicSupervisor.terminate_child(supervisor, worker_pid)
  end

  @impl GenServer
  def handle_call(:get_idle_worker, {from_pid, _} = caller, %State{} = state) do
    if IdleWorkers.empty?(state.pool_id, state.idle_workers_state) do
      if state.overflow < state.max_overflow do
        {:ok, new_worker} = start_worker(state)

        Monitoring.add(state.monitor_id, new_worker, :temporary_worker)

        new_state = %State{
          state
          | busy_workers_state:
              BusyWorkers.add(state.pool_id, state.busy_workers_state, new_worker),
            overflow: state.overflow + 1
        }

        {:reply, {:ok, new_worker}, new_state}
      else
        Monitoring.add(state.monitor_id, from_pid, :caller)

        new_callers_state = WaitingCallers.add(state.pool_id, state.waiting_callers_state, caller)

        {:noreply, %{state | waiting_callers_state: new_callers_state}}
      end
    else
      {idle_worker_pid, new_idle_workers_state} =
        IdleWorkers.pop(state.pool_id, state.idle_workers_state)

      new_busy_workers_state =
        BusyWorkers.add(state.pool_id, state.busy_workers_state, idle_worker_pid)

      new_state = %State{
        state
        | idle_workers_state: new_idle_workers_state,
          busy_workers_state: new_busy_workers_state
      }

      {:reply, {:ok, idle_worker_pid}, new_state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_debug_info, _form, %Poolex.State{} = state) do
    debug_info = %DebugInfo{
      busy_workers_count: BusyWorkers.count(state.pool_id, state.busy_workers_state),
      busy_workers_impl: BusyWorkers.impl(state.pool_id),
      busy_workers_pids: BusyWorkers.to_list(state.pool_id, state.busy_workers_state),
      idle_workers_count: IdleWorkers.count(state.pool_id, state.idle_workers_state),
      idle_workers_impl: IdleWorkers.impl(state.pool_id),
      idle_workers_pids: IdleWorkers.to_list(state.pool_id, state.idle_workers_state),
      max_overflow: state.max_overflow,
      overflow: state.overflow,
      waiting_callers: WaitingCallers.to_list(state.pool_id, state.waiting_callers_state),
      waiting_callers_impl: WaitingCallers.impl(state.pool_id),
      worker_args: state.worker_args,
      worker_module: state.worker_module,
      worker_start_fun: state.worker_start_fun
    }

    {:reply, debug_info, state}
  end

  @impl GenServer
  def handle_cast({:release_busy_worker, worker}, %State{} = state) do
    if WaitingCallers.empty?(state.pool_id, state.waiting_callers_state) do
      new_state = release_busy_worker(state, worker)
      {:noreply, new_state}
    else
      new_state = provide_worker_to_waiting_caller(state, worker)
      {:noreply, new_state}
    end
  end

  @spec release_busy_worker(State.t(), worker()) :: State.t()
  defp release_busy_worker(%State{} = state, worker) do
    if BusyWorkers.member?(state.pool_id, state.busy_workers_state, worker) do
      busy_workers_state = BusyWorkers.remove(state.pool_id, state.busy_workers_state, worker)

      if state.overflow > 0 do
        stop_worker(state.supervisor, worker)

        %State{state | busy_workers_state: busy_workers_state}
      else
        %State{
          state
          | busy_workers_state: busy_workers_state,
            idle_workers_state: IdleWorkers.add(state.pool_id, state.idle_workers_state, worker)
        }
      end
    else
      state
    end
  end

  @spec provide_worker_to_waiting_caller(State.t(), worker()) :: State.t()
  defp provide_worker_to_waiting_caller(%State{} = state, worker) do
    {caller, new_waiting_callers_state} =
      WaitingCallers.pop(state.pool_id, state.waiting_callers_state)

    GenServer.reply(caller, {:ok, worker})

    %{state | waiting_callers_state: new_waiting_callers_state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, monitoring_reference, _process, dead_process_pid, _reason},
        %State{} = state
      ) do
    case Monitoring.remove(state.monitor_id, monitoring_reference) do
      :temporary_worker ->
        {:noreply,
         %State{
           state
           | overflow: state.overflow - 1,
             idle_workers_state:
               IdleWorkers.remove(
                 state.pool_id,
                 state.idle_workers_state,
                 dead_process_pid
               )
         }}

      :worker ->
        {:ok, new_worker} = start_worker(state)

        Monitoring.add(state.monitor_id, new_worker, :worker)

        temp_idle_workers_state =
          IdleWorkers.remove(state.pool_id, state.idle_workers_state, dead_process_pid)

        new_idle_workers_state =
          IdleWorkers.add(state.pool_id, temp_idle_workers_state, new_worker)

        state = %State{
          state
          | idle_workers_state: new_idle_workers_state,
            busy_workers_state:
              BusyWorkers.remove(state.pool_id, state.busy_workers_state, dead_process_pid)
        }

        {:noreply, state}

      :caller ->
        new_waiting_callers_state =
          WaitingCallers.remove_by_pid(
            state.pool_id,
            state.waiting_callers_state,
            dead_process_pid
          )

        {:noreply, %{state | waiting_callers_state: new_waiting_callers_state}}
    end
  end

  @impl GenServer
  def terminate(reason, %State{} = state) do
    DynamicSupervisor.stop(state.supervisor, reason)

    :ok
  end
end
