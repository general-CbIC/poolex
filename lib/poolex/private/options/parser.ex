defmodule Poolex.Private.Options.Parser do
  @moduledoc false

  alias Poolex.Private.Options.Parsed

  # Interval between retry attempts for workers that failed to start (1 second by default)
  @default_failed_workers_retry_interval to_timeout(second: 1)

  @spec parse(list(Poolex.poolex_option())) :: Parsed.t()
  def parse(options) do
    %Parsed{
      busy_workers_impl: parse_optional_option(options, :busy_workers_impl, Poolex.Workers.Impl.List),
      idle_workers_impl: parse_optional_option(options, :idle_workers_impl, Poolex.Workers.Impl.List),
      idle_overflowed_workers_impl:
        parse_optional_option(options, :idle_overflowed_workers_impl, Poolex.Workers.Impl.List),
      waiting_callers_impl: parse_optional_option(options, :waiting_callers_impl, Poolex.Callers.Impl.ErlangQueue),
      failed_workers_retry_interval:
        parse_optional_option(options, :failed_workers_retry_interval, @default_failed_workers_retry_interval),
      max_overflow: parse_optional_option(options, :max_overflow, 0),
      worker_shutdown_delay: parse_optional_option(options, :worker_shutdown_delay, 0),
      pool_id: parse_pool_id(options),
      worker_args: parse_optional_option(options, :worker_args, []),
      worker_module: parse_required_option(options, :worker_module),
      worker_start_fun: parse_optional_option(options, :worker_start_fun, :start_link),
      workers_count: parse_required_option(options, :workers_count),
      pool_size_metrics: parse_optional_option(options, :pool_size_metrics, false)
    }
  end

  @doc false
  def parse_pool_id(options) do
    case Keyword.get(options, :pool_id) do
      nil -> Keyword.fetch!(options, :worker_module)
      pool_id -> pool_id
    end
  end

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
end
