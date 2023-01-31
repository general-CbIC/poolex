defmodule Poolex.Workers.Settings do
  @moduledoc false

  @doc false
  @spec busy_workers_impl() :: module()
  def busy_workers_impl do
    Application.get_env(:poolex, :busy_workers_impl, Poolex.Workers.Impl.List)
  end

  @doc false
  @spec idle_workers_impl() :: module()
  def idle_workers_impl do
    Application.get_env(:poolex, :idle_workers_impl, Poolex.Workers.Impl.List)
  end
end
