defmodule Poolex.Callers.Settings do
  @moduledoc false

  @doc false
  @spec callers_impl() :: module()
  def callers_impl do
    Application.get_env(:poolex, :callers_impl, Poolex.Callers.Impl.ErlangQueue)
  end
end
