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

  describe "idle_overflowed_workers_impl validation" do
    test "parse/1 with non-atom idle_overflowed_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :idle_overflowed_workers_impl, "not_an_atom")

      assert_raise ArgumentError, "Expected a module atom, got: \"not_an_atom\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with integer idle_overflowed_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :idle_overflowed_workers_impl, 456)

      assert_raise ArgumentError, "Expected a module atom, got: 456", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with map idle_overflowed_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :idle_overflowed_workers_impl, %{key: "value"})

      assert_raise ArgumentError, "Expected a module atom, got: %{key: \"value\"}", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with non-existent module idle_overflowed_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :idle_overflowed_workers_impl, :AnotherNonExistentModule)

      assert_raise ArgumentError, "Module :AnotherNonExistentModule is not loaded or does not exist", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without idle_overflowed_workers_impl uses default value", %{options: options} do
      options_without_impl = Keyword.delete(options, :idle_overflowed_workers_impl)

      result = Parser.parse(options_without_impl)

      assert result.idle_overflowed_workers_impl == Poolex.Workers.Impl.List
    end
  end

  describe "idle_workers_impl validation" do
    test "parse/1 with non-atom idle_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :idle_workers_impl, [1, 2, 3])

      assert_raise ArgumentError, "Expected a module atom, got: [1, 2, 3]", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with non-existent module idle_workers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :idle_workers_impl, :IdleWorkersModule)

      assert_raise ArgumentError, "Module :IdleWorkersModule is not loaded or does not exist", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without idle_workers_impl uses default value", %{options: options} do
      options_without_impl = Keyword.delete(options, :idle_workers_impl)

      result = Parser.parse(options_without_impl)

      assert result.idle_workers_impl == Poolex.Workers.Impl.List
    end
  end

  describe "max_overflow validation" do
    test "parse/1 with valid max_overflow values", %{options: options} do
      # Test with positive integer
      options_with_overflow = Keyword.put(options, :max_overflow, 10)
      result = Parser.parse(options_with_overflow)
      assert result.max_overflow == 10

      # Test with zero
      options_with_zero = Keyword.put(options, :max_overflow, 0)
      result = Parser.parse(options_with_zero)
      assert result.max_overflow == 0
    end

    test "parse/1 with negative max_overflow raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :max_overflow, -5)

      assert_raise ArgumentError, "Expected a non-negative integer, got: -5", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with float max_overflow raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :max_overflow, 2.5)

      assert_raise ArgumentError, "Expected a non-negative integer, got: 2.5", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with string max_overflow raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :max_overflow, "5")

      assert_raise ArgumentError, "Expected a non-negative integer, got: \"5\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without max_overflow uses default value", %{options: options} do
      options_without_overflow = Keyword.delete(options, :max_overflow)

      result = Parser.parse(options_without_overflow)

      assert result.max_overflow == 0
    end
  end

  describe "pool_size_metrics validation" do
    test "parse/1 with valid pool_size_metrics values", %{options: options} do
      # Test with true
      options_with_true = Keyword.put(options, :pool_size_metrics, true)
      result = Parser.parse(options_with_true)
      assert result.pool_size_metrics == true

      # Test with false
      options_with_false = Keyword.put(options, :pool_size_metrics, false)
      result = Parser.parse(options_with_false)
      assert result.pool_size_metrics == false
    end

    test "parse/1 with string pool_size_metrics raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :pool_size_metrics, "true")

      assert_raise ArgumentError, "Expected a boolean value, got: \"true\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with integer pool_size_metrics raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :pool_size_metrics, 1)

      assert_raise ArgumentError, "Expected a boolean value, got: 1", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with atom pool_size_metrics raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :pool_size_metrics, :yes)

      assert_raise ArgumentError, "Expected a boolean value, got: :yes", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without pool_size_metrics uses default value", %{options: options} do
      options_without_metrics = Keyword.delete(options, :pool_size_metrics)

      result = Parser.parse(options_without_metrics)

      assert result.pool_size_metrics == false
    end
  end

  describe "waiting_callers_impl validation" do
    test "parse/1 with non-atom waiting_callers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :waiting_callers_impl, {:tuple, :value})

      assert_raise ArgumentError, "Expected a module atom, got: {:tuple, :value}", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with non-existent module waiting_callers_impl raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :waiting_callers_impl, :WaitingCallersModule)

      assert_raise ArgumentError, "Module :WaitingCallersModule is not loaded or does not exist", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without waiting_callers_impl uses default value", %{options: options} do
      options_without_impl = Keyword.delete(options, :waiting_callers_impl)

      result = Parser.parse(options_without_impl)

      assert result.waiting_callers_impl == Poolex.Callers.Impl.ErlangQueue
    end
  end

  describe "worker_args validation" do
    test "parse/1 with valid worker_args values", %{options: options} do
      # Test with keyword list
      options_with_keyword = Keyword.put(options, :worker_args, [timeout: 5000, retries: 3])
      result = Parser.parse(options_with_keyword)
      assert result.worker_args == [timeout: 5000, retries: 3]

      # Test with simple list
      options_with_list = Keyword.put(options, :worker_args, [1, 2, 3])
      result = Parser.parse(options_with_list)
      assert result.worker_args == [1, 2, 3]

      # Test with empty list
      options_with_empty = Keyword.put(options, :worker_args, [])
      result = Parser.parse(options_with_empty)
      assert result.worker_args == []
    end

    test "parse/1 with string worker_args raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_args, "not a list")

      assert_raise ArgumentError, "Expected a list, got: \"not a list\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with integer worker_args raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_args, 123)

      assert_raise ArgumentError, "Expected a list, got: 123", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with map worker_args raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_args, %{key: "value"})

      assert_raise ArgumentError, "Expected a list, got: %{key: \"value\"}", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without worker_args uses default value", %{options: options} do
      options_without_args = Keyword.delete(options, :worker_args)

      result = Parser.parse(options_without_args)

      assert result.worker_args == []
    end
  end

  describe "worker_module validation" do
    test "parse/1 without worker_module raises ArgumentError", %{options: options} do
      options_without_module = Keyword.delete(options, :worker_module)

      assert_raise ArgumentError, "Missing required option: :worker_module", fn ->
        Parser.parse(options_without_module)
      end
    end

    test "parse/1 with non-atom worker_module raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_module, "SomeWorker")

      assert_raise ArgumentError, "Expected a module atom, got: \"SomeWorker\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with non-existent worker_module raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_module, :NonExistentWorkerModule)

      assert_raise ArgumentError, "Module :NonExistentWorkerModule is not loaded or does not exist", fn ->
        Parser.parse(invalid_options)
      end
    end
  end

  describe "worker_shutdown_delay validation" do
    test "parse/1 with valid worker_shutdown_delay values", %{options: options} do
      # Test with positive integer
      options_with_delay = Keyword.put(options, :worker_shutdown_delay, 2000)
      result = Parser.parse(options_with_delay)
      assert result.worker_shutdown_delay == 2000

      # Test with zero
      options_with_zero = Keyword.put(options, :worker_shutdown_delay, 0)
      result = Parser.parse(options_with_zero)
      assert result.worker_shutdown_delay == 0

      # Test with :infinity
      options_with_infinity = Keyword.put(options, :worker_shutdown_delay, :infinity)
      result = Parser.parse(options_with_infinity)
      assert result.worker_shutdown_delay == :infinity
    end

    test "parse/1 with negative worker_shutdown_delay raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_shutdown_delay, -500)

      assert_raise ArgumentError, "Expected a non-negative integer or :infinity, got: -500", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with string worker_shutdown_delay raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_shutdown_delay, "500")

      assert_raise ArgumentError, "Expected a non-negative integer or :infinity, got: \"500\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without worker_shutdown_delay uses default value", %{options: options} do
      options_without_delay = Keyword.delete(options, :worker_shutdown_delay)

      result = Parser.parse(options_without_delay)

      assert result.worker_shutdown_delay == 0
    end
  end

  describe "worker_start_fun validation" do
    test "parse/1 with valid worker_start_fun values", %{options: options} do
      # Test with custom atom
      options_with_custom = Keyword.put(options, :worker_start_fun, :start)
      result = Parser.parse(options_with_custom)
      assert result.worker_start_fun == :start

      # Test with another atom
      options_with_another = Keyword.put(options, :worker_start_fun, :init)
      result = Parser.parse(options_with_another)
      assert result.worker_start_fun == :init
    end

    test "parse/1 with string worker_start_fun raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_start_fun, "start_link")

      assert_raise ArgumentError, "Expected an atom, got: \"start_link\"", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with integer worker_start_fun raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :worker_start_fun, 42)

      assert_raise ArgumentError, "Expected an atom, got: 42", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 without worker_start_fun uses default value", %{options: options} do
      options_without_fun = Keyword.delete(options, :worker_start_fun)

      result = Parser.parse(options_without_fun)

      assert result.worker_start_fun == :start_link
    end
  end

  describe "workers_count validation" do
    test "parse/1 with valid workers_count values", %{options: options} do
      # Test with positive integer
      options_with_count = Keyword.put(options, :workers_count, 10)
      result = Parser.parse(options_with_count)
      assert result.workers_count == 10

      # Test with zero (edge case)
      options_with_zero = Keyword.put(options, :workers_count, 0)
      result = Parser.parse(options_with_zero)
      assert result.workers_count == 0
    end

    test "parse/1 without workers_count raises ArgumentError", %{options: options} do
      options_without_count = Keyword.delete(options, :workers_count)

      assert_raise ArgumentError, "Missing required option: :workers_count", fn ->
        Parser.parse(options_without_count)
      end
    end

    test "parse/1 with negative workers_count raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :workers_count, -3)

      assert_raise ArgumentError, "Expected a non-negative integer, got: -3", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with float workers_count raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :workers_count, 5.5)

      assert_raise ArgumentError, "Expected a non-negative integer, got: 5.5", fn ->
        Parser.parse(invalid_options)
      end
    end

    test "parse/1 with string workers_count raises ArgumentError", %{options: options} do
      invalid_options = Keyword.put(options, :workers_count, "5")

      assert_raise ArgumentError, "Expected a non-negative integer, got: \"5\"", fn ->
        Parser.parse(invalid_options)
      end
    end
  end

  describe "pool_id validation" do
    test "parse/1 with explicit pool_id uses provided value", %{options: options} do
      options_with_custom_id = Keyword.put(options, :pool_id, :my_custom_pool)
      result = Parser.parse(options_with_custom_id)
      assert result.pool_id == :my_custom_pool
    end

    test "parse/1 without pool_id uses worker_module as default", %{options: options} do
      options_without_pool_id = Keyword.delete(options, :pool_id)
      result = Parser.parse(options_without_pool_id)
      assert result.pool_id == SomeWorker
    end
  end
end
