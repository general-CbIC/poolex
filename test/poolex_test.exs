defmodule PoolexTest do
  use ExUnit.Case,
    parameterize: [
      %{pool_options: [pool_id: SomeWorker, worker_module: SomeWorker, workers_count: 5]},
      %{pool_options: [pool_id: {:global, SomeWorker}, worker_module: SomeWorker, workers_count: 5]},
      %{
        pool_options: [
          pool_id: {:via, Registry, {PoolexTestRegistry, "some_pool"}},
          worker_module: SomeWorker,
          workers_count: 5
        ]
      }
    ]

  import PoolHelpers

  alias Poolex.Private.DebugInfo

  doctest Poolex

  describe "debug info" do
    test "valid after initialization", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.__struct__ == DebugInfo
      assert debug_info.busy_workers_count == 0
      assert debug_info.busy_workers_impl == Poolex.Workers.Impl.List
      assert debug_info.busy_workers_pids == []
      assert debug_info.idle_workers_count == 5
      assert debug_info.idle_workers_impl == Poolex.Workers.Impl.List
      assert debug_info.max_overflow == 0
      assert Enum.count(debug_info.idle_workers_pids) == 5
      assert debug_info.worker_module == SomeWorker
      assert debug_info.worker_args == []
      assert debug_info.waiting_callers == []
      assert debug_info.waiting_callers_impl == Poolex.Callers.Impl.ErlangQueue
    end

    test "valid configured implementations", %{pool_options: pool_options} do
      pool_name =
        pool_options
        |> Keyword.merge(
          busy_workers_impl: SomeBusyWorkersImpl,
          idle_workers_impl: SomeIdleWorkersImpl,
          waiting_callers_impl: SomeWaitingCallersImpl
        )
        |> start_pool()

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_impl == SomeBusyWorkersImpl
      assert debug_info.idle_workers_impl == SomeIdleWorkersImpl
      assert debug_info.waiting_callers_impl == SomeWaitingCallersImpl
    end

    test "valid after using the worker" do
      initial_fun = fn -> 0 end
      pool_name = start_pool(worker_module: Agent, worker_args: [initial_fun], workers_count: 5)

      {:ok, 0} = Poolex.run(pool_name, fn pid -> Agent.get(pid, & &1) end)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.__struct__ == DebugInfo
      assert debug_info.busy_workers_count == 0
      assert Enum.empty?(debug_info.busy_workers_pids)
      assert debug_info.idle_workers_count == 5
      assert Enum.count(debug_info.idle_workers_pids) == 5
      assert debug_info.worker_module == Agent
      assert debug_info.worker_args == [initial_fun]
      assert debug_info.waiting_callers == []
    end

    test "valid after holding some workers" do
      initial_fun = fn -> 0 end
      pool_name = start_pool(worker_module: Agent, worker_args: [initial_fun], workers_count: 5)

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

      assert debug_info.__struct__ == DebugInfo
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
    test "updates agent's state" do
      pool_name = start_pool(worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 1)

      Poolex.run(pool_name, fn pid -> Agent.update(pid, fn _state -> 1 end) end)

      [agent_pid] = Poolex.get_debug_info(pool_name).idle_workers_pids

      assert 1 == Agent.get(agent_pid, fn state -> state end)
    end

    test "get result from custom worker" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 2)

      result = Poolex.run(pool_name, fn pid -> GenServer.call(pid, :do_some_work) end)
      assert result == {:ok, :some_result}
    end

    test "test waiting queue" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 5)

      result =
        1..20
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Poolex.run(pool_name, fn pid ->
              GenServer.call(pid, {:do_some_work_with_delay, 100})
            end)
          end)
        end)
        |> Enum.map(&Task.await/1)

      assert length(result) == 20
      assert Enum.all?(result, &(&1 == {:ok, :some_result}))
    end
  end

  describe "restarting terminated processes" do
    test "works on idle workers" do
      pool_name = start_pool(worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 1)

      [agent_pid] = Poolex.get_debug_info(pool_name).idle_workers_pids

      Process.exit(agent_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      [new_agent_pid] = Poolex.get_debug_info(pool_name).idle_workers_pids

      assert agent_pid != new_agent_pid
    end

    test "works on busy workers" do
      pool_name = start_pool(worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 1)

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

    test "restart busy workers when pending callers" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)

      # test_process = self()
      launch_long_tasks(pool_name, 2)

      debug_info = Poolex.get_debug_info(pool_name)
      assert debug_info.busy_workers_count == 1
      assert length(debug_info.waiting_callers) == 1

      [busy_worker_pid] = debug_info.busy_workers_pids
      Process.exit(busy_worker_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      debug_info = Poolex.get_debug_info(pool_name)
      assert debug_info.busy_workers_count == 1
      assert Enum.empty?(debug_info.waiting_callers)

      [new_worker_pid] = debug_info.busy_workers_pids

      assert busy_worker_pid != new_worker_pid
    end

    test "works on callers" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)

      Enum.each(1..10, fn _ ->
        spawn(fn ->
          Poolex.run(pool_name, fn pid -> GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)}) end)
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

      assert Enum.find(debug_info.waiting_callers, fn %Poolex.Caller{from: {pid, _tag}} ->
               pid == waiting_caller
             end)

      Process.exit(waiting_caller, :kill)
      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)
      assert length(debug_info.waiting_callers) == 9

      refute Enum.find(debug_info.waiting_callers, fn %Poolex.Caller{from: {pid, _tag}} ->
               pid == waiting_caller
             end)
    end

    test "release busy worker when caller dies" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 2)

      caller =
        spawn(fn ->
          Poolex.run(pool_name, fn pid ->
            GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)})
          end)
        end)

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 1

      Process.exit(caller, :kill)

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_count == 2
    end

    test "release busy worker when caller dies (overflow case)" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 0, max_overflow: 2)

      caller =
        spawn(fn ->
          Poolex.run(pool_name, fn pid ->
            GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)})
          end)
        end)

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0

      Process.exit(caller, :kill)

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_count == 0
    end

    test "runtime errors" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)

      catch_exit(Poolex.run(pool_name, fn pid -> GenServer.call(pid, :do_raise) end))

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_count == 1
      assert debug_info.idle_workers_pids |> hd() |> Process.alive?()
    end
  end

  describe "timeouts" do
    test "when caller waits too long" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)

      launch_long_task(pool_name)

      waiting_caller =
        spawn(fn ->
          Poolex.run(
            pool_name,
            fn pid ->
              GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)})
            end,
            checkout_timeout: 100
          )
        end)

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)
      assert length(debug_info.waiting_callers) == 1

      assert Enum.find(debug_info.waiting_callers, fn %Poolex.Caller{from: {pid, _tag}} ->
               pid == waiting_caller
             end)

      :timer.sleep(100)
      debug_info = Poolex.get_debug_info(pool_name)
      assert Enum.empty?(debug_info.waiting_callers)
      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0
    end

    test "run/3 returns error on checkout timeout" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)
      launch_long_task(pool_name)

      result =
        Poolex.run(
          pool_name,
          fn pid -> GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)}) end,
          checkout_timeout: 100
        )

      assert result == {:error, :checkout_timeout}

      :timer.sleep(10)

      debug_info = Poolex.get_debug_info(pool_name)
      assert Enum.empty?(debug_info.waiting_callers)
      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0
    end

    test "handle worker's timeout" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)
      delay = 100

      assert {:ok, :some_result} =
               Poolex.run(pool_name, fn pid ->
                 GenServer.call(pid, {:do_some_work_with_delay, delay}, 1000)
               end)

      assert {:timeout, {GenServer, :call, [_worker_pid, {:do_some_work_with_delay, 100}, 1]}} =
               catch_exit(
                 Poolex.run(pool_name, fn pid ->
                   GenServer.call(pid, {:do_some_work_with_delay, delay}, 1)
                 end)
               )
    end

    test "worker not hangs in busy status after checkout timeout" do
      test_pid = self()
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)
      delay = 100

      process_1 =
        spawn(fn ->
          assert {:ok, :some_result} =
                   Poolex.run(pool_name, fn pid ->
                     send(test_pid, {:worker, pid})
                     GenServer.call(pid, {:do_some_work_with_delay, delay})
                   end)
        end)

      reference_1 = Process.monitor(process_1)

      process_2 =
        spawn(fn ->
          assert {:error, :checkout_timeout} =
                   Poolex.run(
                     pool_name,
                     fn pid ->
                       GenServer.call(pid, {:do_some_work_with_delay, delay})
                     end,
                     checkout_timeout: 0
                   )

          send(test_pid, {:waiting, self()})

          receive do
            :finish -> :ok
          end
        end)

      reference_2 = Process.monitor(process_2)

      assert_receive {:worker, worker}, 1000
      assert_receive {:waiting, ^process_2}, 1000
      assert_receive {:DOWN, ^reference_1, :process, ^process_1, _}, 1000
      refute_received _

      Process.sleep(100)
      debug_info = Poolex.get_debug_info(pool_name)
      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_pids == [worker]

      send(process_2, :finish)
      assert_receive {:DOWN, ^reference_2, :process, ^process_2, _}
    end
  end

  describe "overflow" do
    test "create new workers when possible" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1, max_overflow: 5)

      launch_long_tasks(pool_name, 5)

      debug_info = Poolex.get_debug_info(pool_name)
      assert debug_info.max_overflow == 5
      assert debug_info.busy_workers_count == 5
      assert debug_info.overflow == 4
    end

    test "return error when max count of workers reached" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)
      launch_long_task(pool_name)

      result =
        Poolex.run(
          pool_name,
          fn pid -> GenServer.call(pid, {:do_some_work_with_delay, :timer.seconds(4)}) end,
          checkout_timeout: 100
        )

      assert result == {:error, :checkout_timeout}

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 1
      assert debug_info.max_overflow == 0
      assert debug_info.overflow == 0
    end

    test "all workers running over the limit are turned off after use" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1, max_overflow: 2)

      launch_long_task(pool_name)

      spawn(fn -> Poolex.run(pool_name, &is_pid/1) end)
      spawn(fn -> Poolex.run(pool_name, &is_pid/1) end)

      :timer.sleep(50)

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0
      assert debug_info.overflow == 0
    end

    test "allows workers_count: 0" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 0, max_overflow: 2)
      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.idle_workers_count == 0
      assert debug_info.idle_workers_pids == []
      assert debug_info.busy_workers_count == 0
      assert debug_info.busy_workers_pids == []
      assert debug_info.overflow == 0

      pid = self()

      spawn(fn ->
        Poolex.run(pool_name, fn server ->
          SomeWorker.traceable_call(server, pid, :foo, 50)
        end)
      end)

      assert_receive {:traceable_start, :foo, worker_pid}
      refute_received {:traceable_end, _, _}

      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.idle_workers_count == 0
      assert debug_info.idle_workers_pids == []
      assert debug_info.busy_workers_count == 1
      assert debug_info.busy_workers_pids == [worker_pid]
      assert debug_info.overflow == 1

      assert_receive {:traceable_end, :foo, ^worker_pid}
      debug_info = Poolex.get_debug_info(pool_name)

      assert debug_info.idle_workers_count == 0
      assert debug_info.idle_workers_pids == []
      assert debug_info.busy_workers_count == 0
      assert debug_info.busy_workers_pids == []
      assert debug_info.overflow == 0
    end
  end

  describe "child_spec" do
    test "child_spec/1" do
      assert Poolex.child_spec(pool_id: :test_pool, worker_module: SomeWorker, workers_count: 5) ==
               %{
                 id: :test_pool,
                 start: {Poolex, :start_link, [[pool_id: :test_pool, worker_module: SomeWorker, workers_count: 5]]}
               }

      assert Poolex.child_spec(pool_id: {:global, :biba}, worker_module: SomeWorker, workers_count: 10) ==
               %{
                 id: {:global, :biba},
                 start: {Poolex, :start_link, [[pool_id: {:global, :biba}, worker_module: SomeWorker, workers_count: 10]]}
               }
    end
  end

  describe "terminate process" do
    test "workers stop before the pool with reason :normal" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)
      pool_pid = Process.whereis(pool_name)

      state = :sys.get_state(pool_name)

      supervisor_pid = state.supervisor
      {:ok, worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      pool_monitor_ref = Process.monitor(pool_pid)
      supervisor_monitor_ref = Process.monitor(supervisor_pid)
      worker_monitor_ref = Process.monitor(worker_pid)

      GenServer.stop(pool_name)

      {:messages, [message_1, message_2, message_3]} = Process.info(self(), :messages)

      assert message_1 == {:DOWN, worker_monitor_ref, :process, worker_pid, :shutdown}
      assert message_2 == {:DOWN, supervisor_monitor_ref, :process, supervisor_pid, :normal}
      assert message_3 == {:DOWN, pool_monitor_ref, :process, pool_pid, :normal}
    end

    test "workers stop before the pool with reason :exit" do
      pool_name = start_pool(worker_module: SomeWorker, workers_count: 1)
      pool_pid = Process.whereis(pool_name)

      state = :sys.get_state(pool_name)

      supervisor_pid = state.supervisor
      {:ok, worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      pool_monitor_ref = Process.monitor(pool_pid)
      supervisor_monitor_ref = Process.monitor(supervisor_pid)
      worker_monitor_ref = Process.monitor(worker_pid)

      Process.exit(pool_pid, :exit)
      :timer.sleep(20)

      {:messages, [message_1, message_2, message_3]} = Process.info(self(), :messages)

      assert message_1 == {:DOWN, worker_monitor_ref, :process, worker_pid, :shutdown}

      assert elem(message_2, 0) == :DOWN
      assert elem(message_2, 1) == supervisor_monitor_ref
      assert elem(message_2, 2) == :process
      assert elem(message_2, 3) == supervisor_pid

      assert elem(message_3, 0) == :DOWN
      assert elem(message_3, 1) == pool_monitor_ref
      assert elem(message_3, 2) == :process
      assert elem(message_3, 3) == pool_pid
    end
  end

  describe "add_idle_workers!/2" do
    test "adds idle workers to pool" do
      initial_fun = fn -> 0 end

      pool_name = start_pool(worker_module: Agent, worker_args: [initial_fun], workers_count: 5)

      assert %DebugInfo{idle_workers_count: 5} = Poolex.get_debug_info(pool_name)
      assert :ok = Poolex.add_idle_workers!(pool_name, 5)
      assert %DebugInfo{idle_workers_count: 10} = Poolex.get_debug_info(pool_name)
    end

    test "raises error on non positive workers_count" do
      initial_fun = fn -> 0 end

      pool_name = start_pool(worker_module: Agent, worker_args: [initial_fun], workers_count: 5)

      assert_raise(ArgumentError, fn ->
        Poolex.add_idle_workers!(pool_name, -1)
      end)

      assert_raise(ArgumentError, fn ->
        Poolex.add_idle_workers!(pool_name, 0)
      end)
    end
  end

  describe "remove_idle_workers!/2" do
    test "removes idle workers from pool" do
      initial_fun = fn -> 0 end

      pool_name = start_pool(worker_module: Agent, worker_args: [initial_fun], workers_count: 5)

      assert %DebugInfo{idle_workers_count: 5} = Poolex.get_debug_info(pool_name)
      assert :ok = Poolex.remove_idle_workers!(pool_name, 2)
      assert %DebugInfo{idle_workers_count: 3} = Poolex.get_debug_info(pool_name)
    end

    test "removes all idle workers when argument is bigger than idle_workers count" do
      initial_fun = fn -> 0 end

      pool_name = start_pool(worker_module: Agent, worker_args: [initial_fun], workers_count: 3)

      assert %DebugInfo{idle_workers_count: 3} = Poolex.get_debug_info(pool_name)
      assert :ok = Poolex.remove_idle_workers!(pool_name, 5)
      assert %DebugInfo{idle_workers_count: 0} = Poolex.get_debug_info(pool_name)
    end

    test "raises error on non positive workers_count" do
      initial_fun = fn -> 0 end

      pool_name = start_pool(worker_module: Agent, worker_args: [initial_fun], workers_count: 5)

      assert_raise(ArgumentError, fn ->
        Poolex.remove_idle_workers!(pool_name, -1)
      end)

      assert_raise(ArgumentError, fn ->
        Poolex.remove_idle_workers!(pool_name, 0)
      end)
    end
  end

  describe "using GenServer.name() naming" do
    test "works with {:global, term()}" do
      ExUnit.Callbacks.start_supervised(
        {Poolex,
         [
           pool_id: {:global, :biba},
           worker_module: SomeWorker,
           workers_count: 5
         ]}
      )

      state = :sys.get_state({:global, :biba})

      assert state.pool_id == {:global, :biba}

      assert {:ok, true} == Poolex.run({:global, :biba}, &is_pid/1)
    end

    test "works with Registry" do
      ExUnit.Callbacks.start_supervised({Registry, [keys: :unique, name: TestRegistry]})
      name = {:via, Registry, {TestRegistry, "pool"}}

      ExUnit.Callbacks.start_supervised({Poolex, [pool_id: name, worker_module: SomeWorker, workers_count: 5]})

      state = :sys.get_state(name)

      assert state.pool_id == name

      assert {:ok, true} == Poolex.run(name, &is_pid/1)
    end
  end
end
