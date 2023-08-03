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
  @spec add(State.t(), Poolex.caller()) :: State.t()
  def add(
        %State{waiting_callers_impl: impl, waiting_callers_state: waiting_callers_state} = state,
        caller
      ) do
    %State{state | waiting_callers_state: impl.add(waiting_callers_state, caller)}
  end

  @doc false
  @spec empty?(State.t()) :: boolean()
  def empty?(%State{waiting_callers_impl: impl, waiting_callers_state: state}) do
    impl.empty?(state)
  end

  @doc false
  @spec pop(State.t()) :: {Poolex.caller(), State.t()} | :empty
  def pop(
        %State{waiting_callers_impl: impl, waiting_callers_state: waiting_callers_state} = state
      ) do
    case impl.pop(waiting_callers_state) do
      {caller, new_waiting_callers_state} ->
        {caller, %State{state | waiting_callers_state: new_waiting_callers_state}}

      :empty ->
        :empty
    end
  end

  @doc false
  @spec remove_by_pid(module(), Behaviour.state(), pid()) :: Behaviour.state()
  def remove_by_pid(impl, state, caller_pid) do
    impl.remove_by_pid(state, caller_pid)
  end

  @doc false
  @spec to_list(module(), Behaviour.state()) :: list(Poolex.caller())
  def to_list(impl, state), do: impl.to_list(state)
end
