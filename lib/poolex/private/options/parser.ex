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
      pool_size_metrics: parse_optional_option(options, :pool_size_metrics, false),
      waiting_callers_impl: parse_optional_module(options, :waiting_callers_impl, Poolex.Callers.Impl.ErlangQueue),
      worker_args: parse_optional_option(options, :worker_args, []),
      worker_module: parse_required_module(options, :worker_module),
      worker_shutdown_delay: parse_optional_timeout(options, :worker_shutdown_delay, 0),
      worker_start_fun: parse_optional_option(options, :worker_start_fun, :start_link),
      workers_count: parse_required_option(options, :workers_count)
    }
  end

  @doc false
  def parse_pool_id(options) do
    case Keyword.get(options, :pool_id) do
      nil -> Keyword.fetch!(options, :worker_module)
      pool_id -> pool_id
    end
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
    |> case do
      value when is_integer(value) and value >= 0 -> value
      :infinity -> :infinity
      value -> raise ArgumentError, "Expected non-negative integer for #{inspect(key)}. Got: #{value}"
    end
  end

  defp parse_optional_non_neg_integer(options, key, default) do
    options
    |> parse_optional_option(key, default)
    |> case do
      value when is_integer(value) and value >= 0 -> value
      value -> raise ArgumentError, "Expected non-negative integer for #{inspect(key)}. Got: #{value}"
    end
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
end
