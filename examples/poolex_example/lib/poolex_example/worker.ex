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
