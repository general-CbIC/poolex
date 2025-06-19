defmodule Poolex.Private.Options.Parser do
  @moduledoc false

  alias Poolex.Private.Options.Parsed

  # Interval between retry attempts for workers that failed to start (1 second by default)
  @default_failed_workers_retry_interval to_timeout(second: 1)

  @spec parse(list(Poolex.poolex_option())) :: Parsed.t()
  def parse(options) do
    %Parsed{
      busy_workers_impl: parse_optional_module(options, :busy_workers_impl, Poolex.Workers.Impl.List),
      failed_workers_retry_interval:
        parse_optional_timeout(options, :failed_workers_retry_interval, @default_failed_workers_retry_interval),
      idle_overflowed_workers_impl:
        parse_optional_module(options, :idle_overflowed_workers_impl, Poolex.Workers.Impl.List),
      idle_workers_impl: parse_optional_module(options, :idle_workers_impl, Poolex.Workers.Impl.List),
      max_overflow: parse_optional_non_neg_integer(options, :max_overflow, 0),
      pool_id: parse_pool_id(options),
      pool_size_metrics: parse_optional_boolean(options, :pool_size_metrics, false),
      waiting_callers_impl: parse_optional_module(options, :waiting_callers_impl, Poolex.Callers.Impl.ErlangQueue),
      worker_args: parse_optional_list(options, :worker_args, []),
      worker_module: parse_required_module(options, :worker_module),
      worker_shutdown_delay: parse_optional_timeout(options, :worker_shutdown_delay, 0),
      worker_start_fun: parse_optional_atom(options, :worker_start_fun, :start_link),
      workers_count: parse_required_non_neg_integer(options, :workers_count)
    }
  end

  @doc false
  def parse_pool_id(options) do
    case Keyword.get(options, :pool_id) do
      nil -> Keyword.fetch!(options, :worker_module)
      pool_id -> pool_id
    end
  end

  defp parse_optional_atom(options, key, default) do
    options
    |> parse_optional_option(key, default)
    |> validate_atom()
  end

  defp parse_optional_list(options, key, default) do
    options
    |> parse_optional_option(key, default)
    |> valiadate_list()
  end

  defp parse_optional_boolean(options, key, default) do
    options
    |> parse_optional_option(key, default)
    |> validate_boolean()
  end

  defp parse_optional_module(options, key, default) do
    options
    |> parse_optional_option(key, default)
    |> validate_module()
  end

  defp parse_required_module(options, key) do
    options
    |> parse_required_option(key)
    |> validate_module()
  end

  defp parse_optional_timeout(options, key, default) do
    options
    |> parse_optional_option(key, default)
    |> validate_timeout()
  end

  defp parse_required_non_neg_integer(options, key) do
    options
    |> parse_required_option(key)
    |> validate_non_neg_integer()
  end

  defp parse_optional_non_neg_integer(options, key, default) do
    options
    |> parse_optional_option(key, default)
    |> validate_non_neg_integer()
  end

  # Universal parse functions
  defp parse_required_option(options, key) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Missing required option: #{inspect(key)}"
    end
  end

  defp parse_optional_option(options, key, default) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  # Validators
  defp validate_module(value) when is_atom(value) do
    if Code.ensure_loaded?(value) do
      value
    else
      raise ArgumentError, "Module #{inspect(value)} is not loaded or does not exist"
    end
  end

  defp validate_module(value) do
    raise ArgumentError, "Expected a module atom, got: #{inspect(value)}"
  end

  defp validate_non_neg_integer(value) when is_integer(value) and value >= 0 do
    value
  end

  defp validate_non_neg_integer(value) do
    raise ArgumentError, "Expected a non-negative integer, got: #{inspect(value)}"
  end

  defp validate_timeout(value) when is_integer(value) and value >= 0 do
    value
  end

  defp validate_timeout(:infinity) do
    :infinity
  end

  defp validate_timeout(value) do
    raise ArgumentError, "Expected a non-negative integer or :infinity, got: #{inspect(value)}"
  end

  defp validate_boolean(value) when is_boolean(value) do
    value
  end

  defp validate_boolean(value) do
    raise ArgumentError, "Expected a boolean value, got: #{inspect(value)}"
  end

  defp valiadate_list(value) when is_list(value) do
    value
  end

  defp valiadate_list(value) do
    raise ArgumentError, "Expected a list, got: #{inspect(value)}"
  end

  defp validate_atom(value) when is_atom(value) do
    value
  end

  defp validate_atom(value) do
    raise ArgumentError, "Expected an atom, got: #{inspect(value)}"
  end
end
