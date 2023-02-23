defmodule SomeWorker do
  @moduledoc false
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
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

  def handle_call(:do_raise, _from, state) do
    raise RuntimeError

    {:reply, nil, state}
  end
end
