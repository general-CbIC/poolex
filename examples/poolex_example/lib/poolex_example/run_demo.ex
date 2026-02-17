defmodule PoolexExample.RunDemo do
  @moduledoc """
  Demonstrates the automatic approach using Poolex.run/3.

  This module shows how run/3 automatically manages worker lifecycle
  but has limitations when you need multiple workers simultaneously.
  """

  @pool_id :worker_pool
  @timeout 60_000

  @doc """
  Simple example: one operation with run/3.

  Shows basic usage where the worker is automatically returned
  after the function completes.
  """
  def simple do
    IO.puts("\n[RunDemo.simple] Calculating sqrt(16) with run/3...")

    start_time = System.monotonic_time(:millisecond)

    {:ok, result} =
      Poolex.run(
        @pool_id,
        fn worker_pid ->
          GenServer.call(worker_pid, {:square_root, 16})
        end,
        checkout_timeout: @timeout
      )

    end_time = System.monotonic_time(:millisecond)

    IO.puts("Result: #{result}")
    IO.puts("Time: #{end_time - start_time}ms\n")

    result
  end

  @doc """
  Multiple workers example: shows limitation of run/3.

  With run/3, you cannot acquire multiple workers simultaneously
  from the same process (deadlock risk). Operations must be sequential.
  """
  def multiple_workers do
    IO.puts("\n[RunDemo.multiple_workers] With run/3, operations execute sequentially:")

    start_time = System.monotonic_time(:millisecond)

    # First operation
    IO.puts("\nStep 1: sqrt(25)...")

    {:ok, result1} =
      Poolex.run(
        @pool_id,
        fn worker_pid ->
          GenServer.call(worker_pid, {:square_root, 25})
        end,
        checkout_timeout: @timeout
      )

    IO.puts("Result: #{result1}")

    # Second operation (must wait for first to complete)
    IO.puts("\nStep 2: power(2, 10)...")

    {:ok, result2} =
      Poolex.run(
        @pool_id,
        fn worker_pid ->
          GenServer.call(worker_pid, {:power, 2, 10})
        end,
        checkout_timeout: @timeout
      )

    IO.puts("Result: #{result2}")

    end_time = System.monotonic_time(:millisecond)

    IO.puts("\nTotal time: #{end_time - start_time}ms")
    IO.puts("Note: For parallel use of multiple workers, use acquire/release!\n")

    {result1, result2}
  end
end
