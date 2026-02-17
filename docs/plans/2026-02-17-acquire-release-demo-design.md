# Acquire/Release Demo Design

**Date:** 2026-02-17
**Status:** Approved
**Context:** Feature branch `feature/use-acquire-and-release-at-poolex-example`

## Overview

Add demonstration examples to `poolex_example` application that showcase the new `acquire/release` functionality by comparing it with the existing `run/3` approach.

## Goals

1. Help users understand the difference between `run/3` and `acquire/release`
2. Show when to use each approach
3. Demonstrate both simple and complex scenarios
4. Focus on happy cases (no error handling or crash scenarios)

## Important Notes

- **Communication language:** Russian (for design discussions)
- **Code output language:** English (for international audience)
- All console output, comments in output, and messages should be in English

## Architecture

### Module Structure

```
lib/poolex_example/
├── application.ex          # Existing - pool startup
├── worker.ex               # Enhanced - add :power operation
├── test.ex                 # Existing - keep as-is
├── run_demo.ex             # NEW - run/3 examples
└── acquire_demo.ex         # NEW - acquire/release examples
```

### New Modules

Both new modules will contain:
- `simple/0` - Simple single-operation example
- `multiple_workers/0` - Complex example with multiple workers simultaneously
- Private helper functions for demonstration

## Component Design

### 1. Worker Enhancement

**File:** `lib/poolex_example/worker.ex`

Add a second operation to demonstrate multiple workers:

```elixir
def handle_call({:power, base, exponent}, _from, state) do
  IO.puts("process #{inspect(self())} calculating power #{base}^#{exponent}")
  Process.sleep(1_000)
  result = :math.pow(base, exponent) |> trunc()
  {:reply, result, state}
end
```

**Rationale:** Having two different operations makes the multiple workers demo more realistic and easier to understand.

### 2. RunDemo Module

**File:** `lib/poolex_example/run_demo.ex`

Demonstrates the automatic approach with `Poolex.run/3`.

#### Function: `simple/0`

**Purpose:** Show basic `run/3` usage

**Behavior:**
- Takes a worker from the pool
- Executes one operation (square root)
- Worker automatically returns after function completes
- Prints result and execution time

**Expected Output (English):**
```
[RunDemo.simple] Calculating sqrt(16) with run/3...
[Worker PID<0.234.0>] calculating square root of 16
Result: 4.0
Time: 1002ms
```

#### Function: `multiple_workers/0`

**Purpose:** Show **limitation** of `run/3` approach

**Behavior:**
- Attempts to perform two operations requiring two workers
- Problem: Cannot call second `run/3` inside first callback (deadlock risk)
- Solution: Executes operations sequentially (one after another)
- Prints note about using acquire/release for parallel work

**Expected Output (English):**
```
[RunDemo.multiple_workers] With run/3, operations execute sequentially:
Step 1: sqrt(25)...
[Worker PID<0.234.0>] calculating square root of 25
Result: 5.0

Step 2: power(2, 10)...
[Worker PID<0.235.0>] calculating power 2^10
Result: 1024

Total time: 2004ms
Note: For parallel use of multiple workers, use acquire/release!
```

### 3. AcquireDemo Module

**File:** `lib/poolex_example/acquire_demo.ex`

Demonstrates manual control with `acquire/release`.

#### Function: `simple/0`

**Purpose:** Show basic `acquire/release` usage

**Behavior:**
- Manually acquires worker via `Poolex.acquire/2`
- Executes one operation
- **Explicitly** releases worker via `Poolex.release/2`
- Shows programmer controls worker lifecycle

**Expected Output (English):**
```
[AcquireDemo.simple] Acquiring worker manually...
Acquired worker: PID<0.234.0>
[Worker PID<0.234.0>] calculating square root of 16
Result: 4.0
Releasing worker PID<0.234.0>...
Released!
Time: 1002ms
```

#### Function: `multiple_workers/0`

**Purpose:** Show **advantage** of `acquire/release` approach

**Behavior:**
- Acquires **two workers simultaneously** (impossible with `run/3`)
- Executes operations in parallel with both workers
- Uses `Task.async` for parallel execution
- Releases both workers after completion
- Demonstrates holding multiple workers at once

**Expected Output (English):**
```
[AcquireDemo.multiple_workers] Acquiring two workers simultaneously...
Acquired worker1: PID<0.234.0>
Acquired worker2: PID<0.235.0>

Executing operations in parallel...
[Worker PID<0.234.0>] calculating square root of 25
[Worker PID<0.235.0>] calculating power 2^10

Results:
  - sqrt(25) = 5.0
  - power(2, 10) = 1024

Releasing workers...
Released worker1 and worker2!

Total time: 1003ms (parallel instead of 2004ms!)
```

## Documentation Updates

### README.md Update

Add new section comparing approaches:

```markdown
## Comparing run/3 vs acquire/release

### Simple examples
iex> PoolexExample.RunDemo.simple()
iex> PoolexExample.AcquireDemo.simple()

### Multiple workers
iex> PoolexExample.RunDemo.multiple_workers()
iex> PoolexExample.AcquireDemo.multiple_workers()
```

## Key Learnings for Users

The examples will demonstrate:

- **`run/3`**: Simple and safe for single operations, automatic management
- **`acquire/release`**: Flexible for complex scenarios, manual control, can hold multiple workers

## Out of Scope

- Error handling demonstrations
- Timeout scenarios
- Auto-cleanup on crash (this is well-covered in tests)
- Metrics/telemetry integration (already shown in existing code)

## Implementation Order

1. Enhance `worker.ex` with `:power` operation
2. Create `run_demo.ex` with both functions
3. Create `acquire_demo.ex` with both functions
4. Update `README.md` with new examples
5. Manual testing in `iex -S mix`

## Success Criteria

- All four demo functions work correctly in IEx
- Output is clear and educational (in English)
- Examples clearly show when to use each approach
- Code is simple and easy to understand
