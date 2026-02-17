defmodule PoolexExample.AcquireDemo do
  @moduledoc """
  Demonstrates manual worker management using Poolex.acquire/2 and release/2.

  This module shows how acquire/release gives you explicit control over
  worker lifecycle and enables using multiple workers simultaneously.
  """

  @pool_id :worker_pool
  @timeout 60_000

  @doc """
  Simple example: one operation with acquire/release.

  Shows manual worker lifecycle management where you explicitly
  acquire and release the worker.
  """
  def simple do
    IO.puts("\n[AcquireDemo.simple] Acquiring worker manually...")

    start_time = System.monotonic_time(:millisecond)

    # Acquire worker
    {:ok, worker_pid} = Poolex.acquire(@pool_id, checkout_timeout: @timeout)
    IO.puts("Acquired worker: #{inspect(worker_pid)}")

    # Use worker
    result = GenServer.call(worker_pid, {:square_root, 16})
    IO.puts("Result: #{result}")

    # Release worker
    IO.puts("Releasing worker #{inspect(worker_pid)}...")
    :ok = Poolex.release(@pool_id, worker_pid)
    IO.puts("Released!")

    end_time = System.monotonic_time(:millisecond)
    IO.puts("Time: #{end_time - start_time}ms\n")

    result
  end

  @doc """
  Multiple workers example: shows advantage of acquire/release.

  With acquire/release, you can hold multiple workers simultaneously
  and execute operations in parallel.
  """
  def multiple_workers do
    IO.puts("\n[AcquireDemo.multiple_workers] Acquiring two workers simultaneously...")

    start_time = System.monotonic_time(:millisecond)

    # Acquire two workers
    {:ok, worker1} = Poolex.acquire(@pool_id, checkout_timeout: @timeout)
    IO.puts("Acquired worker1: #{inspect(worker1)}")

    {:ok, worker2} = Poolex.acquire(@pool_id, checkout_timeout: @timeout)
    IO.puts("Acquired worker2: #{inspect(worker2)}")

    IO.puts("\nExecuting operations in parallel...")

    # Execute operations in parallel using Task
    task1 = Task.async(fn ->
      GenServer.call(worker1, {:square_root, 25})
    end)

    task2 = Task.async(fn ->
      GenServer.call(worker2, {:power, 2, 10})
    end)

    # Wait for results
    result1 = Task.await(task1, @timeout)
    result2 = Task.await(task2, @timeout)

    IO.puts("\nResults:")
    IO.puts("  - sqrt(25) = #{result1}")
    IO.puts("  - power(2, 10) = #{result2}")

    # Release both workers
    IO.puts("\nReleasing workers...")
    :ok = Poolex.release(@pool_id, worker1)
    :ok = Poolex.release(@pool_id, worker2)
    IO.puts("Released worker1 and worker2!")

    end_time = System.monotonic_time(:millisecond)
    IO.puts("\nTotal time: #{end_time - start_time}ms (parallel instead of ~2000ms!)\n")

    {result1, result2}
  end
end
