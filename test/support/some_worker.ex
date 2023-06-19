defmodule SomeWorker do
  @moduledoc false
  use GenServer

  def traceable_call(server, pid, msg, delay) do
    GenServer.call(server, {:traceable, pid, msg, delay})
  end

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_options) do
    {:ok, :ok}
  end

  @impl true
  def handle_call({:traceable, pid, msg, delay}, _pid, state) do
    send(pid, {:traceable_start, msg, self()})
    :timer.sleep(delay)
    Process.send_after(pid, {:traceable_end, msg, self()}, 10)
    {:reply, :ok, state}
  end

  @impl true
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
