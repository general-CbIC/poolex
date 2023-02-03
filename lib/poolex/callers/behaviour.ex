defmodule Poolex.Callers.Behaviour do
  @moduledoc """
  Behaviour for callers collection implementations.

  `caller` is a process that uses the `Poolex.run/3` function and waits for the execution result.
  """

  @type state() :: any()

  @doc "Returns `state` (any data structure) which will be passed as the first argument to all other functions."
  @callback init() :: state()
  @doc "Adds caller's pid to `state` and returns new state."
  @callback add(state(), caller :: pid()) :: state()
  @doc "Returns `true` if the `state` is empty, `false` otherwise."
  @callback empty?(state()) :: boolean()
  @doc "Removes one of callers from `state` and returns it as `{caller, state}`. Returns `:empty` if state is empty."
  @callback pop(state()) :: {caller :: pid(), state()} | :empty
  @doc "Removes given caller from `state` and returns new state."
  @callback remove(state(), caller :: pid()) :: state()
  @doc "Returns list of callers pids."
  @callback to_list(state()) :: list(pid())
end
