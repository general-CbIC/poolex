defmodule Poolex.Workers.Impl.List do
  @moduledoc """
  Simple workers stack (LIFO) implementation based on List.
  """
  @behaviour Poolex.Workers.Behaviour

  @impl true
  def init() do
    []
  end

  @impl true
  def init(workers) do
    workers
  end

  @impl true
  def add(state, worker) do
    [worker | state]
  end

  @impl true
  def member?(state, worker) do
    Enum.member?(state, worker)
  end

  @impl true
  def remove(state, worker) do
    List.delete(state, worker)
  end

  @impl true
  def count(state) do
    Enum.count(state)
  end

  @impl true
  def to_list(state) do
    state
  end

  @impl true
  def empty?(state) do
    Enum.empty?(state)
  end

  @impl true
  def pop([]), do: :empty
  def pop([worker]), do: {worker, []}
  def pop([worker | rest]), do: {worker, rest}
end
