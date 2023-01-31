defmodule PoolexTest do
  use ExUnit.Case
  doctest Poolex

  setup do
    [pool_name: pool_name()]
  end

  describe "debug info" do
    test "valid after initialization", %{pool_name: pool_name} do
      initial_fun = fn -> 0 end

      Poolex.start_link(pool_name,
        worker_module: Agent,
        worker_args: [initial_fun],
        workers_count: 5
      )

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.__struct__ == Poolex.DebugInfo
      assert debug_info.busy_workers_count == 0
      assert debug_info.busy_workers_pids == []
      assert debug_info.idle_workers_count == 5
      assert Enum.count(debug_info.idle_workers_pids) == 5
      assert debug_info.worker_module == Agent
      assert debug_info.worker_args == [initial_fun]
      assert debug_info.waiting_callers == []
    end

    test "valid after holding some workers", %{pool_name: pool_name} do
      initial_fun = fn -> 0 end

      Poolex.start_link(pool_name,
        worker_module: Agent,
        worker_args: [initial_fun],
        workers_count: 5
      )

      test_process = self()

      spawn(fn ->
        Poolex.run(pool_name, fn _pid ->
          Process.send(test_process, nil, [])
          :timer.sleep(:timer.seconds(5))
        end)
      end)

      receive do
        _message -> nil
      end

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.__struct__ == Poolex.DebugInfo
      assert debug_info.busy_workers_count == 1
      assert Enum.count(debug_info.busy_workers_pids) == 1
      assert debug_info.idle_workers_count == 4
      assert Enum.count(debug_info.idle_workers_pids) == 4
      assert debug_info.worker_module == Agent
      assert debug_info.worker_args == [initial_fun]
      assert debug_info.waiting_callers == []
    end
  end

  describe "run/2" do
    test "updates agent's state", %{pool_name: pool_name} do
      Poolex.start_link(pool_name,
        worker_module: Agent,
        worker_args: [fn -> 0 end],
        workers_count: 1
      )

      Poolex.run(pool_name, fn pid -> Agent.update(pid, fn _state -> 1 end) end)

      [agent_pid] = Poolex.get_debug_info(pool_name).idle_workers_pids

      assert 1 == Agent.get(agent_pid, fn state -> state end)
    end

    test "get result from custom worker", %{pool_name: pool_name} do
      Poolex.start_link(pool_name, worker_module: SomeWorker, workers_count: 2)

      result = Poolex.run(pool_name, fn pid -> GenServer.call(pid, :do_some_work) end)
      assert result == {:ok, :some_result}

      result = Poolex.run!(pool_name, fn pid -> GenServer.call(pid, :do_some_work) end)
      assert result == :some_result
    end

    test "test waiting queue", %{pool_name: pool_name} do
      Poolex.start_link(pool_name, worker_module: SomeWorker, workers_count: 5)

      result =
        1..20
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Poolex.run!(pool_name, fn pid ->
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
    test "works on idle workers", %{pool_name: pool_name} do
      Poolex.start_link(pool_name,
        worker_module: Agent,
        worker_args: [fn -> 0 end],
        workers_count: 1
      )

      [agent_pid] = Poolex.get_debug_info(pool_name).idle_workers_pids

      Process.exit(agent_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      [new_agent_pid] = Poolex.get_debug_info(pool_name).idle_workers_pids

      assert agent_pid != new_agent_pid
    end

    test "works on busy workers", %{pool_name: pool_name} do
      Poolex.start_link(pool_name,
        worker_module: Agent,
        worker_args: [fn -> 0 end],
        workers_count: 1
      )

      test_process = self()

      spawn(fn ->
        Poolex.run(pool_name, fn _pid ->
          Process.send(test_process, nil, [])
          :timer.sleep(:timer.seconds(5))
        end)
      end)

      receive do
        _message -> nil
      end

      [agent_pid] = Poolex.get_debug_info(pool_name).busy_workers_pids

      Process.exit(agent_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      [new_agent_pid] = Poolex.get_debug_info(pool_name).idle_workers_pids

      assert agent_pid != new_agent_pid
    end

    test "works on callers", %{pool_name: pool_name} do
      Poolex.start_link(pool_name, worker_module: SomeWorker, workers_count: 1)

      1..10
      |> Enum.each(fn _ ->
        spawn(fn ->
          Poolex.run(pool_name, fn pid ->
            GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)})
          end)
        end)
      end)

      waiting_caller =
        spawn(fn ->
          Poolex.run(pool_name, fn pid ->
            GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(3)})
          end)
        end)

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)
      assert length(debug_info.waiting_callers) == 10

      assert Enum.find(debug_info.waiting_callers, fn {pid, _} ->
               pid == waiting_caller
             end)

      Process.exit(waiting_caller, :kill)
      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)
      assert length(debug_info.waiting_callers) == 9

      refute Enum.find(debug_info.waiting_callers, fn {pid, _} ->
               pid == waiting_caller
             end)
    end

    test "runtime errors", %{pool_name: pool_name} do
      Poolex.start(pool_name, worker_module: SomeWorker, workers_count: 1)
      Poolex.run(pool_name, fn pid -> GenServer.call(pid, :do_raise) end)

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_count == 1
      assert debug_info.idle_workers_pids |> hd() |> Process.alive?()
    end
  end

  describe "timeouts" do
    test "when caller waits too long", %{pool_name: pool_name} do
      Poolex.start_link(pool_name, worker_module: SomeWorker, workers_count: 1)

      spawn(fn ->
        Poolex.run(pool_name, fn pid ->
          GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)})
        end)
      end)

      :timer.sleep(10)

      waiting_caller =
        spawn(fn ->
          Poolex.run(
            pool_name,
            fn pid ->
              GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)})
            end,
            timeout: 100
          )
        end)

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)
      assert length(debug_info.waiting_callers) == 1

      assert Enum.find(debug_info.waiting_callers, fn {pid, _} ->
               pid == waiting_caller
             end)

      :timer.sleep(100)
      debug_info = Poolex.get_debug_info(pool_name)
      assert Enum.empty?(debug_info.waiting_callers)
    end

    test "run/3 returns :all_workers_are_busy on timeout", %{pool_name: pool_name} do
      Poolex.start_link(pool_name, worker_module: SomeWorker, workers_count: 1)

      spawn(fn ->
        Poolex.run(
          pool_name,
          fn pid -> GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)}) end
        )
      end)

      :timer.sleep(10)

      result =
        Poolex.run(
          pool_name,
          fn pid -> GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)}) end,
          timeout: 100
        )

      assert result == :all_workers_are_busy
    end

    test "run!/3 exits on timeout", %{pool_name: pool_name} do
      Poolex.start_link(pool_name, worker_module: SomeWorker, workers_count: 1)

      spawn(fn ->
        Poolex.run(
          pool_name,
          fn pid -> GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)}) end
        )
      end)

      :timer.sleep(10)

      assert catch_exit(
               Poolex.run!(
                 pool_name,
                 fn pid -> GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)}) end,
                 timeout: 100
               )
             ) == {:timeout, {GenServer, :call, [pool_name, :get_idle_worker, 100]}}
    end
  end

  defp pool_name do
    1..10
    |> Enum.map(fn _ -> Enum.random(?a..?z) end)
    |> to_string()
    |> String.to_atom()
  end
end
