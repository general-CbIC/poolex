defmodule Poolex.Workers.Impl.ErlangQueueTest do
  use ExUnit.Case

  alias Poolex.Workers.Impl.ErlangQueue, as: Impl

  test "empty workers queue" do
    state = Impl.init()

    assert Impl.empty?(state) == true
    assert Impl.count(state) == 0
    assert Impl.to_list(state) == []
  end

  test "queue with some workers" do
    worker_1 = :c.pid(0, 250, 1)
    worker_2 = :c.pid(0, 250, 2)

    state = Impl.init([worker_1, worker_2])

    assert Impl.empty?(state) == false
    assert Impl.count(state) == 2
    assert Impl.to_list(state) == [worker_1, worker_2]
  end

  test "add and remove workers" do
    worker_1 = :c.pid(0, 250, 1)
    worker_2 = :c.pid(0, 250, 2)

    state = Impl.init()

    state =
      state
      |> Impl.add(worker_1)
      |> Impl.add(worker_2)

    assert Impl.member?(state, worker_1) == true
    assert Impl.member?(state, worker_2) == true
    assert Impl.empty?(state) == false
    assert Impl.count(state) == 2
    assert Impl.to_list(state) == [worker_1, worker_2]

    state = Impl.remove(state, worker_1)

    assert Impl.member?(state, worker_1) == false
    assert Impl.member?(state, worker_2) == true
    assert Impl.empty?(state) == false
    assert Impl.count(state) == 1
    assert Impl.to_list(state) == [worker_2]
  end

  test "pop/1" do
    worker_1 = :c.pid(0, 250, 1)
    worker_2 = :c.pid(0, 250, 2)
    worker_3 = :c.pid(0, 250, 3)

    state =
      Impl.init()
      |> Impl.add(worker_1)
      |> Impl.add(worker_2)
      |> Impl.add(worker_3)

    {worker, state} = Impl.pop(state)
    assert worker == worker_1

    {worker, state} = Impl.pop(state)
    assert worker == worker_2

    {worker, state} = Impl.pop(state)
    assert worker == worker_3

    assert Impl.pop(state) == :empty
    assert Impl.empty?(state) == true
  end
end
