defmodule Poolex.Caller do
  @moduledoc """
  Caller structure.

  **Callers** are processes that have requested to get a worker.
  """

  defstruct from: nil,
            reference: nil

  @type t() :: %__MODULE__{
          from: GenServer.from(),
          reference: reference()
        }
end
