defmodule PoolexDoctestTest do
  # Kept out of the parameterized `PoolexTest`: there every doctest would run once per parameter set,
  # and the examples register pools under fixed names that outlive (`Poolex.start/1`) or shut down
  # asynchronously after (`Poolex.start_link/1`) the test that started them.
  use ExUnit.Case

  doctest Poolex
end
