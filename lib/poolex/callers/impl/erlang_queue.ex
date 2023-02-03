defmodule Poolex.Callers.Impl.ErlangQueue do
  @moduledoc false
  @behaviour Poolex.Callers.Behaviour

  @impl true
  def init do
    :queue.new()
  end

  @impl true
  def add(state, caller) do
    :queue.in(caller, state)
  end

  @impl true
  def empty?(state) do
    :queue.is_empty(state)
  end

  @impl true
  def pop(state) do
    case :queue.out(state) do
      {{:value, caller}, new_state} -> {caller, new_state}
      _ -> :empty
    end
  end

  @impl true
  def remove_by_pid(state, caller_pid) do
    :queue.filter(fn {pid, _} -> pid != caller_pid end, state)
  end

  @impl true
  def to_list(state) do
    :queue.to_list(state)
  end
end
