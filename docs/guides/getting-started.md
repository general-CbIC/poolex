# Getting Started

## Starting pool of workers

To start a pool you can use either `start/1` or `start_link/1`.

```elixir
Poolex.start_link(pool_id: :my_pool, worker_module: SomeWorker, workers_count: 10)
```

In general, you should place it into your Supervision tree for fault tolerance.

```elixir
children = [
  Poolex.child_spec(
    pool_id: :my_pool,
    worker_module: SomeWorker,
    workers_count: 10,
    max_overflow: 10
  )
]

Supervisor.start_link(children, strategy: :one_for_one)
```

The second argument should contain a set of options for starting the pool.

### Poolex configuration options

| Option                 | Description                                          | Example               | Default value                     |
|------------------------|------------------------------------------------------|-----------------------|-----------------------------------|
| `pool_id`              | Identifier by which you will access the pool         | `:my_pool`            | **option is required**            |
| `worker_module`        | Name of module that implements our worker            | `MyApp.Worker`        | **option is required**            |
| `workers_count`        | How many workers should be running in the pool       | `5`                   | **option is required**            |
| `max_overflow`         | How many workers can be created over the limit       | `2`                   | `0`                               |
| `worker_args`          | List of arguments passed to the start function       | `[:gg, "wp"]`         | `[]`                              |
| `worker_start_fun`     | Name of the function that starts the worker          | `:run`                | `:start_link`                     |
| `busy_workers_impl`    | Module that describes how to work with busy workers  | `SomeBusyWorkersImpl` | `Poolex.Workers.Impl.List`        |
| `idle_workers_impl`    | Module that describes how to work with idle workers  | `SomeIdleWorkersImpl` | `Poolex.Workers.Impl.List`        |
| `waiting_callers_impl` | Module that describes how to work with callers queue | `WaitingCallersImpl`  | `Poolex.Callers.Impl.ErlangQueue` |

## Working with the pool

After the pool is initialized, you can get a free worker and perform any operations on it. This is done through the main interfaces `run/3` and `run!/3`. The functions work the same and the only difference between them is that `run/3` takes care of the runtime error handling.

The first argument is the name of the pool mentioned above.

The second argument is the function that takes the pid of the worker as the only parameter and performs the necessary actions.

The third argument contains run options. Currently, there is only one `timeout` option that tells Poolex how long we can wait for a worker on the call site.

```elixir
iex> Poolex.start_link(pool_id: :agent_pool, worker_module: Agent, worker_args: [fn -> 5 end], workers_count: 1)
iex> Poolex.run(:agent_pool, fn pid -> Agent.get(pid, &(&1)) end)
{:ok, 5}
iex> Poolex.run!(:agent_pool, fn pid -> Agent.get(pid, &(&1)) end)
5
```

If you would like to see examples of using Poolex, then check out [Example of Use](example-of-use.md).
