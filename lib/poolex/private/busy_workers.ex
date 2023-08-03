defmodule Poolex.Private.BusyWorkers do
  @moduledoc false

  alias Poolex.State

  @type busy_workers_state() :: Poolex.Workers.Behaviour.state()

  @doc false
  @spec init(State.t(), busy_workers_impl :: module()) :: State.t()
  def init(%State{} = state, impl) do
    %State{state | busy_workers_impl: impl, busy_workers_state: impl.init()}
  end

  @doc false
  @spec add(State.t(), Poolex.worker()) :: State.t()
  def add(%State{busy_workers_impl: impl, busy_workers_state: busy_workers_state} = state, worker) do
    %State{state | busy_workers_state: impl.add(busy_workers_state, worker)}
  end

  @doc false
  @spec member?(module(), busy_workers_state(), Poolex.worker()) :: boolean()
  def member?(impl, state, worker), do: impl.member?(state, worker)

  @doc false
  @spec remove(module(), busy_workers_state(), Poolex.worker()) :: busy_workers_state()
  def remove(impl, state, worker), do: impl.remove(state, worker)

  @doc false
  @spec count(module(), busy_workers_state()) :: non_neg_integer()
  def count(impl, state), do: impl.count(state)

  @doc false
  @spec to_list(module(), busy_workers_state()) :: list(Poolex.worker())
  def to_list(impl, state), do: impl.to_list(state)
end