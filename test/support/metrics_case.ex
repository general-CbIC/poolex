defmodule Poolex.MetricsCase do
  @moduledoc """
  This module defines the setup for tests requiring metrics tests.

  Available tags:
    - `telemetry_events`: list the Telemetry events to listen
    - `metrics`: Specify the list of Telemetry.Metrics to used (format: [Module, :function, [args]])

  Available assertions:
    - `assert_telemetry_event(name, measurements, metadata \\ %{})`
    - `assert_metric(name, measurement, metadata \\ %{})`

  ## Example:

  @tag telemetry_events: [[:user, :subscription, :email_confirmation]],
       metrics: [MayApp.Metrics, :metrics, []]
  test "my test" do
    ...
    assert_telemetry_event([:user, :subscription, :email_confirmation], %{count: 1}, %{result: :error})
    assert_metric([:user, :subscription, :email_confirmation, :count], 1, %{success: false})
  end

  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Poolex.MetricsCase
    end
  end

  setup tags do
    if telemetry_events = tags[:telemetry_events] do
      metrics = get_metrics_from_tag(tags)

      self = self()

      groups = Enum.group_by(metrics, & &1.event_name)

      :telemetry.attach_many(
        tags[:test],
        telemetry_events,
        fn name, measurements, metadata, _config ->
          send(self, {:telemetry_event, name, measurements, metadata})

          # Send related metrics
          if Enum.count(metrics) > 0 do
            Enum.each(Map.get(groups, name, []), fn metric ->
              send(
                self,
                {:metric, metric.name, Map.get(measurements, metric.measurement), extract_tags(metric, metadata)}
              )
            end)
          end
        end,
        nil
      )
    end

    :ok
  end

  defp extract_tags(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Map.take(tag_values, metric.tags)
  end

  defp get_metrics_from_tag(%{metrics: [m, f, args]}) do
    apply(m, f, args)
  end

  defp get_metrics_from_tag(_) do
    []
  end

  @doc """
  Assert that given event has been sent.
  """
  defmacro assert_telemetry_event(name, measurements, metadata \\ %{}),
    do: do_assert_telemetry_event(name, measurements, metadata)

  defp do_assert_telemetry_event(name, measurements, %{}) do
    do_assert_telemetry_event(name, measurements, Macro.escape(%{}))
  end

  defp do_assert_telemetry_event(name, measurements, metadata) do
    do_assert_receive(:telemetry_event, name, measurements, metadata)
  end

  defmacro assert_metric(name, measurement, metadata \\ %{}),
    do: do_assert_metric(name, measurement, metadata)

  defp do_assert_metric(name, measurement, %{}) do
    do_assert_metric(name, measurement, Macro.escape(%{}))
  end

  defp do_assert_metric(name, measurement, metadata) do
    do_assert_receive(:metric, name, measurement, metadata)
  end

  defp do_assert_receive(msg_type, name, measurement, metadata) do
    quote do
      assert_receive {unquote(msg_type), unquote(name), unquote(measurement), unquote(metadata)}
    end
  end
end
