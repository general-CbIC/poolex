# Example of use

This example is based on the [Elixir School's poolboy guide](https://elixirschool.com/en/lessons/misc/poolboy).  
You can find the source of the below example here: [poolex_example](https://github.com/general-CbIC/poolex/tree/develop/examples/poolex_example).

## Defining the worker

We describe an actor that can easily become a bottleneck in our application, since it has a rather long execution time on a blocking call.

```elixir
defmodule PoolexExample.Worker do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, nil)
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

## Configuring Poolex

```elixir
defmodule PoolexExample.Application do
  @moduledoc false

  use Application

  defp pool_config do
    [
      worker_module: PoolexExample.Worker,
      workers_count: 5,
      max_overflow: 2
    ]
  end

  def start(_type, _args) do
    children = [
      %{
        id: :worker_pool,
        start: {Poolex, :start_link, [:worker_pool, pool_config()]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Please note that 7 workers started at once. 5 of them were launched at initialization and 2 workers were started over the limit based on the `max_overflow` setting.

All supported configuration options are presented in [Getting Started guide](getting-started.md#poolex-configuration-options).

## Using Poolex

`Poolex.run/3` is the function that you can use to interface with the worker pool.

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
      Poolex.run!(
        :worker_pool,
        fn pid ->
          # Let's wrap the genserver call in a try - catch block. This allows us to trap any exceptions
          # that might be thrown and return the worker back to Poolex in a clean manner. It also allows
          # the programmer to retrieve the error and potentially fix it.
          try do
            GenServer.call(pid, {:square_root, i})
          catch
            e, r ->
              IO.inspect("Poolex transaction caught error: #{inspect(e)}, #{inspect(r)}")
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

Run the test function `PoolexExample.Test.start()` and see the result:

```text
process #PID<0.351.0> calculating square root of 3
process #PID<0.350.0> calculating square root of 2
process #PID<0.349.0> calculating square root of 1
process #PID<0.352.0> calculating square root of 4
process #PID<0.353.0> calculating square root of 5
process #PID<0.349.0> calculating square root of 9
process #PID<0.353.0> calculating square root of 7
{:ok, 1.0}
process #PID<0.351.0> calculating square root of 8
process #PID<0.352.0> calculating square root of 6
process #PID<0.350.0> calculating square root of 10
{:ok, 1.4142135623730951}
{:ok, 1.7320508075688772}
...
```
