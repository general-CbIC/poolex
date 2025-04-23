defmodule Poolex.Private.Supervisor do
  @moduledoc false
  use DynamicSupervisor

  @doc false
  @spec start_link() :: Supervisor.on_start()
  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [])
  end

  @doc false
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 0)
  end
end
