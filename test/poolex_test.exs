defmodule PoolexTest do
  use ExUnit.Case,
    parameterize: [
      %{pool_options: [worker_module: SomeWorker, workers_count: 5]},
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

  alias Poolex.Private.BusyWorkers
  alias Poolex.Private.DebugInfo
  alias Poolex.Private.IdleOverflowedWorkers
  alias Poolex.Private.Options.Parser, as: OptionsParser

  setup_all do
    if Version.match?(System.version(), ">= 1.18.0") do
      []
    else
      [pool_options: [pool_id: SomeWorker, worker_module: SomeWorker, workers_count: 5]]
    end
  end

  doctest Poolex

  describe "debug info" do
    test "valid after initialization", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.__struct__ == DebugInfo
      assert debug_info.busy_workers_count == 0
      assert debug_info.busy_workers_impl == Poolex.Workers.Impl.List
      assert debug_info.busy_workers_pids == []
      assert debug_info.idle_workers_count == 5
      assert debug_info.idle_workers_impl == Poolex.Workers.Impl.List
      assert debug_info.idle_overflowed_workers_count == 0
      assert debug_info.idle_overflowed_workers_impl == Poolex.Workers.Impl.List
      assert debug_info.idle_overflowed_workers_pids == []
      assert debug_info.max_overflow == 0
      assert Enum.count(debug_info.idle_workers_pids) == 5
      assert debug_info.worker_module == SomeWorker
      assert debug_info.worker_args == []
      assert debug_info.worker_shutdown_delay == 0
      assert debug_info.waiting_callers == []
      assert debug_info.waiting_callers_impl == Poolex.Callers.Impl.ErlangQueue
    end

    test "valid configured implementations", %{pool_options: pool_options} do
      pool_name =
        pool_options
        |> Keyword.merge(
          busy_workers_impl: SomeBusyWorkersImpl,
          idle_overflowed_workers_impl: SomeIdleOverflowedWorkersImpl,
          idle_workers_impl: SomeIdleWorkersImpl,
          waiting_callers_impl: SomeWaitingCallersImpl
        )
        |> start_pool()

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.busy_workers_impl == SomeBusyWorkersImpl
      assert debug_info.idle_overflowed_workers_impl == SomeIdleOverflowedWorkersImpl
      assert debug_info.idle_workers_impl == SomeIdleWorkersImpl
      assert debug_info.waiting_callers_impl == SomeWaitingCallersImpl
    end

    test "valid configured shutdown_delay", %{pool_options: pool_options} do
      shutdown_delay = 1000

      pool_name =
        pool_options
        |> Keyword.put(:worker_shutdown_delay, shutdown_delay)
        |> start_pool()

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.worker_shutdown_delay == shutdown_delay
    end

    test "valid after using the worker", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      assert {:ok, :some_result} = Poolex.run(pool_name, fn pid -> GenServer.call(pid, :do_some_work) end)

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.__struct__ == DebugInfo
      assert debug_info.busy_workers_count == 0
      assert Enum.empty?(debug_info.busy_workers_pids)
      assert debug_info.idle_workers_count == 5
      assert Enum.count(debug_info.idle_workers_pids) == 5
      assert debug_info.worker_module == SomeWorker
      assert debug_info.worker_args == []
      assert debug_info.waiting_callers == []
    end

    test "valid after holding some workers", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      test_process = self()

      spawn(fn ->
        Poolex.run(pool_name, fn _pid ->
          Process.send(test_process, nil, [])
          :timer.sleep(to_timeout(second: 5))
        end)
      end)

      receive do
        _message -> nil
      end

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.__struct__ == DebugInfo
      assert debug_info.busy_workers_count == 1
      assert Enum.count(debug_info.busy_workers_pids) == 1
      assert debug_info.idle_workers_count == 4
      assert Enum.count(debug_info.idle_workers_pids) == 4
      assert debug_info.worker_module == SomeWorker
      assert debug_info.worker_args == []
      assert debug_info.waiting_callers == []
    end
  end

  describe "run/2" do
    test "updates agent's state", %{pool_options: pool_options} do
      pool_name =
        pool_options
        |> Keyword.merge(worker_module: Agent, worker_args: [fn -> 0 end], workers_count: 1)
        |> start_pool()

      Poolex.run(pool_name, fn pid -> Agent.update(pid, fn _state -> 1 end) end)

      [agent_pid] = DebugInfo.get_debug_info(pool_name).idle_workers_pids

      assert 1 == Agent.get(agent_pid, fn state -> state end)
    end

    test "get result from custom worker", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      result = Poolex.run(pool_name, fn pid -> GenServer.call(pid, :do_some_work) end)
      assert result == {:ok, :some_result}
    end

    test "test waiting queue", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

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
    @describetag capture_log: true
    test "works on idle workers", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      [some_worker_pid] = DebugInfo.get_debug_info(pool_name).idle_workers_pids

      Process.exit(some_worker_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      [new_worker_pid] = DebugInfo.get_debug_info(pool_name).idle_workers_pids

      assert some_worker_pid != new_worker_pid
    end

    test "works on busy workers", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      test_process = self()

      spawn(fn ->
        Poolex.run(pool_name, fn _pid ->
          Process.send(test_process, nil, [])
          :timer.sleep(to_timeout(second: 5))
        end)
      end)

      receive do
        _message -> nil
      end

      [some_worker_pid] = DebugInfo.get_debug_info(pool_name).busy_workers_pids

      Process.exit(some_worker_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      [new_worker_pid] = DebugInfo.get_debug_info(pool_name).idle_workers_pids

      assert some_worker_pid != new_worker_pid
    end

    test "restart busy workers when pending callers", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      launch_long_tasks(pool_name, 2)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.busy_workers_count == 1
      assert length(debug_info.waiting_callers) == 1

      [busy_worker_pid] = debug_info.busy_workers_pids
      Process.exit(busy_worker_pid, :kill)

      # To be sure that DOWN message will be handed
      :timer.sleep(1)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.busy_workers_count == 1
      assert Enum.empty?(debug_info.waiting_callers)

      [new_worker_pid] = debug_info.busy_workers_pids

      assert busy_worker_pid != new_worker_pid
    end

    test "works on callers", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      Enum.each(1..10, fn _ ->
        spawn(fn ->
          Poolex.run(pool_name, fn pid -> GenServer.call(pid, {:do_some_work_with_delay, to_timeout(second: 4)}) end)
        end)
      end)

      waiting_caller =
        spawn(fn ->
          Poolex.run(pool_name, fn pid ->
            GenServer.call(pid, {:do_some_work_with_delay, to_timeout(second: 3)})
          end)
        end)

      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert length(debug_info.waiting_callers) == 10

      assert Enum.find(debug_info.waiting_callers, fn %Poolex.Caller{from: {pid, _tag}} ->
               pid == waiting_caller
             end)

      Process.exit(waiting_caller, :kill)
      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert length(debug_info.waiting_callers) == 9

      refute Enum.find(debug_info.waiting_callers, fn %Poolex.Caller{from: {pid, _tag}} ->
               pid == waiting_caller
             end)
    end

    test "release busy worker when caller dies", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 2) |> start_pool()

      caller =
        spawn(fn ->
          Poolex.run(pool_name, fn pid ->
            GenServer.call(pid, {:do_some_work_with_delay, to_timeout(second: 4)})
          end)
        end)

      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 1

      [busy_worker_pid] = debug_info.busy_workers_pids

      Process.exit(caller, :kill)

      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_count == 2

      # Busy worker should be restarted if caller dies
      # NOTE: may be I should write a test using :do_some_work_with_delay
      refute Enum.any?(debug_info.idle_workers_pids, fn pid ->
               pid == busy_worker_pid
             end)
    end

    test "release busy worker when caller dies (overflow case)", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.merge(workers_count: 0, max_overflow: 2) |> start_pool()

      caller =
        spawn(fn ->
          Poolex.run(pool_name, fn pid ->
            GenServer.call(pid, {:do_some_work_with_delay, to_timeout(second: 4)})
          end)
        end)

      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0

      Process.exit(caller, :kill)

      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_count == 0
    end

    test "runtime errors", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      catch_exit(Poolex.run(pool_name, fn pid -> GenServer.call(pid, :do_raise) end))

      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_count == 1
      assert debug_info.idle_workers_pids |> hd() |> Process.alive?()
    end
  end

  describe "timeouts" do
    test "when caller waits too long", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      launch_long_task(pool_name)

      waiting_caller =
        spawn(fn ->
          Poolex.run(
            pool_name,
            fn pid ->
              GenServer.call(pid, {:do_some_work_with_delay, to_timeout(second: 4)})
            end,
            checkout_timeout: 100
          )
        end)

      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert length(debug_info.waiting_callers) == 1

      assert Enum.find(debug_info.waiting_callers, fn %Poolex.Caller{from: {pid, _tag}} ->
               pid == waiting_caller
             end)

      :timer.sleep(100)
      debug_info = DebugInfo.get_debug_info(pool_name)
      assert Enum.empty?(debug_info.waiting_callers)
      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0
    end

    test "run/3 returns error on checkout timeout", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      launch_long_task(pool_name)

      result =
        Poolex.run(
          pool_name,
          fn pid -> GenServer.call(pid, {:do_some_work_with_delay, to_timeout(second: 4)}) end,
          checkout_timeout: 100
        )

      assert result == {:error, :checkout_timeout}

      :timer.sleep(10)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert Enum.empty?(debug_info.waiting_callers)
      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0
    end

    test "handle worker's timeout", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

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

    test "worker not hangs in busy status after checkout timeout", %{pool_options: pool_options} do
      test_pid = self()

      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

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
      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_pids == [worker]

      send(process_2, :finish)
      assert_receive {:DOWN, ^reference_2, :process, ^process_2, _}
    end
  end

  describe "overflow" do
    test "create new workers when possible", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.merge(workers_count: 1, max_overflow: 5) |> start_pool()

      launch_long_tasks(pool_name, 5)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.max_overflow == 5
      assert debug_info.busy_workers_count == 5
      assert debug_info.overflow == 4
    end

    test "return error when max count of workers reached", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      launch_long_task(pool_name)

      result =
        Poolex.run(
          pool_name,
          fn pid -> GenServer.call(pid, {:do_some_work_with_delay, to_timeout(second: 4)}) end,
          checkout_timeout: 100
        )

      assert result == {:error, :checkout_timeout}

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 1
      assert debug_info.max_overflow == 0
      assert debug_info.overflow == 0
    end

    test "all workers running over the limit are turned off after use", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.merge(workers_count: 1, max_overflow: 2) |> start_pool()

      launch_long_task(pool_name)

      spawn(fn -> Poolex.run(pool_name, &is_pid/1) end)
      spawn(fn -> Poolex.run(pool_name, &is_pid/1) end)

      :timer.sleep(50)

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0
      assert debug_info.overflow == 0
    end

    test "allows workers_count: 0", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.merge(workers_count: 0, max_overflow: 2) |> start_pool()

      debug_info = DebugInfo.get_debug_info(pool_name)

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

      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.idle_workers_count == 0
      assert debug_info.idle_workers_pids == []
      assert debug_info.busy_workers_count == 1
      assert debug_info.busy_workers_pids == [worker_pid]
      assert debug_info.overflow == 1

      assert_receive {:traceable_end, :foo, ^worker_pid}
      debug_info = DebugInfo.get_debug_info(pool_name)

      assert debug_info.idle_workers_count == 0
      assert debug_info.idle_workers_pids == []
      assert debug_info.busy_workers_count == 0
      assert debug_info.busy_workers_pids == []
      assert debug_info.overflow == 0
    end
  end

  describe "child_spec" do
    test "child_spec/1", %{pool_options: pool_options} do
      id = OptionsParser.parse_pool_id(pool_options)

      assert Poolex.child_spec(pool_options) ==
               %{
                 id: id,
                 start: {Poolex, :start_link, [pool_options]}
               }

      assert Poolex.child_spec(worker_module: SomeWorker, workers_count: 5) ==
               %{
                 id: SomeWorker,
                 start: {Poolex, :start_link, [[worker_module: SomeWorker, workers_count: 5]]}
               }
    end
  end

  describe "terminate process" do
    @describetag capture_log: true
    test "workers stop before the pool with reason :normal", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      pool_pid = GenServer.whereis(pool_name)

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

    test "workers stop before the pool with reason :exit", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 1) |> start_pool()

      pool_pid = GenServer.whereis(pool_name)

      state = :sys.get_state(pool_name)

      supervisor_pid = state.supervisor
      {:ok, worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      pool_monitor_ref = Process.monitor(pool_pid)
      supervisor_monitor_ref = Process.monitor(supervisor_pid)
      worker_monitor_ref = Process.monitor(worker_pid)

      Process.exit(pool_pid, :exit)

      :timer.sleep(30)

      assert {:messages, [message_1, message_2, message_3]} = Process.info(self(), :messages)

      assert elem(message_1, 0) == :DOWN
      assert elem(message_1, 1) == worker_monitor_ref
      assert elem(message_1, 2) == :process
      assert elem(message_1, 3) == worker_pid
      assert elem(message_1, 4) == :shutdown

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
    test "adds idle workers to pool", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      assert %DebugInfo{idle_workers_count: 5} = DebugInfo.get_debug_info(pool_name)
      assert :ok = Poolex.add_idle_workers!(pool_name, 5)
      assert %DebugInfo{idle_workers_count: 10} = DebugInfo.get_debug_info(pool_name)
    end

    test "provides new workers to waiting callers", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 0) |> start_pool()

      test_process = self()

      spawn(fn ->
        Process.send(test_process, nil, [])

        Poolex.run(pool_name, fn _pid ->
          Process.send(test_process, :started_work, [])
          :timer.sleep(to_timeout(second: 5))
        end)
      end)

      receive do
        _message -> nil
      end

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.busy_workers_count == 0
      assert debug_info.idle_workers_count == 0
      assert Enum.count(debug_info.waiting_callers) == 1
      refute_received :started_work

      assert :ok = Poolex.add_idle_workers!(pool_name, 1)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.busy_workers_count == 1
      assert debug_info.idle_workers_count == 0
      assert Enum.empty?(debug_info.waiting_callers)
      assert_receive :started_work, 1000
    end

    test "raises error on non positive workers_count", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      assert_raise(ArgumentError, fn ->
        Poolex.add_idle_workers!(pool_name, -1)
      end)

      assert_raise(ArgumentError, fn ->
        Poolex.add_idle_workers!(pool_name, 0)
      end)
    end
  end

  describe "remove_idle_workers!/2" do
    test "removes idle workers from pool", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      assert %DebugInfo{idle_workers_count: 5} = DebugInfo.get_debug_info(pool_name)
      assert :ok = Poolex.remove_idle_workers!(pool_name, 2)
      assert %DebugInfo{idle_workers_count: 3} = DebugInfo.get_debug_info(pool_name)
    end

    test "removes all idle workers when argument is bigger than idle_workers count", %{pool_options: pool_options} do
      pool_name = pool_options |> Keyword.put(:workers_count, 3) |> start_pool()

      assert %DebugInfo{idle_workers_count: 3} = DebugInfo.get_debug_info(pool_name)
      assert :ok = Poolex.remove_idle_workers!(pool_name, 5)
      assert %DebugInfo{idle_workers_count: 0} = DebugInfo.get_debug_info(pool_name)
    end

    test "raises error on non positive workers_count", %{pool_options: pool_options} do
      pool_name = start_pool(pool_options)

      assert_raise(ArgumentError, fn ->
        Poolex.remove_idle_workers!(pool_name, -1)
      end)

      assert_raise(ArgumentError, fn ->
        Poolex.remove_idle_workers!(pool_name, 0)
      end)
    end
  end

  describe "handle errors on workers launch" do
    @describetag capture_log: true
    test "while starting the pool", %{pool_options: pool_options} do
      {:ok, control_agent} = Agent.start_link(fn -> 3 end)

      pool_name =
        pool_options
        |> Keyword.merge(
          worker_module: SomeUnstableWorker,
          worker_args: [[control_agent: control_agent]],
          failed_workers_retry_interval: 100
        )
        |> start_pool()

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.failed_to_start_workers_count == 2
      assert debug_info.idle_workers_count == 3

      # Increase the agent value to allow the remaining workers to start
      Agent.update(control_agent, fn _ -> 2 end)

      :timer.sleep(150)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.failed_to_start_workers_count == 0
      assert debug_info.idle_workers_count == 5
    end
  end

  describe "overflow worker shutdown delay" do
    test "overflowed worker is terminated with delay", %{pool_options: pool_options} do
      shutdown_delay = 200

      pool_name =
        pool_options
        |> Keyword.merge(workers_count: 1, max_overflow: 1, worker_shutdown_delay: shutdown_delay)
        |> start_pool()

      # Launch a long task to occupy the worker
      launch_long_task(pool_name)

      # Launch another task to trigger overflow
      {:ok, overflowed_worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      # Ensure the overflowed worker is alive
      assert Process.alive?(overflowed_worker_pid)

      # Check that the overflowed worker is not in the busy workers list
      state = :sys.get_state(pool_name)
      refute BusyWorkers.member?(state, overflowed_worker_pid)

      # Wait for the shutdown delay
      :timer.sleep(shutdown_delay + 50)

      # Check that the overflowed worker is no longer alive
      refute Process.alive?(overflowed_worker_pid)
    end

    test "overflowed worker is not terminated if used again", %{pool_options: pool_options} do
      shutdown_delay = 200

      pool_name =
        pool_options
        |> Keyword.merge(workers_count: 1, max_overflow: 1, worker_shutdown_delay: shutdown_delay)
        |> start_pool()

      # Launch a long task to occupy the worker
      launch_long_task(pool_name)

      # Launch another task to trigger overflow
      {:ok, overflowed_worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      # Ensure the overflowed worker is alive
      assert Process.alive?(overflowed_worker_pid)

      # Check that the overflowed worker is not in the busy workers list
      # And check that it is in the idle overflowed workers list
      state = :sys.get_state(pool_name)
      refute BusyWorkers.member?(state, overflowed_worker_pid)
      assert IdleOverflowedWorkers.member?(state, overflowed_worker_pid)

      # Use the overflowed worker again before the shutdown delay
      launch_long_task(pool_name)

      # Wait for the shutdown delay
      :timer.sleep(shutdown_delay + 50)

      # Check that the overflowed worker is still alive
      assert Process.alive?(overflowed_worker_pid)
    end

    test "overflowed worker is terminated immediately if worker_shutdown_delay is 0", %{pool_options: pool_options} do
      pool_name =
        pool_options
        |> Keyword.merge(workers_count: 1, max_overflow: 1, worker_shutdown_delay: 0)
        |> start_pool()

      # Launch a long task to occupy the worker
      launch_long_task(pool_name)

      # Launch another task to trigger overflow
      {:ok, overflowed_worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      :timer.sleep(10)

      # Ensure the overflowed worker is alive
      refute Process.alive?(overflowed_worker_pid)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.idle_overflowed_workers_count == 0
      assert debug_info.idle_overflowed_workers_pids == []
    end

    test "overflowed workers terminates independently of each other", %{pool_options: pool_options} do
      shutdown_delay = 200

      pool_name =
        pool_options
        |> Keyword.merge(workers_count: 1, max_overflow: 2, worker_shutdown_delay: shutdown_delay)
        |> start_pool()

      # Launch a long task to occupy the worker
      launch_long_task(pool_name)

      # Launch first task to trigger overflow
      launch_long_task(pool_name, 100)

      # Wait a bit before launching the second overflowed worker
      :timer.sleep(50)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.idle_overflowed_workers_count == 0
      assert debug_info.busy_workers_count == 2
      assert debug_info.overflow == 1

      # Launch second task to trigger another overflow
      Poolex.run(pool_name, fn pid -> pid end)

      # Wait to ensure all messages are processed
      :timer.sleep(20)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.idle_overflowed_workers_count == 1
      assert debug_info.busy_workers_count == 2
      assert debug_info.overflow == 2

      # Wait until first overflowed worker is released
      :timer.sleep(50)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.idle_overflowed_workers_count == 2
      assert debug_info.busy_workers_count == 1
      assert debug_info.overflow == 2

      # Wait for the first overflowed worker shutdown delay
      :timer.sleep(150)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.idle_overflowed_workers_count == 1
      assert debug_info.busy_workers_count == 1
      assert debug_info.overflow == 1

      # Wait for the second overflowed worker shutdown delay
      :timer.sleep(100)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.idle_overflowed_workers_count == 0
      assert debug_info.busy_workers_count == 1
      assert debug_info.overflow == 0
    end

    test "overflowed worker can be released many times without errors", %{pool_options: pool_options} do
      shutdown_delay = 100

      pool_name =
        pool_options
        |> Keyword.merge(workers_count: 1, max_overflow: 2, worker_shutdown_delay: shutdown_delay)
        |> start_pool()

      # Launch a long task to occupy the worker
      launch_long_task(pool_name)

      # Launch first task to trigger overflow
      {:ok, overflowed_worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      # Ensure the overflowed worker is alive
      assert Process.alive?(overflowed_worker_pid)

      # Wait a bit before using the overflowed worker again
      :timer.sleep(50)

      # Use the overflowed worker again
      assert {:ok, ^overflowed_worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      # Wait a bit ont more time before using the overflowed worker again
      :timer.sleep(50)

      # Use the overflowed worker again
      assert {:ok, ^overflowed_worker_pid} = Poolex.run(pool_name, fn pid -> pid end)

      # Wait a bit again before checking the overflowed worker
      :timer.sleep(50)

      # Check that the overflowed worker is still alive
      assert Process.alive?(overflowed_worker_pid)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.idle_overflowed_workers_count == 1
      assert debug_info.idle_overflowed_workers_pids == [overflowed_worker_pid]
      assert debug_info.busy_workers_count == 1
      assert debug_info.overflow == 1
      assert debug_info.max_overflow == 2

      # Wait for the shutdown delay
      :timer.sleep(shutdown_delay + 50)

      # Check that the overflowed worker is no longer alive
      refute Process.alive?(overflowed_worker_pid)

      debug_info = DebugInfo.get_debug_info(pool_name)
      assert debug_info.idle_overflowed_workers_count == 0
      assert debug_info.idle_overflowed_workers_pids == []
      assert debug_info.busy_workers_count == 1
      assert debug_info.overflow == 0
      assert debug_info.max_overflow == 2
    end
  end
end
