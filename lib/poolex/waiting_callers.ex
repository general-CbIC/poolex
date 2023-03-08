defmodule Poolex.WaitingCallers do
  @moduledoc false
  alias Poolex.Settings
  alias Poolex.Callers.Behaviour

  @doc false
  @spec init(Poolex.pool_id(), module()) :: Behaviour.state()
  def init(pool_id, impl) do
    :ok = Settings.set_implementation(pool_id, :waiting_callers, impl)
    impl(pool_id).init()
  end

  @doc false
  @spec add(Poolex.pool_id(), Behaviour.state(), Behaviour.caller()) :: Behaviour.state()
  def add(pool_id, state, caller), do: impl(pool_id).add(state, caller)

  @doc false
  @spec empty?(Poolex.pool_id(), Behaviour.state()) :: boolean()
  def empty?(pool_id, state), do: impl(pool_id).empty?(state)

  @doc false
  @spec pop(Poolex.pool_id(), Behaviour.state()) ::
          {Behaviour.caller(), Behaviour.state()} | :empty
  def pop(pool_id, state), do: impl(pool_id).pop(state)

  @doc false
  @spec remove_by_pid(Poolex.pool_id(), Behaviour.state(), pid()) :: Behaviour.state()
  def remove_by_pid(pool_id, state, caller_pid) do
    impl(pool_id).remove_by_pid(state, caller_pid)
  end

  @doc false
  @spec to_list(Poolex.pool_id(), Behaviour.state()) :: list(Behaviour.caller())
  def to_list(pool_id, state), do: impl(pool_id).to_list(state)

  @doc false
  @spec impl(Poolex.pool_id()) :: module()
  def impl(pool_id), do: Settings.get_implementation(pool_id, :waiting_callers)
end
