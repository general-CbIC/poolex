defmodule PoolexTest do
  use ExUnit.Case
  doctest Poolex

  @pool_name :test_pool

  describe "state" do
    test "valid after initialization" do
      initial_fun = fn -> 0 end

      Poolex.start_link(@pool_name,
        worker_module: Agent,
        worker_args: [initial_fun],
        workers_count: 5
      )

      state = Poolex.get_state(@pool_name)

      assert state.__struct__ == Poolex.State
      assert state.busy_workers_count == 0
      assert state.busy_workers_pids == []
      assert state.idle_workers_count == 5
      assert Enum.count(state.idle_workers_pids) == 5
      assert state.worker_module == Agent
      assert state.worker_args == [initial_fun]
    end

    test "valid after holding some workers" do
      initial_fun = fn -> 0 end

      Poolex.start_link(@pool_name,
        worker_module: Agent,
        worker_args: [initial_fun],
        workers_count: 5
      )

      test_process = self()

      spawn(fn ->
        Poolex.run(@pool_name, fn _pid ->
          Process.send(test_process, nil, [])
          :timer.sleep(:timer.seconds(5))
        end)
      end)

      receive do
        _message -> nil
      end

      state = Poolex.get_state(@pool_name)

      assert state.__struct__ == Poolex.State
      assert state.busy_workers_count == 1
      assert Enum.count(state.busy_workers_pids) == 1
      assert state.idle_workers_count == 4
      assert Enum.count(state.idle_workers_pids) == 4
      assert state.worker_module == Agent
      assert state.worker_args == [initial_fun]
    end
  end

  describe "run/2" do
    test "updates agent's state" do
      Poolex.start_link(@pool_name,
        worker_module: Agent,
        worker_args: [fn -> 0 end],
        workers_count: 1
      )

      Poolex.run(@pool_name, fn pid -> Agent.update(pid, fn _state -> 1 end) end)

      [agent_pid] = Poolex.get_state(@pool_name).idle_workers_pids

      assert 1 == Agent.get(agent_pid, fn state -> state end)
    end

    test "get result from custom worker" do
      Poolex.start_link(@pool_name,
        worker_module: SomeWorker,
        worker_args: [],
        workers_count: 2
      )

      result = Poolex.run(@pool_name, fn pid -> GenServer.call(pid, :do_some_work) end)
      assert result == :some_result
    end

    test "test waiting queue" do
      Poolex.start_link(
        @pool_name,
        worker_module: SomeWorker,
        worker_args: [],
        workers_count: 5
      )

      result =
        1..20
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Poolex.run(@pool_name, fn pid ->
              GenServer.call(pid, {:do_some_work_with_delay, 100})
            end)
          end)
        end)
        |> Enum.map(&Task.await/1)

      assert length(result) == 20
      assert Enum.all?(result, &(&1 == :some_result))
    end
  end

  describe "restarting terminated processes" do
    test "works on idle workers" do
      Poolex.start_link(@pool_name,
        worker_module: Agent,
        worker_args: [fn -> 0 end],
        workers_count: 1
      )

      [agent_pid] = Poolex.get_state(@pool_name).idle_workers_pids

      Process.exit(agent_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      [new_agent_pid] = Poolex.get_state(@pool_name).idle_workers_pids

      assert agent_pid != new_agent_pid
    end

    test "works on busy workers" do
      Poolex.start_link(@pool_name,
        worker_module: Agent,
        worker_args: [fn -> 0 end],
        workers_count: 1
      )

      test_process = self()

      spawn(fn ->
        Poolex.run(@pool_name, fn _pid ->
          Process.send(test_process, nil, [])
          :timer.sleep(:timer.seconds(5))
        end)
      end)

      receive do
        _message -> nil
      end

      [agent_pid] = Poolex.get_state(@pool_name).busy_workers_pids

      Process.exit(agent_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      [new_agent_pid] = Poolex.get_state(@pool_name).idle_workers_pids

      assert agent_pid != new_agent_pid
    end
  end
end
