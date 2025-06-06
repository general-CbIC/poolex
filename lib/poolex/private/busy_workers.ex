defmodule Poolex.Private.BusyWorkers do
  @moduledoc false

  alias Poolex.Private.State

  @doc false
  @spec init(State.t(), busy_workers_impl :: module()) :: State.t()
  def init(%State{} = state, impl) do
    %{state | busy_workers_impl: impl, busy_workers_state: impl.init()}
  end

  @doc false
  @spec add(State.t(), Poolex.worker()) :: State.t()
  def add(%State{busy_workers_impl: impl, busy_workers_state: busy_workers_state} = state, worker) do
    %{state | busy_workers_state: impl.add(busy_workers_state, worker)}
  end

  @doc false
  @spec member?(State.t(), Poolex.worker()) :: boolean()
  def member?(%State{busy_workers_impl: impl, busy_workers_state: busy_workers_state}, worker) do
    impl.member?(busy_workers_state, worker)
  end

  @doc false
  @spec remove(State.t(), Poolex.worker()) :: State.t()
  def remove(%State{busy_workers_impl: impl, busy_workers_state: busy_workers_state} = state, worker) do
    %{state | busy_workers_state: impl.remove(busy_workers_state, worker)}
  end

  @doc false
  @spec count(State.t()) :: non_neg_integer()
  def count(%State{busy_workers_impl: impl, busy_workers_state: state}) do
    impl.count(state)
  end

  @doc false
  @spec to_list(State.t()) :: list(Poolex.worker())
  def to_list(%State{busy_workers_impl: impl, busy_workers_state: state}) do
    impl.to_list(state)
  end
end
