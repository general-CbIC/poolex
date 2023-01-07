# Poolex

![Build and tests workflow](https://github.com/general-CbIC/poolex/actions/workflows/ci-tests.yml/badge.svg)
[![hex.pm version](https://img.shields.io/hexpm/v/poolex.svg?style=flat)](https://hex.pm/packages/poolex)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg?style=flat)](https://hexdocs.pm/poolex/)
[![License](https://img.shields.io/hexpm/l/poolex.svg?style=flat)](https://github.com/general-CbIC/poolex/blob/main/LICENSE)
<!--[![Total Download](https://img.shields.io/hexpm/dt/poolex.svg?style=flat)](https://hex.pm/packages/poolex)-->

<!-- @moduledoc -->

Poolex is a library for managing a pool of processes. Inspired by [poolboy](https://github.com/devinus/poolboy).

## Requirements

| Requirement | Version |
|-------------|---------|
| Erlang/OTP  | >= 23   |
| Elixir      | >= 1.13 |

## Installation

Add `:poolex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:poolex, "~> 0.1.0"}
  ]
end
```

## Usage

This example is based on the [Elixir School's poolboy guide](https://elixirschool.com/en/lessons/misc/poolboy).  
You can find the source of the below example here: [poolex_example](https://github.com/general-CbIC/poolex_example).

### Defining the worker

We describe an actor that can easily become a bottleneck in our application, since it has a rather long execution time on a blocking call.

```elixir
defmodule PoolexExample.Worker do
  use GenServer

  def start do
    GenServer.start(__MODULE__, nil)
  end

  def init(_args) do
    {:ok, nil}
  end

  def handle_call({:square_root, x}, _from, state) do
    IO.puts("process #{inspect(self())} calculating square root of #{x}")
    Process.sleep(1_000)
    {:reply, :math.sqrt(x), state}
  end
end
```

### Configuring Poolex

```elixir
defmodule PoolexExample.Application do
  @moduledoc false

  use Application

  defp worker_config do
    [
      worker_module: PoolexExample.Worker,
      workers_count: 5
    ]
  end

  def start(_type, _args) do
    children = [
      %{
        id: :worker_pool,
        start: {Poolex, :start_link, [:worker_pool, worker_config()]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

List of possible configuration options:

| Option             | Description                                    | Example        | Default value          |
|--------------------|------------------------------------------------|----------------|------------------------|
| `worker_module`    | Name of module that implements our worker      | `MyApp.Worker` | **option is required** |
| `worker_start_fun` | Name of the function that starts the worker    | `:run`         | `:start`               |
| `worker_args`      | List of arguments passed to the start function | `[:gg, "wp"]`  | `[]`                   |
| `workers_count`    | How many workers should be running in the pool | `5`            | **option is required** |

### Using Poolex

`Poolex.run/3` is the function that you can use to interface with the worker pool.

- The first parameter is the pool ID (see Poolex configuration).
- The second parameter is a function that takes the pid of the worker and performs the necessary operation with it.
- The third parameter is a keyword of run options.
  - `:timeout` -- Worker timeout on the side of the calling process. For example, if the timeout is `1000` and no free workers have appeared in the pool for a second, then the execution will abort with raising an error. The default value for this parameter is 5 seconds.

```elixir
defmodule PoolexExample.Test do
  @timeout 60_000

  def start do
    1..20
    |> Enum.map(fn i -> async_call_square_root(i) end)
    |> Enum.each(fn task -> await_and_inspect(task) end)
  end

  defp async_call_square_root(i) do
    Task.async(fn ->
      Poolex.run(
        :worker_pool,
        fn pid ->
          # Let's wrap the genserver call in a try - catch block. This allows us to trap any exceptions
          # that might be thrown and return the worker back to poolboy in a clean manner. It also allows
          # the programmer to retrieve the error and potentially fix it.
          try do
            GenServer.call(pid, {:square_root, i})
          catch
            e, r ->
              IO.inspect("poolboy transaction caught error: #{inspect(e)}, #{inspect(r)}")
              :ok
          end
        end,
        timeout: @timeout
      )
    end)
  end

  defp await_and_inspect(task), do: task |> Task.await(@timeout) |> IO.inspect()
end
```

Run the test function and see the result.

```shell
iex -S mix
```

```iex
iex> PoolexExample.Test.start
process #PID<0.227.0> calculating square root of 5
process #PID<0.223.0> calculating square root of 1
process #PID<0.225.0> calculating square root of 3
process #PID<0.224.0> calculating square root of 2
process #PID<0.226.0> calculating square root of 4
1.0
1.4142135623730951
1.7320508075688772
2.0
2.23606797749979
2.449489742783178
...
```
