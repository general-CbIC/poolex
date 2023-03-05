defmodule Poolex.WaitingCallers do
  @moduledoc false
  alias Poolex.Callers.Behaviour

  @spec init(module()) :: Behaviour.state()
  def init(impl), do: impl.init()

  @spec add(module(), Behaviour.state(), Behaviour.caller()) :: Behaviour.state()
  def add(impl, state, caller), do: impl.add(state, caller)

  @spec empty?(module(), Behaviour.state()) :: boolean()
  def empty?(impl, state), do: impl.empty?(state)

  @spec pop(module(), Behaviour.state()) :: {Behaviour.caller(), Behaviour.state()} | :empty
  def pop(impl, state), do: impl.pop(state)

  @spec remove_by_pid(module(), Behaviour.state(), pid()) :: Behaviour.state()
  def remove_by_pid(impl, state, caller_pid), do: impl.remove_by_pid(state, caller_pid)

  @spec to_list(module(), Behaviour.state()) :: list(Behaviour.caller())
  def to_list(impl, state), do: impl.to_list(state)
end
