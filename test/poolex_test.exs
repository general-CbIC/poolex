defmodule PoolexTest do
  use ExUnit.Case
  doctest Poolex

  @pool_name :test_pool

  describe "state" do
    test "is valid after initialization" do
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
  end
end
