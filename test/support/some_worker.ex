defmodule SomeWorker do
  @moduledoc false
  use GenServer

  def init(_options) do
    {:ok, :ok}
  end

  def handle_call(:do_some_work, _from, state) do
    :timer.sleep(:timer.seconds(1))
    {:reply, :some_result, state}
  end
end
