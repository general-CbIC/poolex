# Poolex

Pure elixir pool manager inspired by [poolboy](https://github.com/devinus/poolboy).

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

### Example

TODO: describe me via `PoolexExample`

### Configuration

| Option             | Description                                    | Example        | Default value          |
|--------------------|------------------------------------------------|----------------|------------------------|
| `worker_module`    | Name of module that implements our worker      | `MyApp.Worker` | **option is required** |
| `worker_start_fun` | Name of the function that starts the worker    | `:run`         | `:start`               |
| `worker_args`      | List of arguments passed to the start function | `[:gg, "wp"]`  | `[]`                   |
| `workers_count`    | How many workers should be running in the pool | `5`            | **option is required** |
