defmodule Poolex.Workers.Impl.ErlangQueue do
  @moduledoc """
  Simple workers queue (FIFO) implementation based on Erlang `:queue`
  """
  @behaviour Poolex.Workers.Behaviour

  @impl true
  def init do
    :queue.new()
  end

  @impl true
  def init(workers) do
    :queue.from_list(workers)
  end

  @impl true
  def add(state, worker) do
    :queue.in(worker, state)
  end

  @impl true
  def member?(state, worker) do
    :queue.member(worker, state)
  end

  @impl true
  def remove(state, worker) do
    :queue.filter(fn element -> element != worker end, state)
  end

  @impl true
  def count(state) do
    :queue.len(state)
  end

  @impl true
  def to_list(state) do
    :queue.to_list(state)
  end

  @impl true
  def empty?(state) do
    :queue.is_empty(state)
  end

  @impl true
  def pop(state) do
    case :queue.out(state) do
      {{:value, worker}, new_state} -> {worker, new_state}
      {:empty, _state} -> :empty
    end
  end
end
