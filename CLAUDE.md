# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Poolex is an Elixir library for managing pools of workers, inspired by poolboy. It provides a GenServer-based worker pool with configurable overflow workers, delayed shutdown, and pluggable implementations for managing worker and caller collections.

## Development Commands

### Core Development Tasks
- `mix deps.get` - Install dependencies
- `mix check` - Run all code analysis & testing tools (includes tests, dialyzer, credo, format check)
- `mix test` - Run tests only
- `mix format` - Format code
- `mix dialyzer` - Run Dialyzer type checking
- `mix credo` - Run code analysis

### Testing
- `mix test` - Run all tests
- `mix test --cover` - Run tests with coverage
- `mix test test/poolex_test.exs` - Run specific test file
- `mix test --only focus` - Run only focused tests (tagged with @tag :focus)

### Documentation
- `mix docs` - Generate documentation
- `mix hex.docs open` - Open generated docs in browser

## Architecture

### Core Components

The main pool GenServer (`Poolex`) manages several internal components:

- **State Management**: `Poolex.Private.State` - Core state structure containing pool configuration and runtime state
- **Worker Collections**: Pluggable implementations for managing different types of workers:
  - `idle_workers` - Available workers ready for checkout
  - `busy_workers` - Workers currently in use
  - `idle_overflowed_workers` - Overflow workers with delayed shutdown
- **Caller Management**: `waiting_callers` - Queue of processes waiting for workers
- **Monitoring**: `Poolex.Private.Monitoring` - Tracks worker and caller processes
- **Metrics**: `Poolex.Private.Metrics` - Telemetry integration for pool metrics

### Worker Lifecycle

1. Workers are started via `DynamicSupervisor` under `Poolex.Private.Supervisor`
2. Idle workers are stored in configurable collections (List or ErlangQueue implementations)
3. When requested, workers move from idle → busy state
4. After use, workers either return to idle or are shut down (if overflow)
5. Failed workers are automatically restarted with configurable retry intervals

### Pluggable Implementations

The library uses behaviour-based implementations for:
- **Workers**: `Poolex.Workers.Behaviour` - How to store/retrieve worker PIDs
- **Callers**: `Poolex.Callers.Behaviour` - How to queue waiting callers

Built-in implementations:
- `Poolex.Workers.Impl.List` - Simple list-based storage
- `Poolex.Workers.Impl.ErlangQueue` - Erlang queue-based storage  
- `Poolex.Callers.Impl.ErlangQueue` - Erlang queue for caller management

### Key Features

- **Overflow Workers**: Temporary workers beyond the base pool size
- **Worker Shutdown Delay**: Configurable delay before stopping overflow workers
- **Failed Worker Retry**: Automatic retry of failed worker initialization
- **Pool Metrics**: Telemetry integration for monitoring pool state
- **Process Monitoring**: Automatic cleanup when workers or callers crash

## Configuration Options

Key pool configuration (see `Poolex.poolex_option()` type):
- `worker_module` - Module implementing the worker (required)
- `workers_count` - Base number of workers (required)
- `max_overflow` - Additional workers allowed beyond base count
- `worker_shutdown_delay` - Delay before stopping overflow workers
- `pool_id` - Identifier for the pool (defaults to worker_module)
- `worker_args` - Arguments passed to worker start function
- `*_impl` options - Custom implementations for worker/caller management

## Testing Patterns

- Test files are in `test/` directory
- Test support modules in `test/support/`
- Use `Poolex.start_link/1` to start pools in tests
- Common test pattern: start pool → call `Poolex.run/3` → verify behavior
- Use `Process.sleep/1` for timing-sensitive tests
- Registry-based naming for test isolation

## Git Workflow

- Uses git-flow: `main` for releases, `develop` for development
- Feature branches: `git flow feature start <feature_name>`
- Always rebase, never merge when integrating upstream changes
- Run `mix check` before committing

## Requirements

- Elixir >= 1.17, Erlang/OTP >= 25
- Use `asdf` for version management (see `.tool-versions`)