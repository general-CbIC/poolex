defmodule Poolex.Private.IdleWorkers do
  @moduledoc false
  alias Poolex.Workers.Behaviour

  @doc false
  @spec init(module()) :: Behaviour.state()
  def init(impl) do
    impl.init()
  end

  @doc false
  @spec init(module(), list(Poolex.worker())) :: Behaviour.state()
  def init(impl, workers) do
    impl.init(workers)
  end

  @doc false
  @spec add(module(), Behaviour.state(), Poolex.worker()) :: Behaviour.state()
  def add(impl, state, worker), do: impl.add(state, worker)

  @doc false
  @spec remove(module(), Behaviour.state(), Poolex.worker()) :: Behaviour.state()
  def remove(impl, state, worker), do: impl.remove(state, worker)

  @doc false
  @spec count(module(), Behaviour.state()) :: non_neg_integer()
  def count(impl, state), do: impl.count(state)

  @doc false
  @spec to_list(module(), Behaviour.state()) :: list(Poolex.worker())
  def to_list(impl, state), do: impl.to_list(state)

  @doc false
  @spec empty?(module(), Behaviour.state()) :: boolean()
  def empty?(impl, state), do: impl.empty?(state)

  @doc false
  @spec pop(module(), Behaviour.state()) ::
          {Poolex.worker(), Behaviour.state()} | :empty
  def pop(impl, state), do: impl.pop(state)
end
