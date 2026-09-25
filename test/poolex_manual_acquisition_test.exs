defmodule PoolexManualAcquisitionTest do
  @moduledoc """
  Proof-of-concept tests for manual worker acquisition infrastructure.
  Tests internal GenServer handlers before exposing public API.
  """
  use ExUnit.Case

  import PoolHelpers

  alias Poolex.Private.BusyWorkers
  alias Poolex.Private.IdleWorkers
  alias Poolex.Private.WaitingCallers

  describe "register_manual_acquisition" do
    test "creates monitor and registers in state" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 2)

      # Get a worker manually (simulating future acquire/2)
      assert {:ok, worker_pid} =
               GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)

      # Register manual acquisition atomically
      assert :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

      # Verify monitor process exists in state
      state = :sys.get_state(pool_id)
      assert is_map(state.manual_monitors)
      assert Map.has_key?(state.manual_monitors, worker_pid)
      {caller_pid, monitor_pid} = state.manual_monitors[worker_pid]
      assert caller_pid == self()
      assert is_pid(monitor_pid)
      assert Process.alive?(monitor_pid)

      # Verify worker is busy
      assert BusyWorkers.member?(state, worker_pid)
      refute IdleWorkers.member?(state, worker_pid)

      # Clean up
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})
    end

    test "allows multiple workers per caller" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 3)

      # Acquire two workers
      {:ok, worker1} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
      {:ok, worker2} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)

      # Register both
      :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker1})
      :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker2})

      # Verify both registered
      state = :sys.get_state(pool_id)
      assert map_size(state.manual_monitors) == 2
      assert Map.has_key?(state.manual_monitors, worker1)
      assert Map.has_key?(state.manual_monitors, worker2)

      # Clean up
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker1})
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker2})
    end
  end

  describe "release_manual_worker - auto kill on caller crash" do
    test "worker killed and restarted when caller crashes" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 2)

      # Spawn process that acquires worker and crashes
      test_pid = self()

      crashed_caller =
        spawn(fn ->
          {:ok, worker_pid} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
          :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

          # Send worker pid to test process
          send(test_pid, {:worker_acquired, worker_pid})

          # Wait for crash signal
          receive do
            :crash -> exit(:boom)
          end
        end)

      # Wait for worker acquisition
      assert_receive {:worker_acquired, worker_pid}, 1_000

      # Verify worker is busy and monitored
      state_before = :sys.get_state(pool_id)
      assert BusyWorkers.member?(state_before, worker_pid)
      assert Map.has_key?(state_before.manual_monitors, worker_pid)

      # Crash the caller
      send(crashed_caller, :crash)

      # Verify worker was killed (restarted, not the same PID)
      eventually(fn ->
        state_after = :sys.get_state(pool_id)
        refute BusyWorkers.member?(state_after, worker_pid)
        refute IdleWorkers.member?(state_after, worker_pid)
        refute Map.has_key?(state_after.manual_monitors, worker_pid)

        # A new worker should have been started to replace it
        assert IdleWorkers.count(state_after) == 2
      end)
    end

    test "monitor process dies after releasing worker" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 2)

      # Acquire and register
      {:ok, worker_pid} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
      :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

      # Get monitor pid
      state = :sys.get_state(pool_id)
      {_caller_pid, monitor_pid} = state.manual_monitors[worker_pid]
      assert Process.alive?(monitor_pid)

      # Release worker
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})

      # Verify monitor process killed
      eventually(fn -> refute Process.alive?(monitor_pid) end)

      # Verify removed from state
      state_after = :sys.get_state(pool_id)
      refute Map.has_key?(state_after.manual_monitors, worker_pid)
    end
  end

  describe "release_manual_worker - explicit release" do
    test "worker returned to idle pool" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 2)

      # Acquire worker
      {:ok, worker_pid} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
      :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

      # Verify busy
      state_before = :sys.get_state(pool_id)
      assert BusyWorkers.member?(state_before, worker_pid)
      assert BusyWorkers.count(state_before) == 1
      assert IdleWorkers.count(state_before) == 1

      # Release explicitly
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})

      # Verify returned to idle
      state_after = :sys.get_state(pool_id)
      refute BusyWorkers.member?(state_after, worker_pid)
      assert IdleWorkers.member?(state_after, worker_pid)
      assert BusyWorkers.count(state_after) == 0
      assert IdleWorkers.count(state_after) == 2
    end

    test "release non-existent worker is graceful" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 2)

      fake_worker_pid = spawn(fn -> :ok end)

      # Should not crash
      GenServer.cast(pool_id, {:release_manual_worker, self(), fake_worker_pid})

      # Pool should still be operational
      assert {:ok, _worker} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
    end

    test "double release is safe - second release is ignored" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 2)

      # Acquire worker
      {:ok, worker_pid} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
      :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

      # Release once
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})

      # Verify worker returned to idle
      state_after_first = :sys.get_state(pool_id)
      assert IdleWorkers.count(state_after_first) == 2
      assert BusyWorkers.count(state_after_first) == 0

      # Release again (should be ignored)
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})

      # State should not change
      state_after_second = :sys.get_state(pool_id)
      assert IdleWorkers.count(state_after_second) == 2
      assert BusyWorkers.count(state_after_second) == 0
    end

    test "release from wrong caller is ignored" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 2)

      # Acquire worker from this process
      {:ok, worker_pid} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
      :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

      # Verify worker is busy
      state_before = :sys.get_state(pool_id)
      assert BusyWorkers.member?(state_before, worker_pid)
      assert Map.has_key?(state_before.manual_monitors, worker_pid)

      # Try to release from a different process (should be ignored)
      other_pid = spawn(fn -> :timer.sleep(1000) end)
      GenServer.cast(pool_id, {:release_manual_worker, other_pid, worker_pid})

      # Worker should still be busy
      state_after = :sys.get_state(pool_id)
      assert BusyWorkers.member?(state_after, worker_pid)
      assert Map.has_key?(state_after.manual_monitors, worker_pid)

      # Clean up - release from correct caller
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})
    end

    test "worker provided to waiting caller instead of idle pool" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 1)

      # Acquire the only worker
      {:ok, worker_pid} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
      :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

      # Spawn waiting caller
      test_pid = self()

      _waiting_caller =
        spawn(fn ->
          result = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
          send(test_pid, {:got_worker, result})
        end)

      # Verify caller is waiting
      eventually(fn -> assert length(WaitingCallers.to_list(:sys.get_state(pool_id))) == 1 end)

      # Release worker
      GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})

      # Verify waiting caller received the worker
      assert_receive {:got_worker, {:ok, ^worker_pid}}, 1_000

      # Verify no waiting callers
      state_after = :sys.get_state(pool_id)
      assert WaitingCallers.empty?(state_after)
    end
  end

  describe "race condition stress test" do
    test "no worker leaks when many callers crash immediately after acquiring" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 5)

      # Initial state
      state_initial = :sys.get_state(pool_id)
      initial_idle_count = IdleWorkers.count(state_initial)
      assert initial_idle_count == 5

      # Spawn 100 processes that acquire and crash immediately
      callers =
        for _i <- 1..100 do
          spawn_monitor(fn ->
            case GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 100) do
              {:ok, worker_pid} ->
                :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})
                # Crash immediately
                exit(:boom)

              {:error, :checkout_timeout} ->
                # Expected when pool is busy
                :ok
            end
          end)
        end

      # Wait for all processes to finish
      for {pid, ref} <- callers do
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
      end

      # Verify all workers returned to idle (no leaks)
      eventually(
        fn ->
          state_final = :sys.get_state(pool_id)
          final_idle_count = IdleWorkers.count(state_final)
          final_busy_count = BusyWorkers.count(state_final)
          final_monitors_count = map_size(state_final.manual_monitors)

          assert final_idle_count == 5, "Expected 5 idle workers, got #{final_idle_count}"
          assert final_busy_count == 0, "Expected 0 busy workers, got #{final_busy_count}"

          assert final_monitors_count == 0,
                 "Expected 0 monitors, got #{final_monitors_count} (monitor leak)"
        end,
        2_000
      )
    end

    test "concurrent acquire and release operations are safe" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 10)

      test_pid = self()

      # Spawn 50 processes that acquire, hold briefly, then release
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            case GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 1_000) do
              {:ok, worker_pid} ->
                :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

                # Hold for random time (0-20ms)
                :timer.sleep(:rand.uniform(20))

                # Release
                GenServer.cast(pool_id, {:release_manual_worker, self(), worker_pid})

                send(test_pid, {:completed, i, :released})

              {:error, :checkout_timeout} ->
                send(test_pid, {:completed, i, :timeout})
            end
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, fn task -> Task.await(task, 5_000) end)

      # Collect results
      results =
        for _i <- 1..50 do
          receive do
            {:completed, _id, status} -> status
          after
            100 -> :no_message
          end
        end

      released_count = Enum.count(results, &(&1 == :released))
      timeout_count = Enum.count(results, &(&1 == :timeout))

      assert released_count + timeout_count == 50

      # Verify final state is clean once all releases are processed
      eventually(fn ->
        state_final = :sys.get_state(pool_id)
        assert IdleWorkers.count(state_final) == 10
        assert BusyWorkers.count(state_final) == 0
        assert map_size(state_final.manual_monitors) == 0
      end)
    end
  end

  describe "caller dies abnormally right after release" do
    # The caller releases its worker and exits abnormally before the pool has processed the release.
    # Its monitor sees the death and reports it, but by then the worker already belongs to the next
    # caller. The pool is suspended to hold the release and the monitor's report in its mailbox,
    # as happens under load.
    for exit_reason <- [:boom, :shutdown] do
      test "worker handed to the next caller survives (exit reason #{inspect(exit_reason)})" do
        pool_id = start_pool(worker_module: SomeWorker, workers_count: 1)
        test_pid = self()

        first_caller =
          spawn(fn ->
            Poolex.run(pool_id, fn worker ->
              send(test_pid, {:first_got, worker})
              receive do: (:finish -> :ok)
            end)

            exit(unquote(exit_reason))
          end)

        assert_receive {:first_got, worker_pid}
        eventually(fn -> assert Map.has_key?(:sys.get_state(pool_id).manual_monitors, worker_pid) end)
        {^first_caller, monitor_pid} = :sys.get_state(pool_id).manual_monitors[worker_pid]

        second_caller = spawn_waiting_caller(pool_id, test_pid)
        eventually(fn -> refute WaitingCallers.empty?(:sys.get_state(pool_id)) end)

        :sys.suspend(pool_id)
        first_caller_ref = Process.monitor(first_caller)
        monitor_ref = Process.monitor(monitor_pid)
        send(first_caller, :finish)
        assert_receive {:DOWN, ^first_caller_ref, _, _, unquote(exit_reason)}
        # The monitor has already reported the abnormal exit to the pool
        assert_receive {:DOWN, ^monitor_ref, _, _, :normal}
        :sys.resume(pool_id)

        assert_receive {:second_got, ^worker_pid}
        worker_ref = Process.monitor(worker_pid)
        refute_receive {:DOWN, ^worker_ref, _, _, _}, 100

        state = :sys.get_state(pool_id)
        assert BusyWorkers.member?(state, worker_pid)
        assert {^second_caller, _monitor_pid} = state.manual_monitors[worker_pid]
      end
    end

    test "late report does not touch the next caller's acquisition" do
      pool_id = start_pool(worker_module: SomeWorker, workers_count: 1)
      test_pid = self()

      {:ok, worker_pid} = Poolex.acquire(pool_id)
      {_caller_pid, stale_monitor_pid} = :sys.get_state(pool_id).manual_monitors[worker_pid]
      second_caller = spawn_waiting_caller(pool_id, test_pid)
      eventually(fn -> refute WaitingCallers.empty?(:sys.get_state(pool_id)) end)

      Poolex.release(pool_id, worker_pid)
      assert_receive {:second_got, ^worker_pid}
      eventually(fn -> assert {^second_caller, _} = :sys.get_state(pool_id).manual_monitors[worker_pid] end)
      {^second_caller, monitor_pid} = :sys.get_state(pool_id).manual_monitors[worker_pid]

      # The report of the first acquisition's monitor arrives after the second caller registered
      GenServer.cast(pool_id, {:manual_caller_down, worker_pid, stale_monitor_pid})

      worker_ref = Process.monitor(worker_pid)
      refute_receive {:DOWN, ^worker_ref, _, _, _}, 100
      assert Process.alive?(monitor_pid)
      assert {^second_caller, ^monitor_pid} = :sys.get_state(pool_id).manual_monitors[worker_pid]

      # The second caller can still release the worker
      send(second_caller, :release)
      eventually(fn -> assert IdleWorkers.member?(:sys.get_state(pool_id), worker_pid) end)
    end
  end

  # Starts a caller that waits for a worker, reports it and releases it on request.
  defp spawn_waiting_caller(pool_id, test_pid) do
    spawn(fn ->
      {:ok, worker_pid} = Poolex.acquire(pool_id)
      send(test_pid, {:second_got, worker_pid})
      receive do: (:release -> Poolex.release(pool_id, worker_pid))
      Process.sleep(:infinity)
    end)
  end
end
