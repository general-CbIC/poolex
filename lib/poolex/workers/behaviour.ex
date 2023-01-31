defmodule Poolex.Workers.Behaviour do
  @moduledoc """
  Behaviour for worker list implementations.
  """

  @type state() :: any()

  @callback init() :: state()
  @callback add(state(), worker :: pid()) :: state()
  @callback member?(state(), worker :: pid()) :: boolean()
  @callback remove(state(), worker :: pid()) :: state()
  @callback count(state()) :: non_neg_integer()
  @callback to_list(state()) :: list(pid())
end
