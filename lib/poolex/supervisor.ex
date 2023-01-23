defmodule Poolex.Supervisor do
  @moduledoc false
  use DynamicSupervisor

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, nil)
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
