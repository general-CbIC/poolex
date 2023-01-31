defmodule Poolex.Workers.Impl.List do
  @moduledoc false
  @behaviour Poolex.Workers.Behaviour

  @impl true
  def init() do
    []
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
end
