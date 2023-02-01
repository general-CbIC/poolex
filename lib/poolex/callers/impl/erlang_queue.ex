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
  def remove(state, caller) do
    :queue.filter(fn {caller_pid, _} -> caller_pid != caller end, state)
  end

  @impl true
  def to_list(state) do
    :queue.to_list(state)
  end
end
