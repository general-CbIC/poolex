defmodule Poolex.IdleWorkers do
  @moduledoc false
  alias Poolex.Settings
  alias Poolex.Workers.Behaviour

  @doc false
  @spec init(Poolex.pool_id(), module()) :: Behaviour.state()
  def init(pool_id, impl) do
    :ok = Settings.set_implementation(pool_id, :idle_workers, impl)
    impl(pool_id).init()
  end

  @doc false
  @spec init(Poolex.pool_id(), module(), list(Poolex.worker())) :: Behaviour.state()
  def init(pool_id, impl, workers) do
    :ok = Settings.set_implementation(pool_id, :idle_workers, impl)
    impl(pool_id).init(workers)
  end

  @doc false
  @spec add(Poolex.pool_id(), Behaviour.state(), Poolex.worker()) :: Behaviour.state()
  def add(pool_id, state, worker), do: impl(pool_id).add(state, worker)

  @doc false
  @spec remove(Poolex.pool_id(), Behaviour.state(), Poolex.worker()) :: Behaviour.state()
  def remove(pool_id, state, worker), do: impl(pool_id).remove(state, worker)

  @doc false
  @spec count(Poolex.pool_id(), Behaviour.state()) :: non_neg_integer()
  def count(pool_id, state), do: impl(pool_id).count(state)

  @doc false
  @spec to_list(Poolex.pool_id(), Behaviour.state()) :: list(Poolex.worker())
  def to_list(pool_id, state), do: impl(pool_id).to_list(state)

  @doc false
  @spec empty?(Poolex.pool_id(), Behaviour.state()) :: boolean()
  def empty?(pool_id, state), do: impl(pool_id).empty?(state)

  @doc false
  @spec pop(Poolex.pool_id(), Behaviour.state()) ::
          {Poolex.worker(), Behaviour.state()} | :empty
  def pop(pool_id, state), do: impl(pool_id).pop(state)

  @doc false
  @spec impl(Poolex.pool_id()) :: module()
  def impl(pool_id), do: Settings.get_implementation(pool_id, :idle_workers)
end
