defmodule Poolex.Private.IdleOverflowedWorkers do
  @moduledoc false

  alias Poolex.Private.State

  @doc false
  @spec init(State.t(), idle_overflowed_workers_impl :: module()) :: State.t()
  def init(%State{} = state, impl) do
    %{state | idle_overflowed_workers_impl: impl, idle_overflowed_workers_state: impl.init()}
  end

  @doc false
  @spec add(State.t(), Poolex.worker()) :: State.t()
  def add(
        %State{idle_overflowed_workers_impl: impl, idle_overflowed_workers_state: idle_overflowed_workers_state} = state,
        worker
      ) do
    %{state | idle_overflowed_workers_state: impl.add(idle_overflowed_workers_state, worker)}
  end

  @doc false
  @spec member?(State.t(), Poolex.worker()) :: boolean()
  def member?(
        %State{idle_overflowed_workers_impl: impl, idle_overflowed_workers_state: idle_overflowed_workers_state},
        worker
      ) do
    impl.member?(idle_overflowed_workers_state, worker)
  end

  @doc false
  @spec remove(State.t(), Poolex.worker()) :: State.t()
  def remove(
        %State{idle_overflowed_workers_impl: impl, idle_overflowed_workers_state: idle_overflowed_workers_state} = state,
        worker
      ) do
    %{state | idle_overflowed_workers_state: impl.remove(idle_overflowed_workers_state, worker)}
  end

  @doc false
  @spec count(State.t()) :: neg_integer()
  def count(%State{idle_overflowed_workers_impl: impl, idle_overflowed_workers_state: state}) do
    impl.count(state)
  end

  @doc false
  @spec to_list(State.t()) :: list(Poolex.worker())
  def to_list(%State{idle_overflowed_workers_impl: impl, idle_overflowed_workers_state: state}) do
    impl.to_list(state)
  end

  @doc false
  @spec empty?(State.t()) :: boolean()
  def empty?(%State{idle_overflowed_workers_impl: impl, idle_overflowed_workers_state: state}) do
    impl.empty?(state)
  end

  @doc false
  @spec pop(State.t()) :: {Poolex.worker(), State.t()} | :empty
  def pop(
        %State{idle_overflowed_workers_impl: impl, idle_overflowed_workers_state: idle_overflowed_workers_state} = state
      ) do
    case impl.pop(idle_overflowed_workers_state) do
      {worker, new_idle_overflowed_workers_state} ->
        {worker, %{state | idle_overflowed_workers_state: new_idle_overflowed_workers_state}}

      :empty ->
        :empty
    end
  end
end
