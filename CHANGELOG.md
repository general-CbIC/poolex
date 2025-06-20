# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Fixed overflow worker expiration timing to use `System.monotonic_time/1` instead of `Time.utc_now/0`. This prevents incorrect worker expiration when system clock changes occur (e.g., from NTP adjustments or timezone changes).

## [1.4.0] - 2025-06-19

### Added

- New option `worker_shutdown_delay` for delayed shutdown of overflow workers. Allows to specify a delay (in ms) before terminating overflow workers after they are released. See the new guide for details.
- New option `idle_overflowed_workers_impl` for customizing the implementation of idle overflowed workers storage.
- Strong runtime pool init options validation.

### Changed

#### Breaking changes

- Function `get_debug_info/1` moved from `Poolex` to `Poolex.Private.DebugInfo` (according to the [issue](https://github.com/general-CbIC/poolex/issues/140)).
- Function `Poolex.get_state/1` was removed.
- Minimum required version of Elixir bumped to `~> 1.17` and Erlang/OTP to `~> 25`.

## [1.3.0] - 2025-04-26

### Added

- Added caching of the dependencies on CI (compilation speed up).
- Added a new option `failed_workers_retry_interval` to the pool configuration. This option configures an interval in milliseconds between retry attempts for workers which failed to start. The value is `1 second` by default. Example:

  ```elixir
  Poolex.start_link(
    worker_module: SomeUnstableWorker,
    workers_count: 5,
    failed_workers_retry_interval: 3_000
  )
  ```

### Changed

- Due to the deprecation of support ubuntu 20.04 on GitHub Actions (read more [here](https://github.com/actions/runner-images/issues/11101)), bumped minimum required versions of Elixir to `~> 1.11` and Erlang/OTP to `~> 24`.

### Fixed

- Fixed the `MatchError` on pool starting error that occurs with errors on the launch of workers (read more in [issue](https://github.com/general-CbIC/poolex/issues/113)).

## [1.2.1] - 2025-04-06

### Fixed

- Now the `busy_worker` will be restarted after the `caller's` death. Read more in [issue](https://github.com/general-CbIC/poolex/issues/114).
- The function `add_idle_workers!/2` now provides new workers to waiting callers if they exist. Read more in [issue](https://github.com/general-CbIC/poolex/issues/122).

## [1.2.0] - 2025-01-07

### Added

- Added Elixir 1.18.* support to CI.

### Changed

- Refactored tests with new [ExUnit parameterize feature](https://hexdocs.pm/ex_unit/1.18.0/ExUnit.Case.html#module-parameterized-tests).
- `:pool_id` is not required init option anymore. For now it is equal to `worker_module` option value.

### Fixed

- Functions `Poolex.add_idle_workers!/2` and `Poolex.remove_idle_workers!/2` now accept any value of type `GenServer.name()` as their first argument, instead of only `atom()`.
- Supressed Supervisor's error logs in tests.
  
## [1.1.0] - 2024-12-08

### Added

- Added [adobe/elixir-styler](https://github.com/adobe/elixir-styler) to project.

### Changed

- Monitoring implementation has been optimized by using a plain map instead of the `Agent` process.
- Refactored `State` struct by adding a list of `@enforced_keys`. ([Details](https://hexdocs.pm/elixir/structs.html#default-values-and-required-keys))
- Poolex processes now have higher priority. ([Details](https://www.erlang.org/doc/apps/erts/erlang.html#process_flag_priority))

### Deprecated

- `Poolex.get_state/1` deprecated in favor of `:sys.get_state/1`.

## [1.0.0] - 2024-09-23

### Changed

- Monitoring implementation now uses `Agent` instead of `:ets`. It's needed to be more flexible in pool naming.
- The `pool_id` can now be any valid `GenServer.name()`. For example, `{:global, :biba}` or `{:via, Registry, {MyRegistry, "boba"}}`.

## [0.10.0] - 2024-08-26

### Added

- Added functions `add_idle_workers!/2` and `remove_idle_workers!/2` for changing count of idle workers in runtime.

### Changed

- Refactored private `start_workers` function. It no longer accepts monitor_id as it already is in the state.
- Updated `telemetry` dependency.

## [0.9.0] - 2024-04-24

### Added

- Added sending of pools size metrics via `telemetry`. [Working with metrics guide](https://hexdocs.pm/poolex/pool-metrics.html)

## [0.8.0] - 2023-08-30

### Changed

#### Breaking changes

- Option `:timeout` renamed to `:checkout_timeout`.
  - Reason: This option configures only the waiting time for `worker` from the pool, not the task's work time. This naming should be more understandable on the call site.

    ```elixir
    # Before
    Poolex.run(:my_awesome_pool, fn worker -> some_work(worker) end, timeout: 10_000)

    # After
    Poolex.run(:my_awesome_pool, fn worker -> some_work(worker) end, checkout_timeout: 10_000)
    ```

- `Poolex.run/3` returns tuple `{:error, :checkout_timeout}` instead of `:all_workers_are_busy`.
  - Reason: It is easier to understand the uniform format of the response from the function: `{:ok, result}` or `{:error, reason}`.
- `Poolex.caller()` type replaced with struct defined in `Poolex.Caller.t()`.
  - Reason: We need to save unique caller references.
- `Poolex.run!/3` was removed in favor of `Poolex.run/3`. The new unified function returns `{:ok, result}` or `{:error, :checkout_timeout}` and not handles runtime errors anymore.
  - Reason: We should not catch errors in the caller process. The caller process itself must choose how to handle exceptions and exit signals.

### Fixed

- Fixed a bug when workers get stuck in `busy` status after checkout timeout.

## [0.7.6] - 2023-08-03

### Fixed

- Fixed a bug with workers stuck in busy status. Added caller monitoring. [PR](https://github.com/general-CbIC/poolex/pull/56)

## [0.7.5] - 2023-07-31

### Fixed

- Fixed a serious bug when working with the `idle_workers` set. Previous version retired.

## [0.7.4] - 2023-07-23 (RETIRED)

### Fixed

- Fixed a bug where a restarted worker was not automatically dispatched to pending callers ([Issue](https://github.com/general-CbIC/poolex/issues/53) / [PR](https://github.com/general-CbIC/poolex/pull/54)).

### Changed

- Upgraded [ex_doc](https://hex.pm/packages/ex_doc) from `0.29.4` to `0.30.3`

## [0.7.3] - 2023-06-21

### Fixed

- Fixed a bug with an incorrect number of running workers when specifying a zero or negative number in the `workers_count` parameter ([PR](https://github.com/general-CbIC/poolex/pull/49)).

## [0.7.2] - 2023-06-11

### Fixed

- Trap exit to shutdown correctly ([PR](https://github.com/general-CbIC/poolex/pull/46)) .

### Changed

- Implementation settings are stored in the pool process state instead of the ETS table. This makes the testing process easier and removes unnecessary entities.

## [0.7.1] - 2023-06-03

### Fixed

- Fixed the shutdown process: stop workers before the pool ([issue](https://github.com/general-CbIC/poolex/issues/44)).

## [0.7.0] - 2023-04-13

### Added

- Added `FIFO` worker's implementation ([About implemetations](https://hexdocs.pm/poolex/workers-and-callers-implementations.html)).

## [0.6.1] - 2023-03-25

### Documentation updates

- Refactored some custom types and added some typedocs.
- Added `diff` syntax highlighting support.
- Updated guides:
  - The pages were merged into a group called `Guides`.
  - Tried to refresh some pages with [cheatmd](https://hexdocs.pm/ex_doc/cheatsheet.html).

## [0.6.0] - 2023-03-09

### Changed

- [INCOMPATIBLE] Changed approach to configuring custom implementations for queues of workers and callers.
  - Reasons: [Avoid application configuration](https://hexdocs.pm/elixir/library-guidelines.html#avoid-application-configuration)
  - Now for the configuration you need to use the initialization parameters instead of `Application` config.

    ```elixir
    # Before
    import Config

    config :poolex,
      callers_impl: SomeCallersImpl,
      busy_workers_impl: SomeBusyWorkersImpl,
      idle_workers_impl: SomeIdleWorkersImpl

    # After
    Poolex.child_spec(
      pool_id: :some_pool,
      worker_module: SomeWorker,
      workers_count: 10,
      waiting_callers_impl: SomeCallersImpl,
      busy_workers_impl: SomeBusyWorkersImpl,
      idle_workers_impl: SomeIdleWorkersImpl
    )
    ```

## [0.5.1] - 2023-03-04

### Added

- [Docs] Simple [migration guide from `:poolboy`](https://hexdocs.pm/poolex/migration-from-poolboy.html)

### Fixed

- [Docs] Fix missing `Poolex.State.t()` on docs generating ([issue](https://github.com/general-CbIC/poolex/issues/32))

## [0.5.0] - 2023-02-24

### Changed

- The default value of the parameter `:worker_start_fun` changed from `:start` to `:start_link`, since the second value is used more often.
- [INCOMPATIBLE] Reworked pool launch functions `start` and `start_link`
  - First argument `pool_id` moved to `poolex_options` under required key `:pool_id`. So the arity of both functions has changed to `1`.

    ```elixir
    # Before
    Poolex.start(:my_pool, worker_module: Agent, workers_count: 5)

    # After
    Poolex.start(pool_id: :my_pool, worker_module: Agent, workers_count: 5)
    ```

  - `child_spec/1` was redefined to support `:pool_id` key in `poolex_options`. Now the pool can be added to the supervisor tree in a more convenient way.

    ```elixir
    children = [
        Poolex.child_spec(pool_id: :worker_pool_1, worker_module: SomeWorker, workers_count: 5),
        # or in another way
        {Poolex, [pool_id: :worker_pool_2, worker_module: SomeOtherWorker, workers_count: 5]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
    ```

## [0.4.0] - 2023-02-18

### Added

- Overflow feature. [Example of use](https://hexdocs.pm/poolex/example-of-use.html)
- Speeding up CI by adding dialyzer PLT files caches.

### Fixed

- Fix links in hex documentation.
- Added missing spec for `get_debug_info/1`.

## [0.3.0] - 2023-02-03 (RETIRED)

### Added

- The ability to set your own implementations for `workers` and `callers`. [Read more about it](docs/guides/custom-implementations.md)
- New interface `Poolex.debug_info/1`.

### Changed

- All documentation is divided into separate guides. A table of contents with links has been added to the [Readme](README.md).
- Several changes have been made to the `Poolex.State` structure:
  - Fields `busy_workers_count` and `busy_workers_pids` removed in favor of `busy_workers_state`.
  - Fields `idle_workers_count` and `idle_workers_pids` removed in favor of `idle_workers_state`.
  - Field `waiting_callers` changed to `waiting_callers_state`.

## [0.2.2] - 2023-01-28

### Added

- Docs for functions with examples of use.

### Changed

- Use [ex_check](https://github.com/karolsluszniak/ex_check) for static analysis.

## [0.2.1] - 2023-01-27

### Changed

- Updated minimum required versions
  - Elixir: `1.7`
  - OTP: `22`

## [0.2.0] - 2023-01-25

### Changed

- `run/3` was moved to `run!/3` since it can raise runtime errors.
- `run/3` function now handles errors and returns:
  - `{:ok, any()}` on success;
  - `:all_workers_are_busy` when no idle worker is found in the pool;
  - `{:runtime_error, any()}` on runtime errors.

### Fixed

- Now workers are running under [DynamicSupervisor](https://hexdocs.pm/elixir/1.13/DynamicSupervisor.html) for better control.
- Fix bug on worker release logic.

## [0.1.1] - 2023-01-06

### Fixed

- Fix `Poolex.run/3` spec.

## [0.1.0] - 2023-01-06

### Added

- Supported main interface `Poolex.run/3` with `:timeout` option.

[unreleased]: https://github.com/general-CbIC/poolex/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/general-CbIC/poolex/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/general-CbIC/poolex/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/general-CbIC/poolex/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/general-CbIC/poolex/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/general-CbIC/poolex/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/general-CbIC/poolex/compare/v0.10.0...v1.0.0
[0.10.0]: https://github.com/general-CbIC/poolex/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/general-CbIC/poolex/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/general-CbIC/poolex/compare/v0.7.6...v0.8.0
[0.7.6]: https://github.com/general-CbIC/poolex/compare/v0.7.5...v0.7.6
[0.7.5]: https://github.com/general-CbIC/poolex/compare/v0.7.4...v0.7.5
[0.7.4]: https://github.com/general-CbIC/poolex/compare/v0.7.3...v0.7.4
[0.7.3]: https://github.com/general-CbIC/poolex/compare/v0.7.2...v0.7.3
[0.7.2]: https://github.com/general-CbIC/poolex/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/general-CbIC/poolex/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/general-CbIC/poolex/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/general-CbIC/poolex/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/general-CbIC/poolex/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/general-CbIC/poolex/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/general-CbIC/poolex/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/general-CbIC/poolex/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/general-CbIC/poolex/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/general-CbIC/poolex/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/general-CbIC/poolex/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/general-CbIC/poolex/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/general-CbIC/poolex/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/general-CbIC/poolex/releases/tag/v0.1.0
