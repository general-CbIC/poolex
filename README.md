# Poolex

![Build and tests workflow](https://github.com/general-CbIC/poolex/actions/workflows/ci-tests.yml/badge.svg)
[![hex.pm version](https://img.shields.io/hexpm/v/poolex.svg?style=flat)](https://hex.pm/packages/poolex)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg?style=flat)](https://hexdocs.pm/poolex/)
[![License](https://img.shields.io/hexpm/l/poolex.svg?style=flat)](https://github.com/general-CbIC/poolex/blob/main/LICENSE)
<!-- [![Total Download](https://img.shields.io/hexpm/dt/poolex.svg?style=flat)](https://hex.pm/packages/poolex) -->

Poolex is a library for managing pools of workers. Inspired by [poolboy](https://github.com/devinus/poolboy).

## Features

With `poolex` you can:

- Launch multiple pools of workers and then access the free ones from anywhere in the application.
- Configure the pool to run additional temporary workers if the load increases.
- Use your own implementations to define workers and callers access logic.

<details>
  <summary>Why `poolex` instead of `poolboy`?</summary>
  
- `poolex` is written in Elixir. This library is much more convenient to use in Elixir projects.
- `poolboy` is a great library, but not actively maintained at the moment :crying_cat_face: ![Last poolboy commit](https://img.shields.io/github/last-commit/devinus/poolboy?style=flat)
  
</details>

## Requirements

| Requirement | Version |
|-------------|---------|
| Erlang/OTP  | >= 22   |
| Elixir      | >= 1.7  |

## Table of Contents

- [Installation](#installation)
- [Getting Started](docs/guides/getting-started.md)
  - [Starting pool of workers](docs/guides/getting-started.md#starting-pool-of-workers)
    - [Poolex configuration options](docs/guides/getting-started.md#poolex-configuration-options)
  - [Working with the pool](docs/guides/getting-started.md#working-with-the-pool)
- [Example of use](docs/guides/example-of-use.md)
  - [Defining the worker](docs/guides/example-of-use.md#defining-the-worker)
  - [Configuring Poolex](docs/guides/example-of-use.md#configuring-poolex)
  - [Using Poolex](docs/guides/example-of-use.md#using-poolex)
- [Custom implementations](docs/guides/custom-implementations.md)
  - [Callers](docs/guides/custom-implementations.md#callers)
  - [Workers](docs/guides/custom-implementations.md#workers)
  - [Writing custom implementations](docs/guides/custom-implementations.md#writing-custom-implementations)
- [Contributions](#contributions)

## Installation

Add `:poolex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:poolex, "~> 0.5.0"}
  ]
end
```

## Usage

In the most typical use of Poolex, you only need to start pool of workers as a child of your application.

```elixir
children = [
  Poolex.child_spec(
    pool_id: :worker_pool,
    worker_module: SomeWorker,
    workers_count: 5
  )
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Then you can execute any code on the workers with `run/3`:

```elixir
iex> Poolex.run(:worker_pool, &(is_pid?(&1)), timeout: 1_000)
{:ok, true}
```

A detailed description of the available configuration or examples of use can be found in [documentation](docs/guides.md).

## Contributions

If you feel something can be improved, or have any questions about certain behaviours or pieces of implementation, please feel free to file an issue. Proposed changes should be taken to issues before any PRs to avoid wasting time on code which might not be merged upstream.

If you are ready to make changes to the project, then please read the [Contributing guide](docs/CONTRIBUTING.md) first.
