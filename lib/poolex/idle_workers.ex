defmodule Poolex.IdleWorkers do
  @moduledoc false
  @behaviour Poolex.Workers.Behaviour

  @impl true
  def init(), do: impl().init()
  @impl true
  def init(workers), do: impl().init(workers)
  @impl true
  def add(state, worker), do: impl().add(state, worker)
  @impl true
  def member?(state, worker), do: impl().member?(state, worker)
  @impl true
  def remove(state, worker), do: impl().remove(state, worker)
  @impl true
  def count(state), do: impl().count(state)
  @impl true
  def to_list(state), do: impl().to_list(state)
  @impl true
  def empty?(state), do: impl().empty?(state)
  @impl true
  def pop(state), do: impl().pop(state)

  defp impl, do: Poolex.Workers.Settings.idle_workers_impl()
end
