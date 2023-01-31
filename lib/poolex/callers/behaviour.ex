defmodule Poolex.Callers.Behaviour do
  @moduledoc """
  Behaviour for callers list implementations.

  `caller` is a process that uses the `Poolex.run/3` function and waits for the execution result.
  """

  @type state() :: any()

  @callback init() :: state()
  @callback add(state(), caller :: pid()) :: state()
  @callback empty?(state()) :: boolean()
  @callback pop(state()) :: {caller :: pid(), state()} | :empty
  @callback remove(state(), caller :: pid()) :: state()
  @callback to_list(state()) :: list(pid())
end
