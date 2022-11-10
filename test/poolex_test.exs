defmodule PoolexTest do
  use ExUnit.Case
  doctest Poolex

  @pool_name :test_pool

  describe "state" do
    test "valid after initialization" do
      Poolex.start_link(@pool_name,
        worker_module: Agent,
        worker_args: fn 0 -> 0 end,
        workers_count: 5
      )

      state = Poolex.get_state(@pool_name)

      assert state.__struct__ == Poolex.State
      assert state.busy_workers_count == 0
      assert state.busy_workers_pids == []
      assert state.idle_workers_count == 5
      assert Enum.count(state.idle_workers_pids) == 5
      assert state.worker_module == Agent
      assert state.worker_args == [fn 0 -> 0 end]
    end

    test "valid after holding some workers" do
      Poolex.start_link(@pool_name,
        worker_module: Agent,
        worker_args: fn 0 -> 0 end,
        workers_count: 5
      )

      spawn(fn ->
        Poolex.run(@pool_name, fn _pid ->
          :timer.sleep(:timer.seconds(5))
          :ok
        end)
      end)

      state = Poolex.get_state(@pool_name)

      assert state.__struct__ == Poolex.State
      assert state.busy_workers_count == 1
      assert Enum.count(state.busy_workers_pids) == 1
      assert state.idle_workers_count == 4
      assert Enum.count(state.idle_workers_pids) == 4
      assert state.worker_module == Agent
      assert state.worker_args == [fn 0 -> 0 end]
    end
  end
end
