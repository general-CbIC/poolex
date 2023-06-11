defmodule Poolex.BusyWorkers do
  @moduledoc false
  alias Poolex.Workers.Behaviour

  @doc false
  @spec init(module()) :: Behaviour.state()
  def init(impl) do
    impl.init()
  end

  @doc false
  @spec add(module(), Behaviour.state(), Poolex.worker()) :: Behaviour.state()
  def add(impl, state, worker), do: impl.add(state, worker)

  @doc false
  @spec member?(module(), Behaviour.state(), Poolex.worker()) :: boolean()
  def member?(impl, state, worker), do: impl.member?(state, worker)

  @doc false
  @spec remove(module(), Behaviour.state(), Poolex.worker()) :: Behaviour.state()
  def remove(impl, state, worker), do: impl.remove(state, worker)

  @doc false
  @spec count(module(), Behaviour.state()) :: non_neg_integer()
  def count(impl, state), do: impl.count(state)

  @doc false
  @spec to_list(module(), Behaviour.state()) :: list(Poolex.worker())
  def to_list(impl, state), do: impl.to_list(state)
end
