defmodule Poolex.Callers.Behaviour do
  @moduledoc """
  Behaviour for callers collection implementations.

  `caller` is a process that uses the `Poolex.run/3` function and waits for the execution result.

  **Note that the caller's typespec matches `GenServer.from()`**
  """

  @type state() :: any()

  @doc "Returns `state` (any data structure) which will be passed as the first argument to all other functions."
  @callback init() :: state()
  @doc "Adds caller to `state` and returns new state."
  @callback add(state(), Poolex.Caller.t()) :: state()
  @doc "Returns `true` if the `state` is empty, `false` otherwise."
  @callback empty?(state()) :: boolean()
  @doc "Removes one of callers from `state` and returns it as `{caller, state}`. Returns `:empty` if state is empty."
  @callback pop(state()) :: {Poolex.Caller.t(), state()} | :empty
  @doc "Removes caller by pid from `state` and returns new state."
  @callback remove_by_pid(state(), caller_pid :: pid()) :: state()
  @doc "Removes caller by reference from `state` and returns new state."
  @callback remove_by_reference(state(), reference :: reference()) :: state()
  @doc "Returns list of callers."
  @callback to_list(state()) :: list(Poolex.Caller.t())
end
