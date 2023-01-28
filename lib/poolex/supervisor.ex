defmodule Poolex.Supervisor do
  @moduledoc false
  use DynamicSupervisor

  @doc false
  @spec start_link() :: Supervisor.on_start()
  def start_link do
    DynamicSupervisor.start_link(__MODULE__, nil)
  end

  @doc false
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
