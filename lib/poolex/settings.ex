defmodule Poolex.Settings do
  @moduledoc false
  @impl_types ~w(idle_workers busy_workers waiting_callers)a
  @table_name :poolex_settings

  @type impl_type() :: :idle_workers | :busy_workers | :waiting_callers

  @doc false
  @spec init() :: :ok
  def init do
    case :ets.info(@table_name) do
      :undefined -> :ets.new(@table_name, [:set, :named_table, :public])
      _ -> nil
    end

    :ok
  end

  @doc false
  @spec set_implementation(Poolex.pool_id(), impl_type(), module()) :: :ok
  def set_implementation(pool_id, impl_type, impl_module) when impl_type in @impl_types do
    :ets.insert(@table_name, {{pool_id, impl_type}, impl_module})

    :ok
  end

  @doc false
  @spec get_implementation(Poolex.pool_id(), impl_type()) :: module()
  def get_implementation(pool_id, impl_type) when impl_type in @impl_types do
    [{{_pool_id, _impl_type}, impl_module}] = :ets.lookup(@table_name, {pool_id, impl_type})

    impl_module
  end
end
