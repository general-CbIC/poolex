# Manual Worker Management

Poolex provides two functions for manually managing workers: `acquire/2` and `release/2`. These functions give you direct control over worker lifecycle, which is useful for long-running operations.

## When to use acquire/release

Use `acquire/2` and `release/2` when:

- **Long-lived connections**: You need to hold a database connection, HTTP connection, or similar resource for the entire lifetime of a process or session
- **Session-based workflows**: A worker must be tied to a user session (e.g., maintaining state during a TCP connection)
- **Complex transactions**: You need to perform multiple operations on the same worker with arbitrary delays between them
- **Manual resource management**: You want explicit control over when resources are acquired and released

Use `run/3` when:

- **Short operations**: You have a single, quick function to execute
- **Automatic cleanup**: You want the pool to handle worker release automatically
- **Simpler code**: You don't need to manage worker lifecycle explicitly

## Basic usage

### Simple acquire and release

```elixir
# Acquire a worker from the pool
{:ok, worker} = Poolex.acquire(:my_pool)

# Use the worker
result = GenServer.call(worker, :do_work)

# Release it back to the pool
Poolex.release(:my_pool, worker)
```

### With timeout

```elixir
# Wait up to 10 seconds for a worker
case Poolex.acquire(:my_pool, checkout_timeout: 10_000) do
  {:ok, worker} ->
    # Use worker...
    Poolex.release(:my_pool, worker)

  {:error, :checkout_timeout} ->
    {:error, :pool_busy}
end
```

### Multiple workers

A single process can acquire multiple workers:

```elixir
{:ok, worker1} = Poolex.acquire(:my_pool)
{:ok, worker2} = Poolex.acquire(:my_pool)

# Use both workers...

Poolex.release(:my_pool, worker1)
Poolex.release(:my_pool, worker2)
```

## Real-world example: TCP session handler

Here's a practical example of using `acquire/release` to maintain a database connection for the lifetime of a TCP session:

```elixir
defmodule MyApp.SessionHandler do
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  @impl true
  def init(socket) do
    # Acquire a database connection for this session
    case Poolex.acquire(:db_pool, checkout_timeout: 5_000) do
      {:ok, db_conn} ->
        # Connection will be held for the entire session lifetime
        {:ok, %{socket: socket, db_conn: db_conn}}

      {:error, :checkout_timeout} ->
        {:stop, :no_db_connection}
    end
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    # Use the same db connection for all requests in this session
    result = GenServer.call(state.db_conn, {:query, data})
    :gen_tcp.send(state.socket, result)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Release the connection when session ends
    Poolex.release(:db_pool, state.db_conn)
    :ok
  end
end
```

## Safety guarantees

### Automatic cleanup on crash

If your process crashes before calling `release/2`, Poolex automatically handles cleanup:

```elixir
{:ok, worker} = Poolex.acquire(:my_pool)

# If your process crashes here, the worker is automatically killed
# and restarted by the supervisor, preventing stuck workers

# This ensures the next caller gets a clean worker
```

**Why kill the worker?** When a process crashes while holding a worker, we can't know the worker's state. It might be:
- Stuck in a long-running operation
- Holding locks or resources
- In an inconsistent state

Killing and restarting ensures the next caller gets a fresh, clean worker.

### Graceful release

When you explicitly call `release/2`, the worker is returned to the pool gracefully without restart:

```elixir
{:ok, worker} = Poolex.acquire(:my_pool)
# Use worker...
Poolex.release(:my_pool, worker)  # Worker returned to pool, not killed
```

### Double-release is safe

Calling `release/2` multiple times for the same worker is safe - subsequent releases are ignored:

```elixir
Poolex.release(:my_pool, worker)
Poolex.release(:my_pool, worker)  # Ignored, does nothing
```

### Ownership protection

Workers can only be released by the process that acquired them:

```elixir
# Process A
{:ok, worker} = Poolex.acquire(:my_pool)

# Process B (different process)
Poolex.release(:my_pool, worker)  # Ignored - Process B doesn't own this worker

# Process A
Poolex.release(:my_pool, worker)  # Works - Process A is the owner
```

## Best practices

### Always release in terminate/2

For GenServer processes holding workers, always release in `terminate/2`:

```elixir
def terminate(_reason, %{worker: worker} = state) do
  Poolex.release(:my_pool, worker)
  :ok
end
```

### Use try/after for synchronous code

When using workers in synchronous code, use `try/after` to ensure release:

```elixir
{:ok, worker} = Poolex.acquire(:my_pool)

try do
  # Do work with worker
  GenServer.call(worker, :operation)
after
  Poolex.release(:my_pool, worker)
end
```

**Note:** For simple cases like this, consider using `run/3` instead, which handles this automatically.

### Don't pass workers between processes

Workers should not be passed between processes. Each process should acquire its own worker:

```elixir
# Bad: Passing worker to another process
{:ok, worker} = Poolex.acquire(:my_pool)
Task.async(fn -> GenServer.call(worker, :operation) end)
Poolex.release(:my_pool, worker)  # Worker still in use by Task!

# Good: Each process acquires its own worker
Task.async(fn ->
  {:ok, worker} = Poolex.acquire(:my_pool)
  try do
    GenServer.call(worker, :operation)
  after
    Poolex.release(:my_pool, worker)
  end
end)
```

### Keep acquisition time short

When waiting for a worker, keep the checkout_timeout reasonable:

```elixir
# Good: Reasonable timeout
{:ok, worker} = Poolex.acquire(:my_pool, checkout_timeout: 5_000)

# Bad: Waiting forever
{:ok, worker} = Poolex.acquire(:my_pool, checkout_timeout: :infinity)
```

### Monitor pool metrics

Use telemetry to monitor how long workers are held:

```elixir
# Track acquisition and release
{:ok, worker} = Poolex.acquire(:my_pool)
start_time = System.monotonic_time()

try do
  # Do work...
after
  duration = System.monotonic_time() - start_time
  :telemetry.execute([:my_app, :worker, :held], %{duration: duration})
  Poolex.release(:my_pool, worker)
end
```

## Comparison with run/3

| Feature | `run/3` | `acquire/release` |
|---------|---------|-------------------|
| Worker lifetime | Single function call | Manual control |
| Cleanup | Automatic | Manual (with auto-cleanup on crash) |
| Use case | Short operations | Long-lived connections |
| Complexity | Simple | More control, more responsibility |
| Safety | Worker killed on crash | Worker killed on crash |

## Common patterns

### Connection pooling for requests

```elixir
defmodule MyApp.RequestHandler do
  def handle_request(request) do
    case Poolex.acquire(:db_pool) do
      {:ok, conn} ->
        try do
          process_request(conn, request)
        after
          Poolex.release(:db_pool, conn)
        end

      {:error, :checkout_timeout} ->
        {:error, :service_unavailable}
    end
  end
end
```

### Long-lived session with cleanup

```elixir
defmodule MyApp.Session do
  use GenServer

  def init(_opts) do
    case Poolex.acquire(:resource_pool) do
      {:ok, resource} ->
        Process.flag(:trap_exit, true)
        {:ok, %{resource: resource}}

      {:error, :checkout_timeout} ->
        {:stop, :no_resource}
    end
  end

  def terminate(_reason, %{resource: resource}) do
    Poolex.release(:resource_pool, resource)
  end
end
```

## See also

- `Poolex.acquire/2` - Function documentation
- `Poolex.release/2` - Function documentation
- `Poolex.run/3` - Automatic worker management
- [Getting Started](getting-started.html) - Basic Poolex usage
