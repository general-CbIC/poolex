defmodule Poolex do
  @external_resource "README.md"
  @moduledoc "README.md" |> File.read!() |> String.split("<!-- @moduledoc -->") |> Enum.at(1)

  use GenServer

  alias Poolex.State
  alias Poolex.Monitoring

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
      iex> %Poolex.State{idle_workers_count: idle_workers_count} = Poolex.get_state(:my_pool)
      iex> idle_workers_count
      5
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

      iex> Poolex.start_link(:my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> %Poolex.State{idle_workers_count: idle_workers_count} = Poolex.get_state(:my_pool)
      iex> idle_workers_count
      5
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

  Primarily needed to help with debugging.

  ## Examples

      iex> Poolex.start(:my_pool, worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 5)
      iex> state = %Poolex.State{} = Poolex.get_state(:my_pool)
      iex> state.busy_workers_count
      0
      iex> state.idle_workers_count
      5
      iex> state.worker_module
      Agent
  """
  @spec get_state(pool_id()) :: State.t()
  def get_state(pool_id) do
    GenServer.call(pool_id, :get_state)
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
      idle_workers_count: workers_count,
      idle_workers_pids: worker_pids,
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
  def handle_call(
        :get_idle_worker,
        {from_pid, _} = caller,
        %State{idle_workers_count: 0, waiting_callers: waiting_callers, monitor_id: monitor_id} =
          state
      ) do
    Monitoring.add(monitor_id, from_pid, :caller)

    {:noreply, %{state | waiting_callers: :queue.in(caller, waiting_callers)}}
  end

  def handle_call(
        :get_idle_worker,
        _from,
        %State{
          idle_workers_count: idle_workers_count,
          idle_workers_pids: idle_workers_pids,
          busy_workers_count: busy_workers_count,
          busy_workers_pids: busy_workers_pids
        } = state
      ) do
    [idle_worker_pid | rest_idle_workers_pids] = idle_workers_pids

    state = %State{
      state
      | idle_workers_count: idle_workers_count - 1,
        idle_workers_pids: rest_idle_workers_pids,
        busy_workers_count: busy_workers_count + 1,
        busy_workers_pids: [idle_worker_pid | busy_workers_pids]
    }

    {:reply, {:ok, idle_worker_pid}, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast(
        {:release_busy_worker, worker_pid},
        %State{
          busy_workers_pids: busy_workers_pids,
          busy_workers_count: busy_workers_count,
          idle_workers_pids: idle_workers_pids,
          idle_workers_count: idle_workers_count,
          waiting_callers: {[], []}
        } = state
      ) do
    if Enum.member?(busy_workers_pids, worker_pid) do
      {:noreply,
       %State{
         state
         | busy_workers_count: busy_workers_count - 1,
           busy_workers_pids: List.delete(busy_workers_pids, worker_pid),
           idle_workers_count: idle_workers_count + 1,
           idle_workers_pids: [worker_pid | idle_workers_pids]
       }}
    else
      {:noreply, state}
    end
  end

  def handle_cast(
        {:release_busy_worker, worker_pid},
        %State{waiting_callers: waiting_callers} = state
      ) do
    {{:value, caller}, left_waiting_callers} = :queue.out(waiting_callers)

    GenServer.reply(caller, {:ok, worker_pid})

    {:noreply, %{state | waiting_callers: left_waiting_callers}}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, monitoring_reference, _process, dead_process_pid, _reason},
        %State{
          monitor_id: monitor_id,
          idle_workers_pids: idle_workers_pids,
          busy_workers_pids: busy_workers_pids,
          worker_module: worker_module,
          worker_start_fun: worker_start_fun,
          worker_args: worker_args,
          waiting_callers: waiting_callers,
          supervisor: supervisor
        } = state
      ) do
    case Monitoring.remove(monitor_id, monitoring_reference) do
      :worker ->
        {:ok, new_worker} = start_worker(worker_module, worker_start_fun, worker_args, supervisor)
        Monitoring.add(monitor_id, new_worker, :worker)

        idle_workers_pids = [new_worker | List.delete(idle_workers_pids, dead_process_pid)]
        busy_workers_pids = List.delete(busy_workers_pids, dead_process_pid)

        state = %State{
          state
          | idle_workers_pids: idle_workers_pids,
            idle_workers_count: Enum.count(idle_workers_pids),
            busy_workers_pids: busy_workers_pids,
            busy_workers_count: Enum.count(busy_workers_pids)
        }

        {:noreply, state}

      :caller ->
        left_waiting_queue =
          :queue.filter(fn {caller_pid, _} -> caller_pid != dead_process_pid end, waiting_callers)

        {:noreply, %{state | waiting_callers: left_waiting_queue}}
    end
  end
end
