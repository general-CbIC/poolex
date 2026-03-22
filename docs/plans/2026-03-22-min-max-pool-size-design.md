# Design: min_pool_size / max_pool_size Options

## Overview

Add two new pool configuration options that limit the minimum and maximum number of running base workers. These limits are enforced when calling `add_idle_workers!/2` and `remove_idle_workers!/2`.

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `min_pool_size` | `non_neg_integer()` | `0` | Minimum number of base workers allowed |
| `max_pool_size` | `pos_integer() \| :infinity` | `:infinity` | Maximum number of base workers allowed |

**"Base workers"** = idle workers + busy workers (overflow workers are excluded).

## Changes

### `Poolex.Private.Options.Parser`

Add a new private helper and validator:

```elixir
defp parse_optional_pos_integer_or_infinity(options, key, default) do
  options
  |> parse_optional_option(key, default)
  |> validate_pos_integer_or_infinity()
end

defp validate_pos_integer_or_infinity(value) when is_integer(value) and value > 0, do: value
defp validate_pos_integer_or_infinity(:infinity), do: :infinity
defp validate_pos_integer_or_infinity(value) do
  raise ArgumentError, "Expected a positive integer or :infinity, got: #{inspect(value)}"
end
```

Add to `parse/1`:

```elixir
min_pool_size: parse_optional_non_neg_integer(options, :min_pool_size, 0),
max_pool_size: parse_optional_pos_integer_or_infinity(options, :max_pool_size, :infinity),
```

Add consistency validation after building the struct:

```elixir
if parsed.min_pool_size > parsed.max_pool_size do
  raise ArgumentError, "min_pool_size (#{parsed.min_pool_size}) must be <= max_pool_size (#{parsed.max_pool_size})"
end
```

### `Poolex.Private.Options.Parsed`

Add to `@enforce_keys`, `defstruct`, and `@type t()`:

```elixir
min_pool_size: non_neg_integer(),
max_pool_size: pos_integer() | :infinity
```

### `Poolex.Private.State`

Add to `@enforce_keys` and `@type t()`:

```elixir
min_pool_size: non_neg_integer(),
max_pool_size: pos_integer() | :infinity
```

### `Poolex` (public API)

Add to `poolex_option()` type:

```elixir
| {:min_pool_size, non_neg_integer()}
| {:max_pool_size, pos_integer() | :infinity}
```

Add `min_pool_size` and `max_pool_size` to `State` initialization in `init/1`.

### `Poolex` (handle_call)

Add helper:

```elixir
defp base_workers_count(state) do
  IdleWorkers.count(state) + BusyWorkers.count(state)
end
```

Update `handle_call({:add_idle_workers, workers_count}, ...)`:

- Compute how many workers can actually be added without exceeding `max_pool_size`
- Log error for skipped workers
- Start only the allowed number

```elixir
defp available_to_add(%State{max_pool_size: :infinity}, workers_count), do: workers_count
defp available_to_add(%State{max_pool_size: max} = state, workers_count) do
  max(0, min(workers_count, max - base_workers_count(state)))
end
```

Update `handle_call({:remove_idle_workers, workers_count}, ...)`:

- Compute how many workers can actually be removed without going below `min_pool_size`
- Log error for skipped workers

```elixir
defp available_to_remove(%State{min_pool_size: 0} = state, workers_count) do
  min(workers_count, IdleWorkers.count(state))
end
defp available_to_remove(%State{min_pool_size: min} = state, workers_count) do
  max(0, min(workers_count, base_workers_count(state) - min))
end
```

**Log message format:**
- Add: `"Failed to add {n} worker(s): max_pool_size limit of {max} reached"`
- Remove: `"Failed to remove {n} worker(s): min_pool_size limit of {min} reached"`

## Error Behavior

Partial execution: the operation proceeds for as many workers as the limit allows. Workers that cannot be added/removed are silently skipped after logging the error. The function always returns `:ok`.

## Validation at Startup

`ArgumentError` is raised at parse time if:
- `max_pool_size` is not a positive integer or `:infinity`
- `min_pool_size` is not a non-negative integer
- `min_pool_size > max_pool_size`
