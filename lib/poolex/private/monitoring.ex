defmodule Poolex.Private.Monitoring do
  @moduledoc false
  alias Poolex.Private.State

  @type kind_of_process() :: :worker | :waiting_caller

  @spec add(State.t(), worker_pid :: pid(), kind_of_process()) :: State.t()
  @doc """
  Start monitoring given worker or caller process.
  """
  def add(%{monitors: monitors} = state, process_pid, kind_of_process) do
    reference = Process.monitor(process_pid)
    %{state | monitors: Map.put(monitors, reference, kind_of_process)}
  end

  @spec remove(State.t(), reference()) :: {kind_of_process(), State.t()}
  @doc """
  Stop monitoring given worker or caller process and return kind of it.
  """
  def remove(%{monitors: monitors} = state, monitoring_reference) do
    true = Process.demonitor(monitoring_reference)
    kind_of_process = Map.get(monitors, monitoring_reference)
    state = %{state | monitors: Map.delete(monitors, monitoring_reference)}
    {kind_of_process, state}
  end
end
