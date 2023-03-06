defmodule Poolex.IdleWorkers do
  @moduledoc false
  alias Poolex.Workers.Behaviour

  @spec init(module()) :: Behaviour.state()
  def init(impl), do: impl.init()

  @spec init(module(), list(Behaviour.worker())) :: Behaviour.state()
  def init(impl, workers), do: impl.init(workers)

  @spec add(module(), Behaviour.state(), Behaviour.worker()) :: Behaviour.state()
  def add(impl, state, worker), do: impl.add(state, worker)

  @spec remove(module(), Behaviour.state(), Behaviour.worker()) :: Behaviour.state()
  def remove(impl, state, worker), do: impl.remove(state, worker)

  @spec count(module(), Behaviour.state()) :: non_neg_integer()
  def count(impl, state), do: impl.count(state)

  @spec to_list(module(), Behaviour.state()) :: list(Behaviour.worker())
  def to_list(impl, state), do: impl.to_list(state)

  @spec empty?(module(), Behaviour.state()) :: boolean()
  def empty?(impl, state), do: impl.empty?(state)

  @spec pop(module(), Behaviour.state()) :: {Behaviour.worker(), Behaviour.state()} | :empty
  def pop(impl, state), do: impl.pop(state)
end
