defmodule Poolex do
  use GenServer

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

  @spec get_state(pool_id()) :: Poolex.State.t()
  def get_state(_pool_id) do
    %Poolex.State{}
  end

  @impl true
  def init(_opts) do
    {:ok, nil}
  end
end
