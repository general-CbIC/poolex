# Migration from `poolboy`

If you are using `:poolboy` and want to use `Poolex` instead, then you need to follow three simple steps.

## I. Install the `Poolex` dependency

```diff
# mix.exs
defp deps do
  [
-    {:poolboy, "~> 1.5.0"}
+    {:poolex, "~> 0.5.0"}
  ]
end
```

Well, you can also clean up installed dependencies locally and remove them from the `lock` file.

```bash
mix deps.clean --unlock --unused
```

## II. Update child specs

```diff
# Your Application or Supervisor file
def init(_args) do
  children = [
-    :poolboy.child_spec(:some_pool,
-      name: {:local, :some_pool},
-      worker_module: MyApp.SomeWorker,
-      size: 100,
-      max_overflow: 50
-    )
+    Poolex.child_spec(
+      pool_id: :some_pool,
+      worker_module: MyApp.SomeWorker,
+      workers_count: 100,
+      max_overflow: 50
+    )
  ]

  Supervisor.init(children, strategy: :one_for_one)
end
```

## III. Update call site

```diff
# Use `run!/3` to leave the same behavior. 
# If you want a safe interface with error handling, then use `run/3`.
-  :poolboy.transaction(
-    :some_pool,
-    fn pid -> some_function(pid) end,
-    :timer.seconds(10)
-  )
+  Poolex.run!(
+    :some_pool,
+    fn pid -> some_function(pid) end,
+    timeout: :timer.seconds(10)
+  )
```
