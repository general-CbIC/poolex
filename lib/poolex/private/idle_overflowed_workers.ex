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
    %{
      state
      | idle_overflowed_workers_state: impl.add(idle_overflowed_workers_state, worker),
        idle_overflowed_workers_last_touches: Map.put(state.idle_overflowed_workers_last_touches, worker, Time.utc_now())
    }
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
    %{
      state
      | idle_overflowed_workers_state: impl.remove(idle_overflowed_workers_state, worker),
        idle_overflowed_workers_last_touches: Map.delete(state.idle_overflowed_workers_last_touches, worker)
    }
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
        {worker,
         %{
           state
           | idle_overflowed_workers_state: new_idle_overflowed_workers_state,
             idle_overflowed_workers_last_touches: Map.delete(state.idle_overflowed_workers_last_touches, worker)
         }}

      :empty ->
        :empty
    end
  end

  @doc false
  @spec expired?(State.t(), Poolex.worker()) :: boolean()
  def expired?(%State{idle_overflowed_workers_last_touches: last_touches, worker_shutdown_delay: timeout}, worker) do
    case Map.get(last_touches, worker) do
      nil -> false
      # We need to remove the 10ms tolerance to avoid infelicity
      last_touch -> Time.diff(Time.utc_now(), last_touch, :millisecond) > timeout - 10
    end
  end
end
