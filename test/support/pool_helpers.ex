defmodule PoolHelpers do
  @moduledoc """
  Module with helpers functions for launching pools and long tasks.
  """

  @spec start_pool(list(Poolex.poolex_option())) :: Poolex.pool_id()
  def start_pool(options) do
    {:ok, _pid} = ExUnit.Callbacks.start_supervised({Poolex, options})

    Keyword.fetch!(options, :pool_id)
  end

  @spec launch_long_task(Poolex.pool_id(), timeout()) :: :ok
  def launch_long_task(pool_id, delay \\ :timer.seconds(4)) do
    launch_long_tasks(pool_id, 1, delay)
  end

  @spec launch_long_tasks(Poolex.pool_id(), non_neg_integer(), timeout()) :: :ok
  def launch_long_tasks(pool_id, count, delay \\ :timer.seconds(4)) do
    for _i <- 1..count do
      spawn(fn ->
        Poolex.run(
          pool_id,
          fn pid -> GenServer.call(pid, {:do_some_work_with_delay, delay}) end,
          checkout_timeout: 100
        )
      end)
    end

    :timer.sleep(10)
  end
end
