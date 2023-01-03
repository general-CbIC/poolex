defmodule Poolex.Monitoring do
  @moduledoc """
  Interfaces to hide monitoring implementation.
  """
  @type monitor_id() :: atom() | reference()

  @spec init(Poolex.pool_id()) :: {:ok, monitor_id()}
  def init(pool_id) do
    monitor_id = :ets.new(:"#{pool_id}_references", [:set, :named_table, :private])

    {:ok, monitor_id}
  end

  @spec add(monitor_id(), pid()) :: :ok
  def add(monitor_id, process_pid) do
    reference = Process.monitor(process_pid)
    :ets.insert_new(monitor_id, {reference, process_pid})

    :ok
  end

  @spec remove(monitor_id(), reference()) :: :ok
  def remove(monitor_id, monitoring_reference) do
    true = Process.demonitor(monitoring_reference)
    true = :ets.delete(monitor_id, monitoring_reference)

    :ok
  end

  @spec get_process(monitor_id(), reference()) :: pid()
  def get_process(monitor_id, reference) do
    [{_reference, process_pid}] = :ets.lookup(monitor_id, reference)
    process_pid
  end
end
