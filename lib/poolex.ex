defmodule Poolex do
  @external_resource "docs/guides/getting-started.md"
  @moduledoc "docs/guides/getting-started.md" |> File.read!()

  use GenServer

  alias Poolex.BusyWorkers
  alias Poolex.DebugInfo
  alias Poolex.IdleWorkers
  alias Poolex.Monitoring
  alias Poolex.State
  alias Poolex.WaitingCallers

  @default_wait_timeout :timer.seconds(5)

  @type pool_id() :: atom()
  @type poolex_option() ::
          {:worker_module, module()}
          | {:worker_start_fun, atom()}
          | {:worker_args, list(any())}
          | {:workers_count, pos_integer()}

  @doc """
  Starts a Poolex process without links (outside of a supervision tree).

  See start_link/2 for more information.

  ## Examples

      iex> Poolex.start(:my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> %Poolex.State{worker_module: worker_module} = Poolex.get_state(:my_pool)
      iex> worker_module
      Agent
  """
  @spec start(pool_id(), list(poolex_option())) :: GenServer.on_start()
  def start(pool_id, opts) do
    GenServer.start(__MODULE__, {pool_id, opts}, name: pool_id)
  end

  @doc """
  Starts a Poolex process linked to the current process.

  This is often used to start the Poolex as part of a supervision tree.

  After the process is started, you can access it using the previously specified `pool_id`.

  ## Options

  | Option             | Description                                    | Example        | Default value          |
  |--------------------|------------------------------------------------|----------------|------------------------|
  | `worker_module`    | Name of module that implements our worker      | `MyApp.Worker` | **option is required** |
  | `worker_start_fun` | Name of the function that starts the worker    | `:run`         | `:start`               |
  | `worker_args`      | List of arguments passed to the start function | `[:gg, "wp"]`  | `[]`                   |
  | `workers_count`    | How many workers should be running in the pool | `5`            | **option is required** |

  ## Examples

      iex> Poolex.start_link(:other_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> %Poolex.State{worker_module: worker_module} = Poolex.get_state(:other_pool)
      iex> worker_module
      Agent
  """
  @spec start_link(pool_id(), list(poolex_option())) :: GenServer.on_start()
  def start_link(pool_id, opts) do
    GenServer.start_link(__MODULE__, {pool_id, opts}, name: pool_id)
  end

  @doc """
  Same as `run!/3` but handles runtime_errors.

  Returns:
    * `{:runtime_error, reason}` on errors.
    * `:all_workers_are_busy` if no free worker was found before the timeout.

  See `run!/3` for more information.

  ## Examples

      iex> Poolex.start_link(:some_pool, worker_module: Agent, worker_args: [fn -> 5 end], workers_count: 1)
      iex> Poolex.run(:some_pool, fn _pid -> raise RuntimeError end)
      {:runtime_error, %RuntimeError{message: "runtime error"}}
      iex> Poolex.run(:some_pool, fn pid -> Agent.get(pid, &(&1)) end)
      {:ok, 5}
  """
  @type run_option() :: {:timeout, timeout()}
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

      iex> Poolex.start_link(:some_pool, worker_module: Agent, worker_args: [fn -> 5 end], workers_count: 1)
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

      iex> Poolex.start(:my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
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
      * `worker_module` - name of a module that describes a worker.
      * `worker_args` - what parameters are used to start the worker.
      * `worker_start_fun` - what function is used to start the worker.
      * `waiting_caller_pids` - list of callers processes.

  ## Examples

      iex> Poolex.start(:my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> debug_info = %Poolex.DebugInfo{} = Poolex.get_debug_info(:my_pool)
      iex> debug_info.busy_workers_count
      0
      iex> debug_info.idle_workers_count
      5
  """
  def get_debug_info(pool_id) do
    GenServer.call(pool_id, :get_debug_info)
  end

  @impl GenServer
  def init({pool_id, opts}) do
    worker_module = Keyword.fetch!(opts, :worker_module)
    workers_count = Keyword.fetch!(opts, :workers_count)

    worker_start_fun = Keyword.get(opts, :worker_start_fun, :start)
    worker_args = Keyword.get(opts, :worker_args, [])

    {:ok, monitor_id} = Monitoring.init(pool_id)
    {:ok, supervisor} = Poolex.Supervisor.start_link()

    worker_pids =
      Enum.map(1..workers_count, fn _ ->
        {:ok, worker_pid} = start_worker(worker_module, worker_start_fun, worker_args, supervisor)
        Monitoring.add(monitor_id, worker_pid, :worker)

        worker_pid
      end)

    state = %State{
      worker_module: worker_module,
      worker_start_fun: worker_start_fun,
      worker_args: worker_args,
      busy_workers_state: BusyWorkers.init(),
      idle_workers_state: IdleWorkers.init(worker_pids),
      waiting_callers_state: WaitingCallers.init(),
      monitor_id: monitor_id,
      supervisor: supervisor
    }

    {:ok, state}
  end

  @spec start_worker(module(), atom(), list(any()), pid()) :: {:ok, pid()}
  defp start_worker(worker_module, worker_start_fun, worker_args, supervisor) do
    DynamicSupervisor.start_child(supervisor, %{
      id: make_ref(),
      start: {worker_module, worker_start_fun, worker_args}
    })
  end

  @impl GenServer
  def handle_call(:get_idle_worker, {from_pid, _} = caller, %State{} = state) do
    if IdleWorkers.empty?(state.idle_workers_state) do
      Monitoring.add(state.monitor_id, from_pid, :caller)
      new_callers_state = WaitingCallers.add(state.waiting_callers_state, caller)

      {:noreply, %{state | waiting_callers_state: new_callers_state}}
    else
      {idle_worker_pid, new_idle_workers_state} = IdleWorkers.pop(state.idle_workers_state)
      new_busy_workers_state = BusyWorkers.add(state.busy_workers_state, idle_worker_pid)

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
      busy_workers_count: BusyWorkers.count(state.busy_workers_state),
      busy_workers_pids: BusyWorkers.to_list(state.busy_workers_state),
      idle_workers_count: IdleWorkers.count(state.idle_workers_state),
      idle_workers_pids: IdleWorkers.to_list(state.idle_workers_state),
      worker_module: state.worker_module,
      worker_args: state.worker_args,
      worker_start_fun: state.worker_start_fun,
      waiting_callers: WaitingCallers.to_list(state.waiting_callers_state)
    }

    {:reply, debug_info, state}
  end

  @impl GenServer
  def handle_cast({:release_busy_worker, worker_pid}, state) do
    if WaitingCallers.empty?(state.waiting_callers_state) do
      if BusyWorkers.member?(state.busy_workers_state, worker_pid) do
        {:noreply,
         %State{
           state
           | busy_workers_state: BusyWorkers.remove(state.busy_workers_state, worker_pid),
             idle_workers_state: IdleWorkers.add(state.idle_workers_state, worker_pid)
         }}
      else
        {:noreply, state}
      end
    else
      {caller, new_waiting_callers_state} = WaitingCallers.pop(state.waiting_callers_state)

      GenServer.reply(caller, {:ok, worker_pid})

      {:noreply, %{state | waiting_callers_state: new_waiting_callers_state}}
    end
  end

  @impl GenServer

  def handle_info({:DOWN, monitoring_reference, _process, dead_process_pid, _reason}, state) do
    case Monitoring.remove(state.monitor_id, monitoring_reference) do
      :worker ->
        {:ok, new_worker} =
          start_worker(
            state.worker_module,
            state.worker_start_fun,
            state.worker_args,
            state.supervisor
          )

        Monitoring.add(state.monitor_id, new_worker, :worker)

        new_idle_workers_state =
          state.idle_workers_state
          |> IdleWorkers.remove(dead_process_pid)
          |> IdleWorkers.add(new_worker)

        state = %State{
          state
          | idle_workers_state: new_idle_workers_state,
            busy_workers_state: BusyWorkers.remove(state.busy_workers_state, dead_process_pid)
        }

        {:noreply, state}

      :caller ->
        new_waiting_callers_state =
          WaitingCallers.remove_by_pid(state.waiting_callers_state, dead_process_pid)

        {:noreply, %{state | waiting_callers_state: new_waiting_callers_state}}
    end
  end
end
