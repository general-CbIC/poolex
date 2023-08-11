defmodule Poolex.CheckoutTimeoutError do
  @moduledoc """
  Raised on using `Poolex.run!/3` when a checkout times out.
  """

  defexception message: "checkout timeout"
end
