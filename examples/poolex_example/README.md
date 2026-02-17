# PoolexExample

Test code example.

## Launch

```shell
mix deps.get

iex -S mix

iex> PoolexExample.Test.start
```

## Pool metrics logs

You can turn on/off metric logs by using `PoolexExample.MetricsHandler.turn_on_logs/0` and `PoolexExample.MetricsHandler.turn_off_logs/0`.

Example of log:

```shell
[Pool: worker_pool]:
- Idle workers: 5
- Busy workers: 0
- Overflowed: 0
```

## Comparing run/3 vs acquire/release

The example application demonstrates two approaches to using Poolex workers:

### Simple examples

Basic usage of each approach:

```shell
iex -S mix

# Automatic approach - worker lifecycle managed by run/3
iex> PoolexExample.RunDemo.simple()

# Manual approach - explicit acquire/release control
iex> PoolexExample.AcquireDemo.simple()
```

### Multiple workers

Shows the key difference between approaches:

```shell
# run/3: Operations execute sequentially (~2000ms)
iex> PoolexExample.RunDemo.multiple_workers()

# acquire/release: Operations execute in parallel (~1000ms)
iex> PoolexExample.AcquireDemo.multiple_workers()
```

### When to use each approach

**Use `Poolex.run/3` when:**
- You need a single worker for one operation
- You want automatic worker lifecycle management
- Simplicity and safety are priorities

**Use `Poolex.acquire/release` when:**
- You need multiple workers simultaneously
- You need explicit control over worker lifecycle
- You're coordinating operations across multiple workers
