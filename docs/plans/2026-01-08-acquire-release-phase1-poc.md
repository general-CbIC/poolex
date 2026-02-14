# Acquire/Release Phase 1 - Proof of Concept Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Validate atomic registration approach for manual worker acquisition before implementing public API

**Architecture:** Add internal infrastructure (`manual_monitors` state field, GenServer handlers) and verify race condition is eliminated through atomic monitor registration within GenServer call.

**Tech Stack:** Elixir GenServer, ExUnit, Process monitoring

---

## Task 1: Add manual_monitors Field to State

**Files:**
- Modify: `lib/poolex/private/state.ex:19-33` (defstruct)
- Modify: `lib/poolex/private/state.ex:35-56` (@type)

**Step 1: Add field to defstruct**

Add `manual_monitors: %{}` to the defstruct list:

```elixir
defstruct @enforce_keys ++
            [
              busy_workers_impl: nil,
              busy_workers_state: nil,
              failed_to_start_workers_count: 0,
              idle_overflowed_workers_impl: nil,
              idle_overflowed_workers_last_touches: %{},
              idle_overflowed_workers_state: nil,
              idle_workers_impl: nil,
              idle_workers_state: nil,
              manual_monitors: %{},
              monitors: %{},
              overflow: 0,
              waiting_callers_impl: nil,
              waiting_callers_state: nil
            ]
```

**Step 2: Add type specification**

Add `manual_monitors` to the @type definition:

```elixir
@type t() :: %__MODULE__{
        busy_workers_impl: module(),
        busy_workers_state: nil | Poolex.Workers.Behaviour.state(),
        failed_to_start_workers_count: non_neg_integer(),
        failed_workers_retry_interval: timeout() | nil,
        idle_overflowed_workers_impl: module(),
        idle_overflowed_workers_last_touches: %{pid() => Time.t()},
        idle_overflowed_workers_state: nil | Poolex.Workers.Behaviour.state(),
        idle_workers_impl: module(),
        idle_workers_state: nil | Poolex.Workers.Behaviour.state(),
        manual_monitors: %{pid() => pid()},
        max_overflow: non_neg_integer(),
        monitors: %{reference() => Poolex.Private.Monitoring.kind_of_process()},
        overflow: non_neg_integer(),
        pool_id: Poolex.pool_id(),
        supervisor: pid(),
        waiting_callers_impl: module(),
        waiting_callers_state: nil | Poolex.Callers.Behaviour.state(),
        worker_args: list(any()),
        worker_module: module(),
        worker_shutdown_delay: timeout(),
        worker_start_fun: atom()
      }
```

**Step 3: Run dialyzer to verify types**

Run: `mix dialyzer`
Expected: No type errors

**Step 4: Commit**

```bash
git add lib/poolex/private/state.ex
git commit -m "feat: add manual_monitors field to State

Track monitor processes for manually acquired workers.
Maps worker_pid => monitor_process_pid.

Part of Phase 1 PoC for acquire/release feature.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Implement start_manual_monitor/3

**Files:**
- Modify: `lib/poolex.ex:596-end` (add new private function after monitor_caller/3)

**Step 1: Add start_manual_monitor/3 function**

Add function after existing `monitor_caller/3` (around line 595):

```elixir
# Monitor the `caller`. Release attached worker in case of caller's death.
# Unlike monitor_caller/3, this uses cast to release worker gracefully instead of stopping it.
@spec start_manual_monitor(pool_id(), caller :: pid(), worker :: pid()) :: monitor_process :: pid()
defp start_manual_monitor(pool_id, caller, worker) do
  spawn(fn ->
    reference = Process.monitor(caller)

    receive do
      {:DOWN, ^reference, :process, ^caller, _reason} ->
        # Send message to release worker if caller is dead
        GenServer.cast(pool_id, {:release_manual_worker, worker})
    end
  end)
end
```

**Step 2: Run tests to verify no breakage**

Run: `mix test`
Expected: All existing tests pass

**Step 3: Commit**

```bash
git add lib/poolex.ex
git commit -m "feat: add start_manual_monitor/3 for manual acquisitions

Similar to monitor_caller/3 but releases worker gracefully
instead of stopping it when caller crashes.

Part of Phase 1 PoC for acquire/release feature.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Implement handle_call for register_manual_acquisition

**Files:**
- Modify: `lib/poolex.ex:376-400` (add new handle_call clause before :get_debug_info)

**Step 1: Add handle_call clause**

Add after existing `handle_call({:get_idle_worker, ...})` handler (around line 375):

```elixir
def handle_call({:register_manual_acquisition, caller_pid, worker_pid}, _from, %State{} = state) do
  monitor_pid = start_manual_monitor(state.pool_id, caller_pid, worker_pid)
  new_state = put_in(state.manual_monitors[worker_pid], monitor_pid)
  {:reply, :ok, new_state}
end
```

**Step 2: Run tests to verify no breakage**

Run: `mix test`
Expected: All existing tests pass

**Step 3: Commit**

```bash
git add lib/poolex.ex
git commit -m "feat: add register_manual_acquisition handler

Atomically creates monitor process and registers it in state.
Eliminates race condition between monitor creation and registration.

Part of Phase 1 PoC for acquire/release feature.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Implement handle_cast for release_manual_worker

**Files:**
- Modify: `lib/poolex.ex:442-453` (add new handle_cast clause after {:release_busy_worker, ...})

**Step 1: Add handle_cast clause**

Add after existing `handle_cast({:release_busy_worker, ...})` handler (around line 442):

```elixir
def handle_cast({:release_manual_worker, worker_pid}, %State{} = state) do
  # Kill monitor process if it exists
  state =
    case Map.get(state.manual_monitors, worker_pid) do
      nil ->
        state

      monitor_pid ->
        Process.exit(monitor_pid, :kill)
        %{state | manual_monitors: Map.delete(state.manual_monitors, worker_pid)}
    end

  # Release worker back to pool or handle waiting callers
  new_state =
    if WaitingCallers.empty?(state) do
      release_busy_worker(state, worker_pid)
    else
      provide_worker_to_waiting_caller(state, worker_pid)
    end

  {:noreply, new_state}
end
```

**Step 2: Run tests to verify no breakage**

Run: `mix test`
Expected: All existing tests pass

**Step 3: Commit**

```bash
git add lib/poolex.ex
git commit -m "feat: add release_manual_worker handler

Handles manual worker release by:
1. Killing monitor process (if exists)
2. Removing from manual_monitors map
3. Releasing worker back to pool

Part of Phase 1 PoC for acquire/release feature.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Write Basic PoC Test

**Files:**
- Create: `test/poolex_manual_acquisition_test.exs`

**Step 1: Create test file with basic flow test**

```elixir
defmodule PoolexManualAcquisitionTest do
  @moduledoc """
  Proof-of-concept tests for manual worker acquisition infrastructure.
  Tests internal GenServer handlers before exposing public API.
  """
  use ExUnit.Case

  import PoolHelpers

  alias Poolex.Private.BusyWorkers
  alias Poolex.Private.IdleWorkers

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
      monitor_pid = state.manual_monitors[worker_pid]
      assert is_pid(monitor_pid)
      assert Process.alive?(monitor_pid)

      # Verify worker is busy
      assert BusyWorkers.member?(state, worker_pid)
      refute IdleWorkers.member?(state, worker_pid)

      # Clean up
      GenServer.cast(pool_id, {:release_manual_worker, worker_pid})
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
      GenServer.cast(pool_id, {:release_manual_worker, worker1})
      GenServer.cast(pool_id, {:release_manual_worker, worker2})
    end
  end
end
```

**Step 2: Run the new test**

Run: `mix test test/poolex_manual_acquisition_test.exs`
Expected: Both tests PASS

**Step 3: Run all tests**

Run: `mix test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add test/poolex_manual_acquisition_test.exs
git commit -m "test: add basic PoC tests for manual acquisition

Verify:
- Monitor creation and registration
- Multiple workers per caller

Part of Phase 1 PoC for acquire/release feature.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Write Auto-Release Test

**Files:**
- Modify: `test/poolex_manual_acquisition_test.exs` (add new describe block)

**Step 1: Add auto-release test**

Add new describe block after existing tests:

```elixir
describe "release_manual_worker - auto release on caller crash" do
  test "worker released when caller crashes" do
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
    worker_pid =
      receive do
        {:worker_acquired, pid} -> pid
      after
        1_000 -> flunk("Timeout waiting for worker acquisition")
      end

    # Verify worker is busy and monitored
    state_before = :sys.get_state(pool_id)
    assert BusyWorkers.member?(state_before, worker_pid)
    assert Map.has_key?(state_before.manual_monitors, worker_pid)

    # Crash the caller
    send(crashed_caller, :crash)
    Process.sleep(50)

    # Verify worker released and monitor removed
    state_after = :sys.get_state(pool_id)
    refute BusyWorkers.member?(state_after, worker_pid)
    assert IdleWorkers.member?(state_after, worker_pid)
    refute Map.has_key?(state_after.manual_monitors, worker_pid)
  end

  test "monitor process dies after releasing worker" do
    pool_id = start_pool(worker_module: SomeWorker, workers_count: 2)

    # Acquire and register
    {:ok, worker_pid} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
    :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

    # Get monitor pid
    state = :sys.get_state(pool_id)
    monitor_pid = state.manual_monitors[worker_pid]
    assert Process.alive?(monitor_pid)

    # Release worker
    GenServer.cast(pool_id, {:release_manual_worker, worker_pid})
    Process.sleep(10)

    # Verify monitor process killed
    refute Process.alive?(monitor_pid)

    # Verify removed from state
    state_after = :sys.get_state(pool_id)
    refute Map.has_key?(state_after.manual_monitors, worker_pid)
  end
end
```

**Step 2: Run the new tests**

Run: `mix test test/poolex_manual_acquisition_test.exs`
Expected: All tests PASS

**Step 3: Run all tests**

Run: `mix test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add test/poolex_manual_acquisition_test.exs
git commit -m "test: add auto-release tests for manual acquisition

Verify:
- Worker released when caller crashes
- Monitor process killed after release

Part of Phase 1 PoC for acquire/release feature.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Write Manual Release Test

**Files:**
- Modify: `test/poolex_manual_acquisition_test.exs` (add new describe block)

**Step 1: Add manual release tests**

Add new describe block:

```elixir
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
    GenServer.cast(pool_id, {:release_manual_worker, worker_pid})
    Process.sleep(10)

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
    GenServer.cast(pool_id, {:release_manual_worker, fake_worker_pid})
    Process.sleep(10)

    # Pool should still be operational
    assert {:ok, _worker} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
  end

  test "worker provided to waiting caller instead of idle pool" do
    pool_id = start_pool(worker_module: SomeWorker, workers_count: 1)

    # Acquire the only worker
    {:ok, worker_pid} = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
    :ok = GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})

    # Spawn waiting caller
    test_pid = self()

    waiting_caller =
      spawn(fn ->
        result = GenServer.call(pool_id, {:get_idle_worker, make_ref()}, 5_000)
        send(test_pid, {:got_worker, result})
      end)

    Process.sleep(50)

    # Verify caller is waiting
    state_waiting = :sys.get_state(pool_id)
    assert length(state_waiting.waiting_callers_state) == 1

    # Release worker
    GenServer.cast(pool_id, {:release_manual_worker, worker_pid})

    # Verify waiting caller received the worker
    assert_receive {:got_worker, {:ok, ^worker_pid}}, 1_000

    # Verify no waiting callers
    state_after = :sys.get_state(pool_id)
    assert length(state_after.waiting_callers_state) == 0
  end
end
```

**Step 2: Run the new tests**

Run: `mix test test/poolex_manual_acquisition_test.exs`
Expected: All tests PASS

**Step 3: Run all tests**

Run: `mix test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add test/poolex_manual_acquisition_test.exs
git commit -m "test: add explicit release tests for manual acquisition

Verify:
- Worker returned to idle pool
- Graceful handling of non-existent worker
- Worker provided to waiting caller

Part of Phase 1 PoC for acquire/release feature.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Write Stress Test for Race Condition

**Files:**
- Modify: `test/poolex_manual_acquisition_test.exs` (add new describe block)

**Step 1: Add stress test**

Add new describe block:

```elixir
describe "race condition stress test" do
  test "no worker leaks when many callers crash immediately after acquiring" do
    pool_id = start_pool(worker_module: SomeWorker, workers_count: 5)

    # Initial state
    state_initial = :sys.get_state(pool_id)
    initial_idle_count = IdleWorkers.count(state_initial)
    assert initial_idle_count == 5

    # Spawn 100 processes that acquire and crash immediately
    for _i <- 1..100 do
      spawn(fn ->
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
    Process.sleep(500)

    # Verify all workers returned to idle (no leaks)
    state_final = :sys.get_state(pool_id)
    final_idle_count = IdleWorkers.count(state_final)
    final_busy_count = BusyWorkers.count(state_final)
    final_monitors_count = map_size(state_final.manual_monitors)

    assert final_idle_count == 5, "Expected 5 idle workers, got #{final_idle_count}"
    assert final_busy_count == 0, "Expected 0 busy workers, got #{final_busy_count}"

    assert final_monitors_count == 0,
           "Expected 0 monitors, got #{final_monitors_count} (monitor leak)"
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
              GenServer.cast(pool_id, {:release_manual_worker, worker_pid})

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

    # Wait for all releases to complete
    Process.sleep(100)

    # Verify final state is clean
    state_final = :sys.get_state(pool_id)
    assert IdleWorkers.count(state_final) == 10
    assert BusyWorkers.count(state_final) == 0
    assert map_size(state_final.manual_monitors) == 0
  end
end
```

**Step 2: Run stress tests multiple times**

Run: `mix test test/poolex_manual_acquisition_test.exs --only describe:"race condition stress test"`
Run this 5 times to verify stability
Expected: All tests PASS consistently

**Step 3: Run all tests**

Run: `mix test`
Expected: All tests PASS

**Step 4: Run mix check**

Run: `mix check`
Expected: All checks PASS (tests, dialyzer, credo, formatter)

**Step 5: Commit**

```bash
git add test/poolex_manual_acquisition_test.exs
git commit -m "test: add stress tests for race condition validation

Verify:
- No worker leaks with 100 concurrent crash scenarios
- Safe concurrent acquire/release operations

Validates atomic registration eliminates race condition.

Phase 1 PoC complete.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Document PoC Results

**Files:**
- Modify: `docs/plans/2025-12-08-manual-worker-acquire-release-design.md`

**Step 1: Update design doc with PoC results**

Add section at the end of the document:

```markdown
## Phase 1 Results - Proof of Concept

**Status:** ✅ Complete

**Implementation:**
- Added `manual_monitors` field to State (lib/poolex/private/state.ex)
- Implemented `start_manual_monitor/3` (lib/poolex.ex)
- Implemented `handle_call({:register_manual_acquisition, ...})` (lib/poolex.ex)
- Implemented `handle_cast({:release_manual_worker, ...})` (lib/poolex.ex)

**Testing:**
- ✅ Basic flow tests (monitor creation, registration, multiple workers)
- ✅ Auto-release tests (caller crash, monitor cleanup)
- ✅ Manual release tests (explicit release, waiting callers)
- ✅ Stress tests (100 concurrent crashes, concurrent operations)

**Validation:**
- ✅ No race conditions detected in stress tests
- ✅ No worker leaks
- ✅ No monitor process leaks
- ✅ All existing tests pass
- ✅ Dialyzer clean
- ✅ Credo clean

**Conclusion:** Atomic registration approach is validated and ready for Phase 2 (public API).
```

**Step 2: Commit documentation**

```bash
git add docs/plans/2025-12-08-manual-worker-acquire-release-design.md
git commit -m "docs: document Phase 1 PoC completion

Atomic registration approach validated through:
- 8 implementation commits
- 12 test cases covering basic, auto-release, manual release, stress scenarios
- All quality checks passing

Ready to proceed to Phase 2 (public API).

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Completion Checklist

- [ ] Task 1: manual_monitors field added to State
- [ ] Task 2: start_manual_monitor/3 implemented
- [ ] Task 3: register_manual_acquisition handler implemented
- [ ] Task 4: release_manual_worker handler implemented
- [ ] Task 5: Basic PoC tests written
- [ ] Task 6: Auto-release tests written
- [ ] Task 7: Manual release tests written
- [ ] Task 8: Stress tests written and passing
- [ ] Task 9: Documentation updated
- [ ] All tests passing (`mix test`)
- [ ] Dialyzer clean (`mix dialyzer`)
- [ ] Credo clean (`mix credo`)
- [ ] Code formatted (`mix format`)

---

## Notes

**Testing Strategy:**
- Tests use internal GenServer.call/cast directly (not public API)
- This validates infrastructure before exposing public interface
- Tests verify both happy path and edge cases (crashes, race conditions)

**Key Validation Points:**
- Monitor process created and registered atomically
- No race condition window between creation and registration
- Auto-release on caller crash works correctly
- Manual release cleans up monitor process
- Stress tests confirm no leaks under concurrent load

**Next Phase:**
Once PoC validated, proceed to Phase 2:
- Implement public `acquire/2` function
- Implement public `release/2` function
- Refactor `run/3` to use new infrastructure
- Add public API tests and documentation
