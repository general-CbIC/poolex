defmodule Poolex.PromEx do
  @moduledoc """
  This is a plugin for your application to collect metrics with PromEx.

  To use this plugin, you need to add `:prom_ex` to your dependencies in `mix.exs`:

  ```elixir
  defp deps do
    [
      {:prom_ex, "~> 1.0"}
    ]
  end
  ```

  Then you need to add this plugin to plugins list in your `PromEx` configuration:

  ```elixir
  defmodule MyCoolApp.PromEx do
    use PromEx, otp_app: :my_cool_app

    @impl PromEx
    def plugins do
      [
        Poolex.PromEx
      ]
    end
  end
  ```

  Additional information about `PromEx` installation and configuration can be found in the `PromEx` documentation: https://hexdocs.pm/prom_ex/readme.html#installation.
  """

  if Code.ensure_loaded(PromEx) == {:module, PromEx} do
    use PromEx.Plugin

    @impl PromEx.Plugin
    def event_metrics(_opts) do
      Event.build(
        :poolex,
        [
          last_value(
            "poolex_idle_workers_count",
            event_name: [:poolex, :metrics, :pool_size],
            tags: [:pool_id],
            measurement: :idle_workers_count,
            description: "[Poolex] idle workers count"
          ),
          last_value(
            "poolex_busy_workers_count",
            event_name: [:poolex, :metrics, :pool_size],
            tags: [:pool_id],
            measurement: :busy_workers_count,
            description: "[Poolex] busy workers count"
          ),
          last_value(
            "poolex_is_max_overflowed",
            event_name: [:poolex, :metrics, :pool_size],
            tags: [:pool_id],
            measurement: :overflowed,
            description: "[Poolex] is pool overflowed?"
          )
        ]
      )
    end
  end
end
