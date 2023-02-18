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
          try do
            GenServer.call(pid, {:square_root, i})
          catch
            e, r ->
              IO.inspect("Caught error: #{inspect(e)}, #{inspect(r)}")
              :ok
          end
        end,
        timeout: @timeout
      )
    end)
  end

  defp await_and_inspect(task), do: task |> Task.await(@timeout) |> IO.inspect()
end
