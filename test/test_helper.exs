ExUnit.start()

Registry.start_link(keys: :unique, name: PoolexTestRegistry)

:ok = Application.ensure_started(:logger)
Logger.configure(level: :warning)
