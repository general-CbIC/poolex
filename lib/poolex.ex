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

  @spec run(pool_id(), (worker :: pid() -> any())) :: :ok
  def run(_pool_id, _fun) do
    :ok
  end

  @spec get_state(pool_id()) :: State.t()
  def get_state(pool_id) do
    :sys.get_state(pool_id)
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
end
