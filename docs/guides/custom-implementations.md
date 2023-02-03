# Custom Implementations

`Poolex` operates with two concepts: `callers` and `workers`. In both cases, we are talking about processes.

## Callers

**Callers** are processes that have made a request to get a worker (used `run/3` or `run!/3`). Each pool keeps information about **callers** in order to distribute workers to them when they are free.

The implementation of the caller storage structure should be conceptually similar to a queue, since by default we want to give workers in the order they are requested. But this logic can be easily changed by writing your own implementation.

Behaviour of callers collection described [here](../../lib/poolex/callers/behaviour.ex).

Default implementation based on erlang `:queue` you can see [here](../../lib/poolex/callers/impl/erlang_queue.ex).

### Behaviour callbacks

| Callback    | Description                                                                                                  |
|-------------|--------------------------------------------------------------------------------------------------------------|
| `init/0`    | Returns `state` (any data structure) which will be passed as the first argument to all other functions.      |
| `add/2`     | Adds caller's pid to `state` and returns new state.                                                          |
| `empty?/1`  | Returns `true` if the `state` is empty, `false` otherwise.                                                   |
| `pop/1`     | Removes one of callers from `state` and returns it as `{caller, state}`. Returns `:empty` if state is empty. |
| `remove/2`  | Removes given caller from `state` and returns new state.                                                     |
| `to_list/1` | Returns list of callers pids.

## Workers

**Workers** are processes launched in a pool. `Poolex` works with two collections of workers:

1. `IdleWorkers` -- Free processes that can be given to callers upon request.
2. `BusyWorkers` -- Processes that are currently processing the caller's request.

For both cases, the default implementation is based on lists. But it is possible to set different implementations for them.

Behaviour of workers collection described [here](../../lib/poolex/workers/behaviour.ex).

Default implementation for `idle` and `busy` workers is [here](../../lib/poolex/workers/impl/list.ex).

### Behaviour callbacks

| Callback    | Description                                                                                                  |
|-------------|--------------------------------------------------------------------------------------------------------------|
| `init/0`    | Returns `state` (any data structure) which will be passed as the first argument to all other functions.      |
| `init/1`    | Same as `init/0` but returns `state` initialized with passed list of workers.                                |
| `add/2`     | Adds worker's pid to `state` and returns new state.                                                          |
| `member?/2` | Returns `true` if given worker contained in the `state`, `false` otherwise.                                  |
| `remove/2`  | Removes given worker from `state` and returns new state.                                                     |
| `count/1`   | Returns the number of workers in the state.                                                                  |
| `to_list/1` | Returns list of workers pids.                                                                                |
| `empty?/1`  | Returns `true` if the `state` is empty, `false` otherwise.                                                   |
| `pop/1`     | Removes one of workers from `state` and returns it as `{caller, state}`. Returns `:empty` if state is empty. |

## Writing custom implementations

It's quite simple when using the [Behaviours](https://elixir-lang.org/getting-started/typespecs-and-behaviours.html#behaviours) mechanism in Elixir.

For example, you want to define a new implementation for callers. To do this, you need to create a module that inherits the [Poolex.Callers.Behaviour](../../lib/poolex/callers/behaviour.ex) and implement all its functions.

```elixir
defmodule MyApp.MyAmazingCallersImpl do
  @behaviour Poolex.Callers.Behaviour

  def init, do: {}
  def add(state, caller), do: #...
end
```

If you have any ideas what implementations can be added to the library or how to improve existing ones, then please [create an issue](https://github.com/general-CbIC/poolex/issues/new)!

### Configuring custom implementations

After that, you need to add the following to the configuration (for example, `runtime.exs`):

```elixir
config :poolex, callers_impl: MyApp.MyAmazingCallersImpl
```

That's it! Your implementation will be used in `Poolex`.

The configuration for workers might look like this:

```elixir
config :poolex,
  busy_workers_impl: MyApp.PerfectBusyWorkersImpl,
  idle_workers_impl: MyApp.FancyIdleWorkersImpl
```
