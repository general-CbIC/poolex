defmodule Poolex.Workers.Behaviour do
  @moduledoc """
  Behaviour for worker collection implementations.
  """

  @type state() :: any()

  @doc "Returns `state` (any data structure) which will be passed as the first argument to all other functions."
  @callback init() :: state()
  @doc "Same as `init/0` but returns `state` initialized with passed list of workers."
  @callback init(list(pid())) :: state()
  @doc "Adds worker's pid to `state` and returns new state."
  @callback add(state(), worker :: pid()) :: state()
  @doc "Returns `true` if given worker contained in the `state`, `false` otherwise."
  @callback member?(state(), worker :: pid()) :: boolean()
  @doc "Removes given worker from `state` and returns new state."
  @callback remove(state(), worker :: pid()) :: state()
  @doc "Returns the number of workers in the state."
  @callback count(state()) :: non_neg_integer()
  @doc "Returns list of workers pids."
  @callback to_list(state()) :: list(pid())
  @doc "Returns `true` if the `state` is empty, `false` otherwise."
  @callback empty?(state()) :: boolean()
  @doc "Removes one of workers from `state` and returns it as `{caller, state}`. Returns `:empty` if state is empty."
  @callback pop(state()) :: {worker :: pid(), state()} | :empty
end
