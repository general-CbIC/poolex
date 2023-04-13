defmodule Poolex.Callers.Impl.ErlangQueueTest do
  use ExUnit.Case

  alias Poolex.Callers.Impl.ErlangQueue, as: Impl

  setup do
    [state: Impl.init()]
  end

  test "usage cases", %{state: state} do
    # Must be empty after init/0
    assert Impl.empty?(state) == true
    assert Impl.pop(state) == :empty
    assert Impl.to_list(state) == []

    # Add 2 callers
    caller_1_pid = :c.pid(0, 250, 1)
    caller_1 = gen_caller(caller_1_pid)

    caller_2_pid = :c.pid(0, 250, 2)
    caller_2 = gen_caller(caller_2_pid)

    state =
      state
      |> Impl.add(caller_1)
      |> Impl.add(caller_2)

    assert Impl.empty?(state) == false
    assert Impl.to_list(state) == [caller_1, caller_2]
    assert state |> Impl.pop() |> elem(0) == caller_1

    # Remove by pid
    state =
      state
      |> Impl.add(caller_1)
      |> Impl.add(caller_2)
      |> Impl.remove_by_pid(caller_1_pid)

    assert Impl.to_list(state) == [caller_2, caller_2]
  end

  defp gen_caller(pid, tag \\ make_ref()) do
    {pid, tag}
  end
end
