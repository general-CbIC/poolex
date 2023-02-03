defmodule Poolex.WaitingCallers do
  @moduledoc false
  @behaviour Poolex.Callers.Behaviour

  @impl true
  def init(), do: impl().init()

  @impl true
  def add(state, caller), do: impl().add(state, caller)

  @impl true
  def empty?(state), do: impl().empty?(state)

  @impl true
  def pop(state), do: impl().pop(state)

  @impl true
  def remove_by_pid(state, caller_pid), do: impl().remove_by_pid(state, caller_pid)

  @impl true
  def to_list(state), do: impl().to_list(state)

  defp impl, do: Poolex.Callers.Settings.callers_impl()
end
