defmodule Poolex.Private.Monitoring do
  @moduledoc false
  @type kind_of_process() :: :worker | :waiting_caller

  @spec init() :: {:ok, pid()}
  @doc """
  Create new monitoring references storage.
  """
  def init do
    Agent.start_link(fn -> %{} end)
  end

  @spec stop(pid()) :: :ok
  @doc """
  Delete storage.
  """
  def stop(pid) do
    Agent.stop(pid)
  end

  @spec add(monitor_pid :: pid(), worker_pid :: pid(), kind_of_process()) :: :ok
  @doc """
  Start monitoring given worker or caller process.
  """
  def add(monitor_pid, process_pid, kind_of_process) do
    reference = Process.monitor(process_pid)

    Agent.update(monitor_pid, fn state -> Map.put(state, reference, kind_of_process) end)
  end

  @spec remove(monitor_pid :: pid(), reference()) :: kind_of_process()
  @doc """
  Stop monitoring given worker or caller process and return kind of it.
  """
  def remove(monitor_pid, monitoring_reference) do
    true = Process.demonitor(monitoring_reference)

    Agent.get_and_update(monitor_pid, fn state ->
      {Map.get(state, monitoring_reference), Map.delete(state, monitoring_reference)}
    end)
  end
end
