# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this example application.

## Project Overview

**PoolexExample** is a demonstration application located inside the Poolex library repository (`poolex/examples/poolex_example`). This application serves two primary purposes:

1. **Usage Examples**: Demonstrates how to integrate and use the Poolex library in a real Elixir application
2. **Manual Testing**: Provides a live environment to test new Poolex features and verify functionality in practice

This is **NOT** a standalone application - it exists within the parent Poolex repository and uses the library via a local path dependency (`{:poolex, path: "../.."}`).

## Application Structure

```
poolex_example/
├── lib/
│   ├── poolex_example.ex              # Main module
│   └── poolex_example/
│       ├── application.ex              # Application startup, pool configuration
│       ├── worker.ex                   # Example worker (calculates square roots)
│       ├── test.ex                     # Demo script to test the pool
│       └── metrics_handler.ex          # Telemetry event handler
└── test/
    └── poolex_example_test.exs         # Basic tests
```

## Key Components

### Application (`application.ex`)

Starts a Poolex worker pool with example configuration:
- **Worker module**: `PoolexExample.Worker`
- **Base workers**: 5
- **Max overflow**: 2
- **Metrics enabled**: `pool_size_metrics: true`
- **Telemetry handler**: Attached to `[:poolex, :metrics, :pool_size]` events

### Worker (`worker.ex`)

Simple GenServer that demonstrates worker functionality:
- Calculates square root of a number
- Uses `Process.sleep(1_000)` to simulate work
- Prints process PID to show which worker handles each request

### Test Module (`test.ex`)

Interactive demonstration:
- Spawns 20 concurrent tasks
- Each task uses `Poolex.run/3` to checkout a worker
- Shows pool overflow behavior (5 base + 2 overflow vs 20 requests)
- Uses 60-second timeout for operations

### Metrics Handler (`metrics_handler.ex`)

Displays pool metrics in real-time:
- Idle workers count
- Busy workers count
- Overflow status

## Development Commands

### Running the Example

```shell
# From poolex_example directory
mix deps.get      # Install dependencies (includes poolex from parent)
iex -S mix        # Start interactive session

# In IEx:
iex> PoolexExample.Test.start   # Run the demo
```

### Testing

```shell
mix test          # Run example app tests
```

### Code Quality

```shell
mix format        # Format code
mix dialyzer      # Type checking (if configured)
```

## Relationship to Parent Repository

- **Parent**: `poolex` library (two directories up: `../..`)
- **Purpose**: Example/testing environment for Poolex development
- **Dependency**: Uses `{:poolex, path: "../.."}` in `mix.exs`
- **Git**: Committed as part of the Poolex repository
- **Workflow**: When testing new Poolex features, modify parent library code, then test here

## Development Workflow

1. Make changes to Poolex library (`../../lib/poolex/...`)
2. Changes are immediately available in this example app (path dependency)
3. Run `iex -S mix` and test manually with `PoolexExample.Test.start`
4. Observe metrics output to verify behavior
5. Add new example code here if needed to demonstrate new features

## Current Branch Context

When working on a feature branch (e.g., `feature/use-acquire-and-release-at-poolex-example`):
- The branch likely adds example code demonstrating a new Poolex feature
- Update `application.ex`, `worker.ex`, or `test.ex` to showcase the feature
- The example should be simple and clear for documentation purposes

## Tips for Claude

- **Always remember**: This is an example app, not the library itself
- **Library code**: Located at `../../lib/poolex/`
- **Testing approach**: Interactive testing via IEx, not just unit tests
- **Keep it simple**: Examples should be clear and educational
- **Don't over-engineer**: This is for demonstration, not production use
