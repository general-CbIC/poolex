defmodule SomeWorker do
  @moduledoc false
  use GenServer

  def start do
    GenServer.start(__MODULE__, [])
  end

  def init(_options) do
    {:ok, :ok}
  end

  def handle_call(:do_some_work, _from, state) do
    {:reply, :some_result, state}
  end

  def handle_call({:do_some_work_with_delay, delay}, _from, state) do
    :timer.sleep(delay)

    {:reply, :some_result, state}
  end
end
