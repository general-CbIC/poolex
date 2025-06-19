defmodule Poolex.Private.Options.ParserTest do
  use ExUnit.Case, async: true

  alias Poolex.Callers.Impl.ErlangQueue
  alias Poolex.Private.Options.Parsed
  alias Poolex.Private.Options.Parser

  setup do
    [
      options: [
        pool_id: :test_pool,
        worker_module: SomeWorker,
        workers_count: 5,
        busy_workers_impl: Poolex.Workers.Impl.List,
        idle_workers_impl: Poolex.Workers.Impl.List,
        idle_overflowed_workers_impl: Poolex.Workers.Impl.List,
        waiting_callers_impl: ErlangQueue,
        failed_workers_retry_interval: 1000,
        max_overflow: 2,
        pool_size_metrics: true,
        worker_args: [arg1: "value1", arg2: "value2"],
        worker_shutdown_delay: 500,
        worker_start_fun: :start_link
      ]
    ]
  end

  test "parse/1 with valid options returns a Parsed struct", %{options: options} do
    expected = %Parsed{
      pool_id: :test_pool,
      worker_module: SomeWorker,
      workers_count: 5,
      busy_workers_impl: Poolex.Workers.Impl.List,
      idle_workers_impl: Poolex.Workers.Impl.List,
      idle_overflowed_workers_impl: Poolex.Workers.Impl.List,
      waiting_callers_impl: ErlangQueue,
      failed_workers_retry_interval: 1000,
      max_overflow: 2,
      pool_size_metrics: true,
      worker_args: [arg1: "value1", arg2: "value2"],
      worker_shutdown_delay: 500,
      worker_start_fun: :start_link
    }

    assert Parser.parse(options) == expected
  end

  describe "busy_workers_impl validation" do
    test "parse/1 with non-atom busy_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :busy_workers_impl, "not_an_atom")

      assert_raise ArgumentError, "Expected a module atom, got: \"not_an_atom\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with integer busy_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :busy_workers_impl, 123)

      assert_raise ArgumentError, "Expected a module atom, got: 123", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with list busy_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :busy_workers_impl, [:some, :list])

      assert_raise ArgumentError, "Expected a module atom, got: [:some, :list]", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with non-existent module busy_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :busy_workers_impl, :NonExistentModule)

      assert_raise ArgumentError, "Module :NonExistentModule is not loaded or does not exist", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without busy_workers_impl uses default value", %{options: options} do
      options_without_busy_workers_impl = Keyword.delete(options, :busy_workers_impl)

      result = Parser.parse(options_without_busy_workers_impl)

      assert result.busy_workers_impl == Poolex.Workers.Impl.List
    end
  end

  describe "failed_workers_retry_interval validation" do
    test "parse/1 with valid timeout values", %{options: options} do
      # Test with positive integer
      options_with_timeout = Keyword.put(options, :failed_workers_retry_interval, 5000)
      result = Parser.parse(options_with_timeout)
      assert result.failed_workers_retry_interval == 5000

      # Test with zero
      options_with_zero = Keyword.put(options, :failed_workers_retry_interval, 0)
      result = Parser.parse(options_with_zero)
      assert result.failed_workers_retry_interval == 0

      # Test with :infinity
      options_with_infinity = Keyword.put(options, :failed_workers_retry_interval, :infinity)
      result = Parser.parse(options_with_infinity)
      assert result.failed_workers_retry_interval == :infinity
    end

    test "parse/1 with negative integer failed_workers_retry_interval raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :failed_workers_retry_interval, -100)

      assert_raise ArgumentError, "Expected a non-negative integer or :infinity, got: -100", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with float failed_workers_retry_interval raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :failed_workers_retry_interval, 1.5)

      assert_raise ArgumentError, "Expected a non-negative integer or :infinity, got: 1.5", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with string failed_workers_retry_interval raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :failed_workers_retry_interval, "1000")

      assert_raise ArgumentError, "Expected a non-negative integer or :infinity, got: \"1000\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with atom (not :infinity) failed_workers_retry_interval raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :failed_workers_retry_interval, :some_atom)

      assert_raise ArgumentError, "Expected a non-negative integer or :infinity, got: :some_atom", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without failed_workers_retry_interval uses default value", %{options: options} do
      options_without_interval = Keyword.delete(options, :failed_workers_retry_interval)

      result = Parser.parse(options_without_interval)

      # Default is 1 second (1000ms)
      assert result.failed_workers_retry_interval == 1000
    end
  end
end
