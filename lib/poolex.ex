defmodule Poolex do
  @moduledoc """
  Poolex is a simple process pool manager.
  """
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

  @spec start_link(pool_id(), list(poolex_option())) :: GenServer.on_start()
  def start_link(pool_id, opts) do
    GenServer.start_link(__MODULE__, {pool_id, opts}, name: pool_id)
  end

  @type run_option() :: {:timeout, timeout()}
  @spec run(pool_id(), (worker :: pid() -> any()), list(poolex_option())) :: any()
  def run(pool_id, fun, options) do
    timeout = Keyword.get(options, :timeout, @default_wait_timeout)

    case GenServer.call(pool_id, :get_idle_worker, timeout) do
      {:ok, pid} ->
        result = fun.(pid)
        GenServer.cast(pool_id, {:release_busy_worker, pid})
        result

      error ->
        error
    end
  end

  @spec get_state(pool_id()) :: State.t()
  def get_state(pool_id) do
    GenServer.call(pool_id, :get_state)
  end

  def init({pool_id, opts}) do
    worker_module = Keyword.fetch!(opts, :worker_module)
    workers_count = Keyword.fetch!(opts, :workers_count)

    worker_start_fun = Keyword.get(opts, :worker_start_fun, :start)
    worker_args = Keyword.get(opts, :worker_args, [])

    {:ok, monitor_id} = Monitoring.init(pool_id)

    worker_pids =
      Enum.map(1..workers_count, fn _ ->
        {:ok, worker_pid} = start_worker(worker_module, worker_start_fun, worker_args)
        Monitoring.add(monitor_id, worker_pid)

        worker_pid
      end)

    state = %State{
      worker_module: worker_module,
      worker_start_fun: worker_start_fun,
      worker_args: worker_args,
      idle_workers_count: workers_count,
      idle_workers_pids: worker_pids,
      monitor_id: monitor_id
    }

    {:ok, state}
  end

  @spec start_worker(module(), atom(), list(any())) :: {:ok, pid()}
  defp start_worker(worker_module, worker_start_fun, worker_args) do
    apply(worker_module, worker_start_fun, worker_args)
  end

  def handle_call(:get_idle_worker, _from, %State{idle_workers_count: 0} = state) do
    {:reply, {:error, :all_workers_are_busy}, state}
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

  def handle_cast(
        {:release_busy_worker, worker_pid},
        %State{
          busy_workers_pids: busy_workers_pids,
          busy_workers_count: busy_workers_count,
          idle_workers_pids: idle_workers_pids,
          idle_workers_count: idle_workers_count
        } = state
      ) do
    state = %State{
      state
      | busy_workers_count: busy_workers_count - 1,
        busy_workers_pids: List.delete(busy_workers_pids, worker_pid),
        idle_workers_count: idle_workers_count + 1,
        idle_workers_pids: [worker_pid | idle_workers_pids]
    }

    {:noreply, state}
  end

  def handle_info(
        {:DOWN, monitoring_reference, _process, dead_worker_pid, _reason},
        %State{
          monitor_id: monitor_id,
          idle_workers_pids: idle_workers_pids,
          busy_workers_pids: busy_workers_pids,
          worker_module: worker_module,
          worker_start_fun: worker_start_fun,
          worker_args: worker_args
        } = state
      ) do
    Monitoring.remove(monitor_id, monitoring_reference)

    {:ok, new_worker} = start_worker(worker_module, worker_start_fun, worker_args)
    Monitoring.add(monitor_id, new_worker)

    idle_workers_pids = [new_worker | List.delete(idle_workers_pids, dead_worker_pid)]
    busy_workers_pids = List.delete(busy_workers_pids, dead_worker_pid)

    state = %State{
      state
      | idle_workers_pids: idle_workers_pids,
        idle_workers_count: Enum.count(idle_workers_pids),
        busy_workers_pids: busy_workers_pids,
        busy_workers_count: Enum.count(busy_workers_pids)
    }

    {:noreply, state}
  end
end
