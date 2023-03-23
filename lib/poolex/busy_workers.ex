defmodule Poolex.BusyWorkers do
  @moduledoc false
  alias Poolex.Workers.Behaviour
  alias Poolex.Settings

  @doc false
  @spec init(Poolex.pool_id(), module()) :: Behaviour.state()
  def init(pool_id, impl) do
    :ok = Settings.set_implementation(pool_id, :busy_workers, impl)
    impl(pool_id).init()
  end

  @doc false
  @spec add(Poolex.pool_id(), Behaviour.state(), Poolex.worker()) :: Behaviour.state()
  def add(pool_id, state, worker), do: impl(pool_id).add(state, worker)

  @doc false
  @spec member?(Poolex.pool_id(), Behaviour.state(), Poolex.worker()) :: boolean()
  def member?(pool_id, state, worker), do: impl(pool_id).member?(state, worker)

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
  @spec impl(Poolex.pool_id()) :: module()
  def impl(pool_id), do: Settings.get_implementation(pool_id, :busy_workers)
end
