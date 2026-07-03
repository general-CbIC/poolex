# Ideas for implementing

## Pool Metrics

I want to make a simple way to analyze running pools to set their optimal configuration. For example, we launched a `pool` in production with a maximum overflow of 0 (we do not want to create more processes than the designated number) and a pool size 200.

Using metrics, we see that typically, our application uses 10-20 processes, and there are spikes when up to 180 workers are exploited. If our processes are heavyweight and, for example, open persistent connections to storage, then by analyzing metrics, we can significantly save resources. In this case, we can set the pool size to 20 and `max_overflow` to 180. This way, we will have one overall pool size limit of 200, and we will avoid uncontrolled waste of all resources, but at the same time, we will only keep up to 20 processes in memory at times when this is not required.

Pool size metrics (idle/busy workers count, overflow flag) are already implemented. Remaining:

- [ ] Usage time
  - [ ] How long are workers busy?
  - [ ] How long the application waits of workers from pool?

## Bugs & Correctness

### Fix race condition in `start_manual_monitor`

**Current problem (`lib/poolex.ex:802`):**
A monitor process is spawned for every `acquire/2` call (and therefore for every `run/3` call) to watch the caller and kill the worker if the caller dies abnormally. This creates a race condition:

1. Caller A holds Worker W
2. Caller A calls `release/2` → pool removes W from `manual_monitors`, calls `Process.exit(monitor_pid, :kill)`
3. But the monitor process **already received** `{:DOWN, ...}` before being killed (caller died abnormally just before release)
4. Monitor sends `GenServer.cast(pool_id, {:stop_worker, W})`
5. Pool may have already given W to Caller B
6. Pool receives `{:stop_worker, W}` → kills W, which now belongs to Caller B

**Contributing issue:**
`handle_cast({:stop_worker, worker_pid})` does not check the worker's current state before killing it:

```elixir
# lib/poolex.ex:640 — no ownership check
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

**Current problem (`lib/poolex.ex:297`):**

A worker can get permanently stuck in `BusyWorkers` if a caller's checkout timeout races with a worker becoming available:

1. No idle workers — caller is added to `waiting_callers`
2. Caller times out → `GenServer.call` returns `{:error, :checkout_timeout}`
3. Simultaneously, a worker is released → pool calls `provide_worker_to_waiting_caller` (`lib/poolex.ex:739`) → `GenServer.reply(caller.from, {:ok, worker})`
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
    # Dead caller — try the next one, or return the worker to the pool
    if WaitingCallers.empty?(state) do
      release_busy_worker(state, worker)
    else
      provide_worker_to_waiting_caller(state, worker)
    end
  end
end
```

**Notes:**

- `Process.alive?/1` is not perfectly atomic but eliminates the common case. A fully correct solution would require a two-phase acknowledgement protocol.
- `Process.alive?/1` raises for remote pids — guard with `node(from_pid) == node()` if cross-node calls should be supported.

### Fix dangling caller monitors (both timeout and success paths)

**Current problem:**

The pool monitors every caller placed into the waiting queue (`Monitoring.add(from_pid, :waiting_caller)` in `handle_call({:get_idle_worker, ...})`), but **never demonitors** it when the caller leaves the queue:

1. **Timeout path (`lib/poolex.ex:662`):** `handle_cast({:cancel_waiting, ref})` removes the caller from the queue via `WaitingCallers.remove_by_reference/2` without demonitoring.
2. **Success path (`lib/poolex.ex:739`):** `provide_worker_to_waiting_caller/2` pops the caller and replies without demonitoring.

**Impact:**

- Every checkout that went through the waiting queue leaves a permanent entry in `state.monitors` plus a live monitor until the caller process dies.
- Long-lived callers that repeatedly wait for workers (named GenServers, channel processes) grow `state.monitors` unboundedly and generate useless `{:DOWN, ...}` traffic when they finally die.

**Proposed fix:**
Demonitor when the caller leaves the queue (both paths). Easiest path: store `monitor_ref` inside `Poolex.Caller` so it is available on pop/remove. Cleaner path: after the `Process.link` refactor below, this bookkeeping goes away.

### Make `acquire/2` atomic (race between `get_idle_worker` and `register_manual_acquisition`)

**Current problem (`lib/poolex.ex:249-260`):**

`acquire/2` performs two sequential `GenServer.call`s to the pool:

1. `{:get_idle_worker, ref}` — worker is moved to `BusyWorkers`
2. `{:register_manual_acquisition, self(), worker_pid}` — monitor is set up

If the caller process dies **between** these two calls, the worker is stuck in `BusyWorkers` with no monitor and no entry in `manual_monitors` — pool has no way to reclaim it until the worker itself crashes.

**Proposed fix:**
Collapse into a single atomic call that takes the worker and registers the monitor in one `handle_call`. The caller pid is trivially available via `GenServer.call`'s `from` argument, so no extra data needs to be passed.

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
- The pool already traps exits and has a catch-all `handle_info({:EXIT, _pid, reason}) → {:stop, ...}` clause (`lib/poolex.ex:706`) — it would need to become selective instead of stopping the pool on any linked exit

**Estimated impact:** Significant simplification of worker lifecycle management, easier to maintain and extend. Makes `remove_idle_workers!` trivial to implement.

### Fix `remove_idle_workers!` resource leak

**Current problem (`lib/poolex.ex:573`):**
- `handle_call({:remove_idle_workers, ...})` only removes workers from the idle collection via `IdleWorkers.remove/2` (the `min_pool_size` cap added later doesn't change this)
- Worker processes continue running inside `DynamicSupervisor` — they are inaccessible to the pool but consume resources
- No `stop_worker` call, no demonitor — workers are simply orphaned
- Repeated calls to `remove_idle_workers!` gradually exhaust system resources

**Root cause:**
- Can't unmonitor by pid (only by reference) — see monitoring refactoring above
- Without `Process.unlink`, stopping the worker would trigger an unwanted EXIT/DOWN handling

**Proposed fix:**
- After the `Process.link` refactoring: call `Process.unlink(worker_pid)` then `DynamicSupervisor.terminate_child` for each removed worker
- Before the refactoring (quick fix): add a reverse map `%{pid() => reference()}` to state for O(1) pid→reference lookup, then demonitor + stop each removed worker

### Replace per-acquire spawn monitor with `Process.monitor` in the pool

**Current problem (`lib/poolex.ex:802`):**
`start_manual_monitor/3` spawns a dedicated process for every manual acquisition just to watch the caller and cast `{:stop_worker, W}` if it dies. Since `run/3` is built on `acquire/release`, **every single checkout** pays for this extra process (plus a `Process.exit(_, :kill)` on release). The pool **already** traps exits and handles `{:DOWN, ...}` messages, so this extra process is pure ceremony — and it's the source of the `:stop_worker` race condition above.

**Proposed fix:**
- On `register_manual_acquisition`: `ref = Process.monitor(caller_pid)`; store `%{manual_acquisitions => %{ref => worker_pid, worker_pid => ref}}` (or a bidirectional map).
- On `release_manual_worker`: `Process.demonitor(ref, [:flush])` and clean up.
- In `handle_info({:DOWN, ref, ...})`: look up the worker, stop it, release or replace as usual.
- Drop `start_manual_monitor/3`, `:cleanup_manual_monitor`, `:stop_worker` casts entirely.

Eliminates the race condition, removes a whole layer of processes, reduces mailbox churn.

### Skip `cancel_waiting` cast on successful checkout

**Current problem (`lib/poolex.ex:306`):**

The `after` block in `get_idle_worker/2` casts `{:cancel_waiting, ref}` on **every** call, including successful checkouts. On success the caller is guaranteed not to be in the waiting queue (it was either replied to directly or popped before the reply), so the pool does a useless O(n) `:queue.filter` pass per checkout.

**Proposed fix:**
Move the cast from the `after` block into the timeout `catch` branch. Non-timeout exits mean the pool itself is down, so no cleanup is needed there either.

### Stop always-on retry ticker

**Current problem (`lib/poolex.ex:819`):**

`schedule_retry_failed_workers/1` reschedules `:retry_failed_workers` every `failed_workers_retry_interval` ms forever. The handler (`lib/poolex.ex:678`) already skips the retry work when `failed_to_start_workers_count == 0`, but the message itself still fires: each pool generates a constant background message stream (~1 Hz by default) that is almost always a no-op.

**Proposed fix:**
- Remove the unconditional reschedule from `handle_continue/2` and the tail of `handle_info(:retry_failed_workers, ...)`.
- Schedule a single retry message at the moment `failed_to_start_workers_count` transitions from 0 to positive inside `start_worker/1`.
- Inside `handle_info(:retry_failed_workers, state)`: after running `retry_failed_workers/1`, schedule another run only if `failed_to_start_workers_count > 0`.

### Lighter-weight snapshot for metrics

**Current problem (`lib/poolex/private/metrics.ex:13`):**

`dispatch_pool_size_metrics/1` calls the full `DebugInfo.get_debug_info/1` every second (when metrics are enabled). That function itself is documented as "Avoid using this function in production" and walks every collection via `to_list/1`.

It is also fragile under load: `get_debug_info/1` is a `GenServer.call` with the default 5-second timeout. If the pool's mailbox is backlogged for more than 5 seconds (a checkout storm — exactly when you want metrics), the call exits, `telemetry_poller` catches the exit and **permanently removes the misbehaving measurement** — pool metrics silently stop until the pool restarts. Additionally, the poller is started via `start_link` from the pool process, so an unexpected poller crash stops the whole pool through the catch-all `{:EXIT, _pid, reason}` clause (`lib/poolex.ex:706`).

**Proposed fix:**
- Introduce a cheap `:get_pool_size_snapshot` `handle_call` that returns just the counts (`idle`, `busy`, `overflow`).
- Use it from the telemetry poller; leave `get_debug_info` for true introspection use cases.
- Consider starting the poller unlinked (or under the pool's supervisor) so metrics failures can't take the pool down.

### Thread `Parsed.t()` through `handle_continue` instead of raw `opts`

**Current problem (`lib/poolex.ex:370`, `lib/poolex/private/metrics.ex:35-52`):**

`init/1` parses options into a `Parsed` struct, builds `state`, then forwards the **raw** `opts` via `{:continue, opts}`. `Metrics.start_poller/1` then reparses the options (`parse_pool_id/1` is even called twice — in `start_poller/1` and in `collect_measurements/1`).

**Proposed fix:**
- Pass parsed options (or a minimal metrics config struct) through `handle_continue`.
- Delete `parse_pool_id/1` calls from the metrics module; the pool already knows its id.

### Extract "distribute worker to idle or waiting" helper

**Current problem (`lib/poolex.ex:559-567` and `838-848`):**

Identical 10-line block appears in `handle_call({:add_idle_workers, ...})` and `retry_failed_workers/1`:

```elixir
Enum.reduce(workers, state, fn worker, acc_state ->
  if WaitingCallers.empty?(acc_state) do
    IdleWorkers.add(acc_state, worker)
  else
    acc_state
    |> BusyWorkers.add(worker)
    |> provide_worker_to_waiting_caller(worker)
  end
end)
```

**Proposed fix:**
Extract as `defp distribute_workers(state, workers)` (or `place_worker/2` for a single worker).

### Extract collection-module boilerplate

**Current problem:**

`Poolex.Private.IdleWorkers`, `BusyWorkers`, `IdleOverflowedWorkers`, `WaitingCallers` together are ~250 lines of the same shape: unpack `impl` + `state` from `State`, call `impl.fn(state, args)`, stash new state back.

**Proposed fix:**
Either (a) a `use Poolex.Private.Collection, key: :idle_workers` macro that generates the wrappers, or (b) a single small helper `apply_to/3` that handles pack/unpack for any collection key.

## Readability

### Split `poolex.ex` (~850 lines) into focused modules

The main module mixes the public API, option parsing glue, worker lifecycle, checkout/release logic, manual acquisition, retry, and debug/metrics plumbing. Extracting e.g. `Poolex.Private.Checkout`, `Poolex.Private.Release`, `Poolex.Private.WorkerLifecycle` would shrink the main module to a thin facade + GenServer callbacks.

### Break up `handle_call({:get_idle_worker, ...})`

The four-branch `cond` (`lib/poolex.ex:465-509`) spans ~45 lines with inline state mutation. Splitting each branch into a named private function (`provide_overflowed/1`, `provide_idle/1`, `try_spawn_overflow/2`, `enqueue_caller/3`) reads much better.

### Drop redundant `:: :ok | no_return()`

`add_idle_workers!/2` (`lib/poolex.ex:313`) and `remove_idle_workers!/2` (`lib/poolex.ex:328`) declare `:ok | no_return()`. `no_return()` is implicit for any function that can raise. Keep `:: :ok`.

### Replace `+ 10` timer hack with cancelable timer refs

`release_overflowed_worker/2` (`lib/poolex.ex:728`) schedules `{:delayed_stop_worker, worker}` with `worker_shutdown_delay + 10` ms and then relies on `expired?/2` (`idle_overflowed_workers.ex:87`) doing a monotonic-time comparison. If we instead stored the timer reference per worker and called `Process.cancel_timer/1` on pop, we could drop both the `+ 10` fudge and the `expired?` helper entirely.

## Minor

### Dead clause in `Poolex.Workers.Impl.List.pop/1`

```elixir
# lib/poolex/workers/impl/list.ex:49
def pop([worker]), do: {worker, []}
def pop([worker | rest]), do: {worker, rest}
```

The single-element clause is fully covered by the following one. Remove it (or keep intentionally and add a comment why).

### Inconsistent `:empty` handling between callers/workers queues

`Callers.Impl.ErlangQueue.pop/1` (`lib/poolex/callers/impl/erlang_queue.ex:26`) uses `_ -> :empty`, while `Workers.Impl.ErlangQueue.pop/1` (`lib/poolex/workers/impl/erlang_queue.ex:51`) uses the explicit `{:empty, _state}` pattern. Pick one for consistency.

### `DebugInfo` "avoid in production" vs Metrics usage

`DebugInfo.get_debug_info/1` (`lib/poolex/private/debug_info.ex:57`) is documented as "Avoid using this function in production", yet `Metrics.dispatch_pool_size_metrics/1` calls it every second. Either soften the doc, or introduce the lightweight snapshot described above.

### `expired?/2` off-by-one

Comparison is `> timeout` (`lib/poolex/private/idle_overflowed_workers.ex:90`); combined with `worker_shutdown_delay + 10` it is not visibly broken today, but swapping to `>=` or moving to cancelable timer refs (see above) makes the intent clearer.
