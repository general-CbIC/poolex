# Ideas for implementing

## Pool Metrics

I want to make a simple way to analyze running pools to set their optimal configuration. For example, we launched a `pool` in production with a maximum overflow of 0 (we do not want to create more processes than the designated number) and a pool size 200.

Using metrics, we see that typically, our application uses 10-20 processes, and there are spikes when up to 180 workers are exploited. If our processes are heavyweight and, for example, open persistent connections to storage, then by analyzing metrics, we can significantly save resources. In this case, we can set the pool size to 20 and `max_overflow` to 180. This way, we will have one overall pool size limit of 200, and we will avoid uncontrolled waste of all resources, but at the same time, we will only keep up to 20 processes in memory at times when this is not required.

### Metrics to be implemented

- [x] Pool size
  - [x] Idle workers count
  - [x] Busy workers count
  - [x] Is max_overflow used?
- [ ] Usage time
  - [ ] How long are workers busy?
  - [ ] How long the application waits of workers from pool?

## Implementations metrics

To be described...

## Architecture Improvements

### Refactor monitoring to use `Process.link` instead of `Process.monitor`

**Current problem:**
- Monitor tracking uses `%{reference() => kind_of_process()}` map
- Can't easily unmonitor a process by pid (only by reference)
- Makes `remove_idle_workers!` difficult to implement correctly:
  - Need to find monitor reference for a given worker pid
  - Either keep reverse map (adds complexity) or iterate through all monitors (slow)
- Manual lifecycle management increases complexity and potential for bugs

**Proposed solution:**
Replace `Process.monitor` with `Process.link` + `trap_exit`:

```elixir
# Current state (in state.ex):
monitors: %{reference() => :worker | :waiting_caller}

# Proposed: remove monitors entirely, use links instead

# Benefits:
1. Remove monitors map entirely from state
2. Automatic cleanup when processes die (links are bidirectional)
3. Simpler remove_idle_workers: Process.unlink + terminate_child
4. Handle {:EXIT, pid, reason} instead of {:DOWN, ref, ...}
5. Less state to manage, fewer race conditions
6. Can unlink by pid directly: Process.unlink(worker_pid)

# Changes needed:
- Remove or drastically simplify Poolex.Private.Monitoring module
- Use Process.link() in start_worker instead of Monitoring.add()
- Handle {:EXIT, pid, reason} messages in handle_info instead of {:DOWN, ref, ...}
- Use Process.unlink() before stopping workers in remove_idle_workers
- Update state.ex to remove monitors field
- Update handle_info to pattern match on pid instead of reference
```

**Trade-offs:**
- Need to distinguish EXIT messages from workers vs callers (solvable: check if pid is in busy/idle/overflowed collections)
- EXIT handling is slightly different from DOWN handling (but simpler overall)
- Links are bidirectional (if Poolex crashes, workers die too - but this is already the case with current supervision tree)

**Estimated impact:** Significant simplification of worker lifecycle management, easier to maintain and extend. Makes `remove_idle_workers!` trivial to implement.

### Fix `remove_idle_workers!` resource leak

**Current problem (`lib/poolex.ex:518`):**
- `handle_call({:remove_idle_workers, ...})` only removes workers from the idle collection via `IdleWorkers.remove/2`
- Worker processes continue running inside `DynamicSupervisor` — they are inaccessible to the pool but consume resources
- No `stop_worker` call, no demonitor — workers are simply orphaned
- Repeated calls to `remove_idle_workers!` gradually exhaust system resources

**Root cause:**
- Can't unmonitor by pid (only by reference) — see monitoring refactoring above
- Without `Process.unlink`, stopping the worker would trigger an unwanted EXIT/DOWN handling

**Proposed fix:**
- After the `Process.link` refactoring: call `Process.unlink(worker_pid)` then `DynamicSupervisor.terminate_child` for each removed worker
- Before the refactoring (quick fix): add a reverse map `%{pid() => reference()}` to state for O(1) pid→reference lookup, then demonitor + stop each removed worker

### Fix race condition in `start_manual_monitor`

**Current problem (`lib/poolex.ex:734`):**
A monitor process is spawned for every `acquire/2` call to watch the caller and kill the worker if the caller dies abnormally. This creates a race condition:

1. Caller A holds Worker W
2. Caller A calls `release/2` → pool removes W from `manual_monitors`, calls `Process.exit(monitor_pid, :kill)`
3. But the monitor process **already received** `{:DOWN, ...}` before being killed (caller died abnormally just before release)
4. Monitor sends `GenServer.cast(pool_id, {:stop_worker, W})`
5. Pool may have already given W to Caller B
6. Pool receives `{:stop_worker, W}` → kills W, which now belongs to Caller B

**Contributing issue:**
`handle_cast({:stop_worker, worker_pid})` does not check the worker's current state before killing it:

```elixir
# lib/poolex.ex:577 — no ownership check
def handle_cast({:stop_worker, worker_pid}, %State{} = state) do
  stop_worker(state.supervisor, worker_pid)
  {:noreply, state}
end
```

**Proposed fix:**
Before stopping, verify the worker is still in `BusyWorkers` and still owned by the expected caller:

```elixir
def handle_cast({:stop_worker, worker_pid, caller_pid}, %State{} = state) do
  case Map.get(state.manual_monitors, worker_pid) do
    {^caller_pid, _monitor_pid} ->
      stop_worker(state.supervisor, worker_pid)
    _ ->
      :ok  # worker already released or belongs to another caller — do nothing
  end
  {:noreply, state}
end
```

Pass `caller_pid` alongside `worker_pid` when sending `{:stop_worker}` from the monitor process.

### Fix worker leak on simultaneous timeout and release

**Current problem (`lib/poolex.ex:292`):**

A worker can get permanently stuck in `BusyWorkers` if a caller's checkout timeout races with a worker becoming available:

1. No idle workers — caller is added to `waiting_callers`
2. Caller times out → `GenServer.call` returns `{:error, :checkout_timeout}`
3. Simultaneously, a worker is released → pool calls `provide_worker_to_waiting_caller` → `GenServer.reply(caller.from, {:ok, worker})`
4. The reply is lost (caller already returned from its timed-out `call`)
5. Pool then processes `{:cancel_waiting, ref}` — but the caller was already popped from the queue
6. Worker is now stuck in `BusyWorkers` indefinitely (until it crashes)

**Proposed fix:**
In `provide_worker_to_waiting_caller`, check that the caller process is still alive before replying:

```elixir
defp provide_worker_to_waiting_caller(%State{} = state, worker) do
  {caller, state} = WaitingCallers.pop(state)
  {from_pid, _tag} = caller.from

  if Process.alive?(from_pid) do
    GenServer.reply(caller.from, {:ok, worker})
    state
  else
    # Caller already gone — return worker to idle instead of leaking it
    release_busy_worker(state, worker)
  end
end
```

**Note:** `Process.alive?/1` is not perfectly atomic but eliminates the common case. A fully correct solution would require a two-phase acknowledgement protocol.
