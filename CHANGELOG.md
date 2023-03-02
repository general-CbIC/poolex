# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Added

- [Docs] Simple [migration guide from `:poolboy`](docs/guides/migration-from-poolboy.md)

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

- Overflow feature. [Example of use](docs/guides/example-of-use.md)
- Speeding up CI by adding dialyzer PLT files caches.

### Fixed

- Fix links in hex documentation.
- Added missing spec for `get_debug_info/1`.

## [0.3.0] - 2023-02-03

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

[unreleased]: https://github.com/general-CbIC/poolex/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/general-CbIC/poolex/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/general-CbIC/poolex/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/general-CbIC/poolex/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/general-CbIC/poolex/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/general-CbIC/poolex/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/general-CbIC/poolex/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/general-CbIC/poolex/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/general-CbIC/poolex/releases/tag/v0.1.0
