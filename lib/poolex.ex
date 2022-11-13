defmodule Poolex do
  use GenServer

  alias Poolex.State

  @type pool_id() :: atom()
  @type poolex_option() ::
          {:worker_module, module()}
          | {:worker_args, list(any())}
          | {:workers_count, pos_integer()}

  @spec start_link(pool_id(), list(poolex_option())) :: GenServer.on_start()
  def start_link(pool_id, opts) do
    GenServer.start_link(__MODULE__, opts, name: pool_id)
  end

  @spec run(pool_id(), (worker :: pid() -> any())) :: :ok | {:error, :all_workers_are_busy}
  def run(pool_id, fun) do
    case GenServer.call(pool_id, :get_idle_worker) do
      {:ok, pid} -> fun.(pid)
      error -> error
    end
  end

  @spec get_state(pool_id()) :: State.t()
  def get_state(pool_id) do
    GenServer.call(pool_id, :get_state)
  end

  def init(opts) do
    worker_module = Keyword.fetch!(opts, :worker_module)
    workers_count = Keyword.fetch!(opts, :workers_count)

    worker_args = Keyword.get(opts, :worker_args, [])

    worker_pids = start_workers(workers_count, worker_module, worker_args)

    state = %State{
      worker_module: worker_module,
      worker_args: worker_args,
      idle_workers_count: workers_count,
      idle_workers_pids: worker_pids
    }

    {:ok, state}
  end

  @spec start_workers(non_neg_integer(), module(), list(any()), list(pid)) :: list(pid())
  defp start_workers(workers_count, worker_module, worker_args, worker_pids \\ [])

  defp start_workers(0, _worker_module, _worker_args, worker_pids) do
    worker_pids
  end

  defp start_workers(workers_count, worker_module, worker_args, workers_pids) do
    {:ok, pid} = apply(worker_module, :start_link, worker_args)
    start_workers(workers_count - 1, worker_module, worker_args, [pid | workers_pids])
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
end
