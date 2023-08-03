defmodule Poolex.Private.IdleWorkers do
  @moduledoc false
  alias Poolex.Workers.Behaviour

  alias Poolex.Private.State

  @doc false
  @spec init(State.t(), idle_workers_impl :: module(), list(Poolex.worker())) :: State.t()
  def init(%State{} = state, impl, workers) do
    %State{state | idle_workers_impl: impl, idle_workers_state: impl.init(workers)}
  end

  @doc false
  @spec add(State.t(), Poolex.worker()) :: State.t()
  def add(%State{idle_workers_impl: impl, idle_workers_state: idle_workers_state} = state, worker) do
    %State{state | idle_workers_state: impl.add(idle_workers_state, worker)}
  end

  @doc false
  @spec remove(State.t(), Poolex.worker()) :: State.t()
  def remove(
        %State{idle_workers_impl: impl, idle_workers_state: idle_workers_state} = state,
        worker
      ) do
    %State{state | idle_workers_state: impl.remove(idle_workers_state, worker)}
  end

  @doc false
  @spec count(State.t()) :: neg_integer()
  def count(%State{idle_workers_impl: impl, idle_workers_state: state}) do
    impl.count(state)
  end

  @doc false
  @spec to_list(State.t()) :: list(Poolex.worker())
  def to_list(%State{idle_workers_impl: impl, idle_workers_state: state}) do
    impl.to_list(state)
  end

  @doc false
  @spec empty?(module(), Behaviour.state()) :: boolean()
  def empty?(impl, state), do: impl.empty?(state)

  @doc false
  @spec pop(module(), Behaviour.state()) ::
          {Poolex.worker(), Behaviour.state()} | :empty
  def pop(impl, state), do: impl.pop(state)
end
