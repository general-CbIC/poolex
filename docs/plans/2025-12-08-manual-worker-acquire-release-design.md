# Manual Worker Acquire/Release Design

**Date:** 2025-12-08
**Status:** In Progress - Brainstorming Phase
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

## Open Questions

### Race Condition in acquire

**Problem:** Between `start_manual_monitor` and `register_manual_monitor` there's a window where:
- Monitor process is created and monitoring caller
- But worker_pid not yet in `manual_monitors`
- If caller crashes in this window, monitor sends `{:release_manual_worker, worker_pid}` but worker_pid not in map

**Possible Solutions:**

1. **Ignore gracefully:** In `handle_cast({:release_manual_worker, ...})`, if worker not in `manual_monitors`, just call `release_busy_worker` directly
   - Pros: Simple, safe fallback
   - Cons: Monitor process becomes orphaned (but will exit naturally after one message)

2. **Register before monitor:** Change order in `acquire`:
   ```elixir
   GenServer.call(pool_id, {:acquire_and_register, self(), worker_pid})
   ```
   - Handle call creates monitor AND registers it atomically
   - Pros: No race condition
   - Cons: More complex call, blocks GenServer longer

3. **Two-phase with pre-registration:**
   - Register placeholder in `manual_monitors` first
   - Create monitor
   - Update with real monitor_pid
   - Pros: Atomic
   - Cons: Most complex

**Recommendation:** TBD - needs discussion

## Implementation Plan

(To be completed once design is finalized)

1. Add `manual_monitors` field to State
2. Implement `start_manual_monitor/3`
3. Implement `acquire/2` with `handle_call({:register_manual_monitor, ...})`
4. Implement `release/2` with `handle_cast({:release_manual_worker, ...})`
5. Refactor `run/3` to use `acquire`/`release`
6. Remove old `monitor_caller/3` function
7. Add tests for new functionality
8. Update documentation

## Notes

- Existing `get_idle_worker/2` handles all complex pool logic (overflow, waiting queue, etc.)
- Existing `release_busy_worker/1` handles returning worker to pool or stopping overflow workers
- New code mainly adds monitoring layer on top of existing infrastructure
- The `{:stop_worker, worker}` message used in old `monitor_caller/3` is replaced with `{:release_manual_worker, worker}` for more graceful handling
