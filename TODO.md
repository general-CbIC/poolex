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
