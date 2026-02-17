# Acquire/Release Demo Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add demonstration examples to poolex_example that compare run/3 vs acquire/release approaches

**Architecture:** Create two new demo modules (RunDemo and AcquireDemo) that showcase both simple and complex usage patterns. Enhance the existing Worker module to support multiple operation types. Focus on clear, educational output in English.

**Tech Stack:** Elixir, Poolex library, GenServer, Task for parallel execution

---

## Task 1: Enhance Worker with Power Operation

**Files:**
- Modify: `examples/poolex_example/lib/poolex_example/worker.ex`

**Step 1: Read the current worker implementation**

```bash
cat examples/poolex_example/lib/poolex_example/worker.ex
```

Expected: See existing `handle_call` for `:square_root`

**Step 2: Add power operation handler**

Add after the existing `handle_call` for `:square_root`:

```elixir
def handle_call({:power, base, exponent}, _from, state) do
  IO.puts("process #{inspect(self())} calculating power #{base}^#{exponent}")
  Process.sleep(1_000)
  result = :math.pow(base, exponent) |> trunc()
  {:reply, result, state}
end
```

**Step 3: Verify syntax**

```bash
cd examples/poolex_example
mix compile
```

Expected: Compilation successful

**Step 4: Test the new operation in IEx**

```bash
iex -S mix
```

```elixir
{:ok, worker} = Poolex.acquire(:worker_pool)
GenServer.call(worker, {:power, 2, 10})
Poolex.release(:worker_pool, worker)
```

Expected: Output shows "calculating power 2^10" and returns 1024

**Step 5: Commit**

```bash
git add examples/poolex_example/lib/poolex_example/worker.ex
git commit -m "feat(example): add power operation to worker

Add :power operation handler to demonstrate multiple operation types
in acquire/release examples.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Create RunDemo Module

**Files:**
- Create: `examples/poolex_example/lib/poolex_example/run_demo.ex`

**Step 1: Create module skeleton**

```elixir
defmodule PoolexExample.RunDemo do
  @moduledoc """
  Demonstrates the automatic approach using Poolex.run/3.

  This module shows how run/3 automatically manages worker lifecycle
  but has limitations when you need multiple workers simultaneously.
  """

  @pool_id :worker_pool
  @timeout 60_000

  @doc """
  Simple example: one operation with run/3.

  Shows basic usage where the worker is automatically returned
  after the function completes.
  """
  def simple do
    IO.puts("\n[RunDemo.simple] Calculating sqrt(16) with run/3...")

    start_time = System.monotonic_time(:millisecond)

    result = Poolex.run(
      @pool_id,
      fn worker_pid ->
        GenServer.call(worker_pid, {:square_root, 16})
      end,
      checkout_timeout: @timeout
    )

    end_time = System.monotonic_time(:millisecond)

    IO.puts("Result: #{result}")
    IO.puts("Time: #{end_time - start_time}ms\n")

    result
  end

  @doc """
  Multiple workers example: shows limitation of run/3.

  With run/3, you cannot acquire multiple workers simultaneously
  from the same process (deadlock risk). Operations must be sequential.
  """
  def multiple_workers do
    IO.puts("\n[RunDemo.multiple_workers] With run/3, operations execute sequentially:")

    start_time = System.monotonic_time(:millisecond)

    # First operation
    IO.puts("\nStep 1: sqrt(25)...")
    result1 = Poolex.run(
      @pool_id,
      fn worker_pid ->
        GenServer.call(worker_pid, {:square_root, 25})
      end,
      checkout_timeout: @timeout
    )
    IO.puts("Result: #{result1}")

    # Second operation (must wait for first to complete)
    IO.puts("\nStep 2: power(2, 10)...")
    result2 = Poolex.run(
      @pool_id,
      fn worker_pid ->
        GenServer.call(worker_pid, {:power, 2, 10})
      end,
      checkout_timeout: @timeout
    )
    IO.puts("Result: #{result2}")

    end_time = System.monotonic_time(:millisecond)

    IO.puts("\nTotal time: #{end_time - start_time}ms")
    IO.puts("Note: For parallel use of multiple workers, use acquire/release!\n")

    {result1, result2}
  end
end
```

**Step 2: Verify compilation**

```bash
cd examples/poolex_example
mix compile
```

Expected: Compilation successful

**Step 3: Test simple/0 in IEx**

```bash
iex -S mix
```

```elixir
PoolexExample.RunDemo.simple()
```

Expected:
- Output shows "[RunDemo.simple] Calculating sqrt(16) with run/3..."
- Worker output shows "calculating square root of 16"
- Result: 4.0
- Time: ~1000ms

**Step 4: Test multiple_workers/0 in IEx**

```elixir
PoolexExample.RunDemo.multiple_workers()
```

Expected:
- Shows sequential execution (Step 1, then Step 2)
- Total time: ~2000ms
- Shows note about using acquire/release

**Step 5: Commit**

```bash
git add examples/poolex_example/lib/poolex_example/run_demo.ex
git commit -m "feat(example): add RunDemo module

Demonstrate Poolex.run/3 approach with simple and multiple workers
examples. Shows automatic lifecycle management and sequential
execution limitation.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Create AcquireDemo Module

**Files:**
- Create: `examples/poolex_example/lib/poolex_example/acquire_demo.ex`

**Step 1: Create module skeleton**

```elixir
defmodule PoolexExample.AcquireDemo do
  @moduledoc """
  Demonstrates manual worker management using Poolex.acquire/2 and release/2.

  This module shows how acquire/release gives you explicit control over
  worker lifecycle and enables using multiple workers simultaneously.
  """

  @pool_id :worker_pool
  @timeout 60_000

  @doc """
  Simple example: one operation with acquire/release.

  Shows manual worker lifecycle management where you explicitly
  acquire and release the worker.
  """
  def simple do
    IO.puts("\n[AcquireDemo.simple] Acquiring worker manually...")

    start_time = System.monotonic_time(:millisecond)

    # Acquire worker
    {:ok, worker_pid} = Poolex.acquire(@pool_id, checkout_timeout: @timeout)
    IO.puts("Acquired worker: #{inspect(worker_pid)}")

    # Use worker
    result = GenServer.call(worker_pid, {:square_root, 16})
    IO.puts("Result: #{result}")

    # Release worker
    IO.puts("Releasing worker #{inspect(worker_pid)}...")
    :ok = Poolex.release(@pool_id, worker_pid)
    IO.puts("Released!")

    end_time = System.monotonic_time(:millisecond)
    IO.puts("Time: #{end_time - start_time}ms\n")

    result
  end

  @doc """
  Multiple workers example: shows advantage of acquire/release.

  With acquire/release, you can hold multiple workers simultaneously
  and execute operations in parallel.
  """
  def multiple_workers do
    IO.puts("\n[AcquireDemo.multiple_workers] Acquiring two workers simultaneously...")

    start_time = System.monotonic_time(:millisecond)

    # Acquire two workers
    {:ok, worker1} = Poolex.acquire(@pool_id, checkout_timeout: @timeout)
    IO.puts("Acquired worker1: #{inspect(worker1)}")

    {:ok, worker2} = Poolex.acquire(@pool_id, checkout_timeout: @timeout)
    IO.puts("Acquired worker2: #{inspect(worker2)}")

    IO.puts("\nExecuting operations in parallel...")

    # Execute operations in parallel using Task
    task1 = Task.async(fn ->
      GenServer.call(worker1, {:square_root, 25})
    end)

    task2 = Task.async(fn ->
      GenServer.call(worker2, {:power, 2, 10})
    end)

    # Wait for results
    result1 = Task.await(task1, @timeout)
    result2 = Task.await(task2, @timeout)

    IO.puts("\nResults:")
    IO.puts("  - sqrt(25) = #{result1}")
    IO.puts("  - power(2, 10) = #{result2}")

    # Release both workers
    IO.puts("\nReleasing workers...")
    :ok = Poolex.release(@pool_id, worker1)
    :ok = Poolex.release(@pool_id, worker2)
    IO.puts("Released worker1 and worker2!")

    end_time = System.monotonic_time(:millisecond)
    IO.puts("\nTotal time: #{end_time - start_time}ms (parallel instead of ~2000ms!)\n")

    {result1, result2}
  end
end
```

**Step 2: Verify compilation**

```bash
cd examples/poolex_example
mix compile
```

Expected: Compilation successful

**Step 3: Test simple/0 in IEx**

```bash
iex -S mix
```

```elixir
PoolexExample.AcquireDemo.simple()
```

Expected:
- Output shows "[AcquireDemo.simple] Acquiring worker manually..."
- Shows acquired worker PID
- Worker output shows "calculating square root of 16"
- Shows "Releasing worker..." and "Released!"
- Result: 4.0
- Time: ~1000ms

**Step 4: Test multiple_workers/0 in IEx**

```elixir
PoolexExample.AcquireDemo.multiple_workers()
```

Expected:
- Shows acquiring two workers
- Shows "Executing operations in parallel..."
- Both worker outputs appear (may be interleaved)
- Shows results for both operations
- Total time: ~1000ms (parallel execution!)
- Shows "Released worker1 and worker2!"

**Step 5: Commit**

```bash
git add examples/poolex_example/lib/poolex_example/acquire_demo.ex
git commit -m "feat(example): add AcquireDemo module

Demonstrate Poolex.acquire/release approach with simple and multiple
workers examples. Shows manual lifecycle control and parallel execution
capability.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Update README with Examples

**Files:**
- Modify: `examples/poolex_example/README.md`

**Step 1: Read current README**

```bash
cat examples/poolex_example/README.md
```

**Step 2: Add comparison section**

Add after the existing content:

```markdown

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
```

**Step 3: Verify markdown formatting**

```bash
cd examples/poolex_example
cat README.md
```

Expected: Clean markdown with proper code blocks

**Step 4: Commit**

```bash
git add examples/poolex_example/README.md
git commit -m "docs(example): add run/3 vs acquire/release comparison

Document the new demo modules and explain when to use each approach
for acquiring workers from the pool.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Final Integration Testing

**Files:**
- N/A (testing only)

**Step 1: Clean rebuild**

```bash
cd examples/poolex_example
mix clean
mix deps.get
mix compile
```

Expected: Clean compilation with no warnings

**Step 2: Run all four demo functions**

```bash
iex -S mix
```

```elixir
# Test all four functions in sequence
PoolexExample.RunDemo.simple()
PoolexExample.AcquireDemo.simple()
PoolexExample.RunDemo.multiple_workers()
PoolexExample.AcquireDemo.multiple_workers()
```

Expected:
- All four functions execute successfully
- Output is clear and in English
- Timing differences are visible (~2000ms sequential vs ~1000ms parallel)
- No errors or warnings

**Step 3: Verify pool metrics**

Observe the metrics output during execution to verify:
- Workers move between idle and busy states correctly
- Pool returns to initial state after each demo
- No worker leaks

**Step 4: Test error case (optional verification)**

```elixir
# Verify acquire timeout works
{:ok, _} = Poolex.acquire(:worker_pool)
{:ok, _} = Poolex.acquire(:worker_pool)
{:ok, _} = Poolex.acquire(:worker_pool)
{:ok, _} = Poolex.acquire(:worker_pool)
{:ok, _} = Poolex.acquire(:worker_pool)
{:ok, _} = Poolex.acquire(:worker_pool)  # 5 base + 2 overflow = 7 max
{:ok, _} = Poolex.acquire(:worker_pool)

# This should timeout
Poolex.acquire(:worker_pool, checkout_timeout: 1000)
```

Expected: `{:error, :checkout_timeout}` after 1 second

**Step 5: Document completion**

Create a summary of what was implemented:

```bash
git log --oneline -5
```

Expected: See all 4 commits for this feature

---

## Success Criteria

- ✅ Worker supports both `:square_root` and `:power` operations
- ✅ `RunDemo.simple/0` demonstrates basic `run/3` usage
- ✅ `RunDemo.multiple_workers/0` shows sequential execution
- ✅ `AcquireDemo.simple/0` demonstrates basic `acquire/release` usage
- ✅ `AcquireDemo.multiple_workers/0` shows parallel execution
- ✅ README documents both approaches and when to use each
- ✅ All output is in English
- ✅ All demos work correctly in IEx
- ✅ Code follows Elixir conventions
- ✅ Commits are well-structured with co-authorship

## Notes

- No unit tests needed for demo modules (they are demonstrations, not library code)
- Manual testing in IEx is the validation approach
- Keep examples simple and educational
- Focus on happy path (no error handling needed in demos)
