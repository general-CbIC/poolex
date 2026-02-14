# Manual Worker Acquire/Release Design

**Date:** 2025-12-08
**Updated:** 2026-01-08
**Status:** Design Complete - Ready for Implementation
**Issue:** https://github.com/general-CbIC/poolex/issues/154

## Context

Users need manual control over worker checkout/checkin for long-running operations where the existing `run/3` function is insufficient. The primary use case is holding a database connection for the entire lifetime of a TCP session (similar to pgBouncer pattern).

## Requirements

Based on the GitHub issue and design discussion:

1. Provide `acquire(pool_id, opts)` and `release(pool_id, worker_pid)` functions
2. Support manual worker management for long-lived operations
3. Maintain safety through automatic cleanup if caller crashes
4. Refactor existing `run/3` to use new `acquire`/`release` internally
5. Support multiple workers per caller process
6. Use timeout-based checkout (like `run/3`)
7. Use waiting queue when no workers available

## Design Decisions

### 1. Auto-release on Caller Crash
**Decision:** Monitor caller and automatically release worker if caller dies
**Rationale:** Provides safety net while maintaining manual control API

### 2. Release Interface
**Decision:** `release(pool_id, worker_pid)` - explicit worker pid parameter
**Rationale:** Simple API without tracking state, allows passing workers between processes

### 3. Timeout Behavior
**Decision:** Support `checkout_timeout` option (same as `run/3`)
**Rationale:** Consistent API, allows control over wait time

### 4. Waiting Queue
**Decision:** Use existing waiting queue mechanism with monitoring
**Rationale:** Consistent behavior with `run/3`, handles dead callers in queue automatically

### 5. Multiple Workers per Caller
**Decision:** One caller can acquire multiple workers
**Rationale:** More flexible, supports complex use cases

### 6. Call vs Cast
**Decision:** `acquire` uses GenServer.call, `release` uses GenServer.cast
**Rationale:** `acquire` must wait for worker synchronously, `release` can be async for better performance

## Architecture

### State Changes

Add new field to `Poolex.Private.State`:

```elixir
defstruct [...existing fields...,
  manual_monitors: %{}  # %{worker_pid => monitor_process_pid}
]

@type t() :: %__MODULE__{
  ...
  manual_monitors: %{pid() => pid()}
}
```

### Public API

```elixir
@spec acquire(pool_id(), list(run_option())) :: {:ok, worker()} | {:error, :checkout_timeout}
def acquire(pool_id, options \\ [])

@spec release(pool_id(), worker()) :: :ok
def release(pool_id, worker_pid)
```

### Flow: acquire

1. Call existing `get_idle_worker/2` (handles timeout, waiting queue, overflow workers)
2. If successful, create monitor process via `start_manual_monitor/3`
3. Register monitor in `manual_monitors` via GenServer.call
4. Return `{:ok, worker_pid}`

```elixir
def acquire(pool_id, options \\ []) do
  checkout_timeout = Keyword.get(options, :checkout_timeout, @default_checkout_timeout)

  case get_idle_worker(pool_id, checkout_timeout) do
    {:ok, worker_pid} ->
      monitor_pid = start_manual_monitor(pool_id, self(), worker_pid)
      GenServer.call(pool_id, {:register_manual_monitor, worker_pid, monitor_pid})
      {:ok, worker_pid}

    {:error, :checkout_timeout} ->
      {:error, :checkout_timeout}
  end
end
```

### Flow: release

1. GenServer.cast `{:release_manual_worker, worker_pid}`
2. In handler:
   - Lookup and kill monitor process from `manual_monitors`
   - Remove from `manual_monitors`
   - Call existing `release_busy_worker` logic

```elixir
def release(pool_id, worker_pid) do
  GenServer.cast(pool_id, {:release_manual_worker, worker_pid})
end

def handle_cast({:release_manual_worker, worker_pid}, %State{} = state) do
  # 1. Get monitor_pid from manual_monitors (if exists)
  # 2. Kill monitor process
  # 3. Remove from manual_monitors
  # 4. Call existing release_busy_worker logic
  {:noreply, new_state}
end
```

### Flow: run (refactored)

```elixir
def run(pool_id, fun, options \\ []) do
  case acquire(pool_id, options) do
    {:ok, worker_pid} ->
      try do
        {:ok, fun.(worker_pid)}
      after
        release(pool_id, worker_pid)
      end

    {:error, :checkout_timeout} ->
      {:error, :checkout_timeout}
  end
end
```

### Monitor Process

New function to create monitor process (replaces `monitor_caller/3`):

```elixir
@spec start_manual_monitor(pool_id(), caller :: pid(), worker :: pid()) :: monitor_process :: pid()
defp start_manual_monitor(pool_id, caller, worker) do
  spawn(fn ->
    reference = Process.monitor(caller)

    receive do
      {:DOWN, ^reference, :process, ^caller, _reason} ->
        # On caller crash - release worker automatically
        GenServer.cast(pool_id, {:release_manual_worker, worker})
    end
  end)
end
```

## Race Condition Resolution

### Problem

Between `start_manual_monitor` and `register_manual_monitor` there's a window where:
- Monitor process is created and monitoring caller
- But worker_pid not yet in `manual_monitors`
- If caller crashes in this window, monitor sends `{:release_manual_worker, worker_pid}` but worker_pid not in map

### Chosen Solution: Atomic Registration Inside GenServer

**Decision:** Create monitor process INSIDE GenServer through atomic handle_call

**Implementation:**

```elixir
def acquire(pool_id, options \\ []) do
  checkout_timeout = Keyword.get(options, :checkout_timeout, @default_checkout_timeout)

  case get_idle_worker(pool_id, checkout_timeout) do
    {:ok, worker_pid} ->
      # Atomically create monitor and register in one call
      GenServer.call(pool_id, {:register_manual_acquisition, self(), worker_pid})
      {:ok, worker_pid}

    {:error, :checkout_timeout} ->
      {:error, :checkout_timeout}
  end
end

# In GenServer:
def handle_call({:register_manual_acquisition, caller_pid, worker_pid}, _from, state) do
  monitor_pid = start_manual_monitor(state.pool_id, caller_pid, worker_pid)
  new_state = put_in(state.manual_monitors[worker_pid], monitor_pid)
  {:reply, :ok, new_state}
end
```

**Rationale:**

- **Eliminates race condition:** Operation is atomic within GenServer
- **Simple semantics:** Monitor created and registered in single step
- **Guaranteed consistency:** Monitor process ALWAYS in map when it sends messages
- **Follows principle:** Critical state belongs inside GenServer

**Trade-offs:**

- GenServer blocks during `spawn` (but only ~microseconds)
- Two sequential GenServer.call operations for `acquire` instead of one

**Alternatives Considered:**

1. **Graceful ignore** - Would leave orphaned monitor processes
2. **Two-phase registration** - Unnecessarily complex

## Implementation Plan

### Phase 1: Proof-of-Concept (Validate Race Condition Solution)

**Goal:** Verify atomic registration approach works before changing public API

1. **Add infrastructure:**
   - Add `manual_monitors: %{pid() => pid()}` field to `Poolex.Private.State`
   - Implement `handle_call({:register_manual_acquisition, caller_pid, worker_pid}, ...)`
   - Implement `start_manual_monitor/3` (based on current `monitor_caller/3`)
   - Implement `handle_cast({:release_manual_worker, worker_pid}, ...)`

2. **Write proof-of-concept test:**
   - Test basic flow: get_idle_worker → register_manual_acquisition → verify monitor created
   - Test auto-release: caller crashes → worker automatically released
   - Test manual release: call release_manual_worker cast → monitor killed, worker freed

3. **Write stress test for race condition:**
   - Spawn many processes in parallel
   - Each process: get_idle_worker → register_manual_acquisition → crash immediately
   - Verify: no worker leaks, all workers returned to pool

4. **Decision point:** If PoC successful, proceed to Phase 2

### Phase 2: Public API Implementation

5. **Implement public `acquire/2` function:**
   - Wraps `get_idle_worker` + `register_manual_acquisition`
   - Returns `{:ok, worker_pid}` or `{:error, :checkout_timeout}`

6. **Implement public `release/2` function:**
   - Simple wrapper around `GenServer.cast(pool_id, {:release_manual_worker, worker_pid})`

7. **Refactor `run/3` to use `acquire`/`release`:**
   - Replace `monitor_caller` + manual cleanup with `acquire` → `release` in after block
   - Ensures consistency between manual and automatic worker management

8. **Remove old `monitor_caller/3` function:**
   - No longer needed after `run/3` refactoring

### Phase 3: Testing & Documentation

9. **Add comprehensive tests:**
   - Multiple workers per caller
   - Timeout behavior
   - Interaction with overflow workers
   - Edge cases (releasing non-existent worker, double-release, etc.)

10. **Update documentation:**
    - Add `acquire/2` and `release/2` to module docs
    - Add usage examples and patterns
    - Document safety guarantees (auto-release on crash)
    - Update CHANGELOG.md

## Notes

- Existing `get_idle_worker/2` handles all complex pool logic (overflow, waiting queue, etc.)
- Existing `release_busy_worker/1` handles returning worker to pool or stopping overflow workers
- New code mainly adds monitoring layer on top of existing infrastructure
- The `{:stop_worker, worker}` message used in old `monitor_caller/3` is replaced with `{:release_manual_worker, worker}` for more graceful handling

## Phase 1 Results - Proof of Concept

**Status:** ✅ Complete (2026-02-14)

**Implementation:**
- Added `manual_monitors` field to State (lib/poolex/private/state.ex:29)
- Added `member?/2` to IdleWorkers for consistency with BusyWorkers
- Implemented `start_manual_monitor/3` (lib/poolex.ex:627-639)
- Implemented `handle_call({:register_manual_acquisition, ...})` (lib/poolex.ex:377-381)
- Implemented `handle_cast({:release_manual_worker, ...})` (lib/poolex.ex:450-471)

**Testing:**
- ✅ Basic flow tests (monitor creation, registration, multiple workers)
- ✅ Auto-release tests (caller crash, monitor cleanup)
- ✅ Manual release tests (explicit release, waiting callers, graceful error handling)
- ✅ Stress tests (100 concurrent crashes, 50 concurrent operations)
- ✅ All 9 PoC tests pass consistently across 5 runs

**Validation:**
- ✅ No race conditions detected in stress tests
- ✅ No worker leaks
- ✅ No monitor process leaks
- ✅ All existing tests pass (227 total tests)
- ✅ Dialyzer clean
- ✅ Credo clean
- ✅ Code formatted

**Conclusion:** Atomic registration approach is validated and ready for Phase 2 (public API implementation).

## Phase 2 Results - Public API Implementation

**Status:** ✅ Complete (2026-02-14)

**Implementation:**
- ✅ Implemented public `acquire/2` function (lib/poolex.ex:220-240)
- ✅ Implemented public `release/2` function (lib/poolex.ex:269-289)
- ✅ Refactored `run/3` to use `acquire/release` internally (lib/poolex.ex:182-194)
- ✅ Removed old `monitor_caller/3` (consolidated into `start_manual_monitor/3`)
- ✅ Added `cleanup_manual_monitor` handler for proper cleanup
- ✅ Enhanced monitor to only kill worker on abnormal termination (not `:normal`)

**Key Design Decision:**
- **Normal shutdown (`:normal`)**: Worker returned gracefully via `release/2`
- **Abnormal shutdown (crash)**: Worker killed and restarted to prevent stuck workers
- This prevents returning workers stuck in long-running operations to the pool

**API Documentation:**
- Comprehensive docs for `acquire/2` with examples and safety notes
- Comprehensive docs for `release/2` with usage patterns
- Both functions have @spec and doctests

**Testing:**
- ✅ Updated auto-kill test to verify worker restart on crash
- ✅ All 227 tests pass (with 1 pre-existing flaky test unrelated to feature)
- ✅ Dialyzer clean
- ✅ Credo clean
- ✅ Documentation coverage: 98.7%

**Conclusion:** Public API is complete and ready for production use.
