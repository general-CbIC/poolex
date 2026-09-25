defmodule PoolHelpers do
  @moduledoc """
  Module with helpers functions for launching pools and long tasks.
  """

  import ExUnit.Assertions, only: [assert: 1]

  alias Poolex.Private.Options.Parser, as: OptionsParser
  alias Poolex.Private.WaitingCallers

  @spec start_pool(list(Poolex.poolex_option())) :: Poolex.pool_id()
  def start_pool(options) do
    {:ok, _pid} = ExUnit.Callbacks.start_supervised({Poolex, options})

    OptionsParser.parse_pool_id(options)
  end

  @doc """
  Launches a caller that holds a worker for `delay` ms.

  Returns once the caller holds a worker or waits for one in the pool's queue.
  """
  @spec launch_long_task(Poolex.pool_id(), timeout()) :: :ok
  def launch_long_task(pool_id, delay \\ to_timeout(second: 4)) do
    launch_long_tasks(pool_id, 1, delay)
  end

  @doc """
  Launches `count` callers that hold a worker for `delay` ms each.

  Returns once every caller holds a worker or waits for one in the pool's queue.
  """
  @spec launch_long_tasks(Poolex.pool_id(), non_neg_integer(), timeout()) :: :ok
  def launch_long_tasks(pool_id, count, delay \\ to_timeout(second: 4)) do
    callers =
      for _i <- 1..count do
        spawn(fn -> do_launch(pool_id, delay) end)
      end

    eventually(fn ->
      state = :sys.get_state(pool_id)
      holding = MapSet.new(Map.values(state.manual_monitors), fn {caller, _monitor} -> caller end)
      waiting = MapSet.new(WaitingCallers.to_list(state), fn %Poolex.Caller{from: {caller, _tag}} -> caller end)

      assert Enum.all?(callers, &(&1 in holding or &1 in waiting))
    end)
  end

  @doc """
  Runs `assertion` until it stops raising `ExUnit.AssertionError` or `MatchError`,
  or until `timeout` ms elapse; then re-raises the last error.

  Use it instead of a fixed `Process.sleep/1` when waiting for the pool to process
  asynchronous messages (casts, `:DOWN`, timers).
  """
  @spec eventually((-> result), timeout()) :: result when result: var
  def eventually(assertion, timeout \\ 1_000) do
    do_eventually(assertion, System.monotonic_time(:millisecond) + timeout)
  end

  defp do_eventually(assertion, deadline) do
    assertion.()
  rescue
    error in [ExUnit.AssertionError, MatchError] ->
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(5)
        do_eventually(assertion, deadline)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp do_launch(pool_id, delay) do
    Poolex.run(
      pool_id,
      fn pid -> GenServer.call(pid, {:do_some_work_with_delay, delay}) end,
      checkout_timeout: to_timeout(second: 5)
    )
  end
end
