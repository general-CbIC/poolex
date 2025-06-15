# Poolex

![Build and tests workflow](https://github.com/general-CbIC/poolex/actions/workflows/ci-tests.yml/badge.svg)
[![hex.pm version](https://img.shields.io/hexpm/v/poolex.svg?style=flat)](https://hex.pm/packages/poolex)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg?style=flat)](https://hexdocs.pm/poolex/)
[![License](https://img.shields.io/hexpm/l/poolex.svg?style=flat)](https://github.com/general-CbIC/poolex/blob/main/LICENSE)
[![Total Download](https://img.shields.io/hexpm/dt/poolex.svg?style=flat)](https://hex.pm/packages/poolex)

Poolex is a library for managing pools of workers. Inspired by [poolboy](https://github.com/devinus/poolboy).

> [!IMPORTANT]  
> Documentation on GitHub corresponds to the current branch. For stable versions' docs see [Hexdocs](https://hexdocs.pm/poolex/).

## Table of Contents

<img alt="Poolex logo" src="https://raw.githubusercontent.com/general-CbIC/poolex/develop/assets/poolex.png" width="250" height="250" align="right"/>

- [Poolex](#poolex)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Usage](#usage)
  - [Guides](#guides)
  - [Used by](#used-by)
  - [Contributions](#contributions)

## Features

With Poolex, you can:

- Launch multiple pools of workers and then access the free ones from anywhere in the application.
- Configure the pool to run additional temporary workers if the load increases.
- Analyze and optimize your pool's production settings using metrics.
- Use your own implementations to define the logic for worker and caller process access.
- Configure delayed shutdown for workers. This is useful if creating workers is a resource-intensive operation.

**Why `poolex` instead of `poolboy`?**
  
- `poolex` is written in Elixir. This library is much more convenient for use in Elixir projects.
- `poolboy` is a great library, but not actively maintained :crying_cat_face: ![Last poolboy commit](https://img.shields.io/github/last-commit/devinus/poolboy?style=flat)

## Requirements

| Library                                                  | Elixir     | Erlang/OTP |
|----------------------------------------------------------|------------|------------|
| from `0.1.0` to `1.2.1`                                  | `>= 1.7`   | `>= 22`    |
| `1.3.0`                                                  | `>= 1 .11` | `>= 24`    |
| `>= 1.4.0` ([not released yet](https://github.com/general-CbIC/poolex/blob/develop/CHANGELOG.md#unreleased)) | `>= 1.17`  | `>= 25`    |

## Installation

Add `:poolex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:poolex, "~> 1.0"}
  ]
end
```

## Usage

In the most typical use of Poolex, you only need to start a pool of workers as a child of your application.

```elixir
children = [
  {Poolex,
    worker_module: SomeWorker,
    workers_count: 5}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Then you can execute any code on the workers with `run/3`:

```elixir
iex> Poolex.run(SomeWorker, &(is_pid?(&1)), checkout_timeout: 1_000)
{:ok, true}
```

A detailed description of the available configuration options and usage examples can be found in the [documentation](https://hexdocs.pm/poolex/getting-started.html).

## Guides

- [Getting Started](https://hexdocs.pm/poolex/getting-started.html)
  - [Starting pool of workers](https://hexdocs.pm/poolex/getting-started.html#starting-pool-of-workers)
  - [Poolex configuration options](https://hexdocs.pm/poolex/getting-started.html#starting-pool-of-workers)
  - [Working with the pool](https://hexdocs.pm/poolex/getting-started.html#working-with-the-pool)
- [Migration from `:poolboy`](https://hexdocs.pm/poolex/migration-from-poolboy.html)
- [Example of use](https://hexdocs.pm/poolex/example-of-use.html)
  - [Defining the worker](https://hexdocs.pm/poolex/example-of-use.html#defining-the-worker)
  - [Configuring Poolex](https://hexdocs.pm/poolex/example-of-use.html#configuring-poolex)
  - [Using Poolex](https://hexdocs.pm/poolex/example-of-use.html#using-poolex)
- [Working with metrics](https://hexdocs.pm/poolex/pool-metrics.html)
  - [Pool size metrics](https://hexdocs.pm/poolex/pool-metrics.html#pool-size-metrics)
  - [Integration with PromEx](https://hexdocs.pm/poolex/pool-metrics.html#integration-with-promex)
- [Workers and callers implementations](https://hexdocs.pm/poolex/workers-and-callers-implementations.html)
  - [Callers](https://hexdocs.pm/poolex/workers-and-callers-implementations.html#callers)
  - [Workers](https://hexdocs.pm/poolex/workers-and-callers-implementations.html#workers)
  - [Writing custom implementations](https://hexdocs.pm/poolex/workers-and-callers-implementations.html#writing-custom-implementations)
- [Using `worker_shutdown_delay` for Overflow Workers](https://hexdocs.pm/poolex/worker-shutdown-delay.html)
  - [What are overflow workers?](https://hexdocs.pm/poolex/worker-shutdown-delay.html#what-are-overflow-workers)
  - [The problem with immediate overflow worker shutdown](https://hexdocs.pm/poolex/worker-shutdown-delay.html#the-problem-with-immediate-overflow-worker-shutdown)
  - [Solution: Delayed shutdown of overflow workers](https://hexdocs.pm/poolex/worker-shutdown-delay.html#solution-delayed-shutdown-of-overflow-workers)
  - [Example usage](https://hexdocs.pm/poolex/worker-shutdown-delay.html#example-usage)
  - [How it works](https://hexdocs.pm/poolex/worker-shutdown-delay.html#how-it-works)
  - [When to use](https://hexdocs.pm/poolex/worker-shutdown-delay.html#when-to-use)
  - [Default value](https://hexdocs.pm/poolex/worker-shutdown-delay.html#default-value)

## Used by

[![Aviasales](https://raw.githubusercontent.com/general-CbIC/poolex/develop/assets/companies/aviasales_logo.svg)](https://aviasales.tp.st/VlJlf7Ar)

<!-- ## Sponsored by

NOTE: Commented cause I'm not sure if the ads are allowed :shrug:

[![Sponsored by GitAds](https://gitads.dev/v1/ad-serve?source=general-cbic/poolex@github)](https://gitads.dev/v1/ad-track?source=general-cbic/poolex@github) -->

## Contributions

If you think something can be improved or have any questions about specific behaviors or implementation details, please feel free to file an issue. Proposed changes should be discussed in issues before submitting any PRs, to avoid spending time on code that might not be merged upstream.

If you are ready to change the project, please read the [Contributing guide](docs/CONTRIBUTING.md) first.
