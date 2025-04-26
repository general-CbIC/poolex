defmodule Poolex.Private.WaitingCallers do
  @moduledoc false

  alias Poolex.Private.State

  @doc false
  @spec init(State.t(), waiting_callers_impl :: module()) :: State.t()
  def init(%State{} = state, impl) do
    %{state | waiting_callers_impl: impl, waiting_callers_state: impl.init()}
  end

  @doc false
  @spec add(State.t(), Poolex.Caller.t()) :: State.t()
  def add(%State{waiting_callers_impl: impl, waiting_callers_state: waiting_callers_state} = state, caller) do
    %{state | waiting_callers_state: impl.add(waiting_callers_state, caller)}
  end

  @doc false
  @spec empty?(State.t()) :: boolean()
  def empty?(%State{waiting_callers_impl: impl, waiting_callers_state: state}) do
    impl.empty?(state)
  end

  @doc false
  @spec pop(State.t()) :: {Poolex.Caller.t(), State.t()} | :empty
  def pop(%State{waiting_callers_impl: impl, waiting_callers_state: waiting_callers_state} = state) do
    case impl.pop(waiting_callers_state) do
      {caller, new_waiting_callers_state} ->
        {caller, %{state | waiting_callers_state: new_waiting_callers_state}}

      :empty ->
        :empty
    end
  end

  @doc false
  @spec remove_by_pid(State.t(), caller_pid :: pid()) :: State.t()
  def remove_by_pid(%State{waiting_callers_impl: impl, waiting_callers_state: waiting_callers_state} = state, caller) do
    %{state | waiting_callers_state: impl.remove_by_pid(waiting_callers_state, caller)}
  end

  @doc false
  @spec remove_by_reference(State.t(), reference :: reference()) :: State.t()
  def remove_by_reference(
        %State{waiting_callers_impl: impl, waiting_callers_state: waiting_callers_state} = state,
        reference
      ) do
    %{
      state
      | waiting_callers_state: impl.remove_by_reference(waiting_callers_state, reference)
    }
  end

  @doc false
  @spec to_list(State.t()) :: list(Poolex.Caller.t())
  def to_list(%State{waiting_callers_impl: impl, waiting_callers_state: state}) do
    impl.to_list(state)
  end
end
