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
- Use your implementations to define worker and caller processes access logic.

<details>
  <summary>Why `poolex` instead of `poolboy`?</summary>
  
- `poolex` is written in Elixir. This library is much more convenient to use in Elixir projects.
- `poolboy` is a great library, but not actively maintained at the moment :crying_cat_face:![Last poolboy commit](https://img.shields.io/github/last-commit/devinus/poolboy?style=flat)
  
</details>

## Requirements

| Requirement | Version |
|-------------|---------|
| Erlang/OTP  | >= 22   |
| Elixir      | >= 1.7  |

## Table of Contents

- [Installation](#installation)
- [Getting Started](https://hexdocs.pm/poolex/getting-started.html)
  - [Starting pool of workers](https://hexdocs.pm/poolex/getting-started.html#starting-pool-of-workers)
  - [Poolex configuration options](https://hexdocs.pm/poolex/getting-started.html#starting-pool-of-workers)
  - [Working with the pool](https://hexdocs.pm/poolex/getting-started.html#working-with-the-pool)
- [Migration from `:poolboy`](https://hexdocs.pm/poolex/migration-from-poolboy.html)
- [Example of use](https://hexdocs.pm/poolex/example-of-use.html)
  - [Defining the worker](https://hexdocs.pm/poolex/example-of-use.html#defining-the-worker)
  - [Configuring Poolex](https://hexdocs.pm/poolex/example-of-use.html#configuring-poolex)
  - [Using Poolex](https://hexdocs.pm/poolex/example-of-use.html#using-poolex)
- [Workers and callers implementations](https://hexdocs.pm/poolex/workers-and-callers-implementations.html)
  - [Callers](https://hexdocs.pm/poolex/workers-and-callers-implementations.html#callers)
  - [Workers](https://hexdocs.pm/poolex/workers-and-callers-implementations.html#workers)
  - [Writing custom implementations](https://hexdocs.pm/poolex/workers-and-callers-implementations.html#writing-custom-implementations)
- [Contributions](#contributions)

## Installation

Add `:poolex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:poolex, "~> 0.7.0"}
  ]
end
```

## Usage

In the most typical use of Poolex, you only need to start a pool of workers as a child of your application.

```elixir
children = [
  {Poolex, 
    pool_id: :worker_pool,
    worker_module: SomeWorker,
    workers_count: 5}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Then you can execute any code on the workers with `run/3`:

```elixir
iex> Poolex.run(:worker_pool, &(is_pid?(&1)), timeout: 1_000)
{:ok, true}
```

A detailed description of the available configuration or examples of use can be found in [documentation](https://hexdocs.pm/poolex/getting-started.html).

## Contributions

If you feel something can be improved, or have any questions about certain behaviors or pieces of implementation, please feel free to file an issue. Proposed changes should be taken to issues before any PRs to avoid wasting time on code that might not be merged upstream.

If you are ready to make changes to the project, then please read the [Contributing guide](docs/CONTRIBUTING.md) first.
