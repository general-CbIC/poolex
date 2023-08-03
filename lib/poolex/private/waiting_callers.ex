defmodule Poolex.Private.WaitingCallers do
  @moduledoc false

  alias Poolex.Callers.Behaviour

  alias Poolex.Private.State

  @doc false
  @spec init(State.t(), waiting_callers_impl :: module()) :: State.t()
  def init(%State{} = state, impl) do
    %State{state | waiting_callers_impl: impl, waiting_callers_state: impl.init()}
  end

  @doc false
  @spec add(module(), Behaviour.state(), Poolex.caller()) :: Behaviour.state()
  def add(impl, state, caller), do: impl.add(state, caller)

  @doc false
  @spec empty?(module(), Behaviour.state()) :: boolean()
  def empty?(impl, state), do: impl.empty?(state)

  @doc false
  @spec pop(module(), Behaviour.state()) ::
          {Poolex.caller(), Behaviour.state()} | :empty
  def pop(impl, state), do: impl.pop(state)

  @doc false
  @spec remove_by_pid(module(), Behaviour.state(), pid()) :: Behaviour.state()
  def remove_by_pid(impl, state, caller_pid) do
    impl.remove_by_pid(state, caller_pid)
  end

  @doc false
  @spec to_list(module(), Behaviour.state()) :: list(Poolex.caller())
  def to_list(impl, state), do: impl.to_list(state)
end
