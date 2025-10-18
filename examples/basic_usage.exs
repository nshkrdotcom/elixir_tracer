#!/usr/bin/env elixir

# Basic Usage Example for ElixirTracer
# Run with: elixir -pa _build/dev/lib/*/ebin examples/basic_usage.exs

Mix.install([{:elixir_tracer, path: "."}])

# Start the application
{:ok, _} = Application.ensure_all_started(:elixir_tracer)

IO.puts("\n=== ElixirTracer Basic Usage Example ===\n")

# Example 1: Simple Transaction
IO.puts("1. Creating a simple transaction...")

ElixirTracer.OtherTransaction.start_transaction("Example", "BasicUsage")

ElixirTracer.Transaction.Reporter.add_attributes(
  example_number: 1,
  description: "Basic transaction"
)

:timer.sleep(10)
{:ok, tx} = ElixirTracer.OtherTransaction.stop_transaction()

IO.puts("   ✓ Transaction: #{tx.name}")
IO.puts("   ✓ Duration: #{tx.duration_ms}ms")
IO.puts("   ✓ Attributes: #{inspect(tx.custom_attributes)}")

# Example 2: Transaction with Spans
IO.puts("\n2. Transaction with database spans...")

ElixirTracer.OtherTransaction.start_transaction("Example", "WithSpans")

span1 =
  ElixirTracer.Span.Reporter.report_span(
    name: "Datastore/PostgreSQL/users/SELECT",
    category: :datastore,
    duration_s: 0.042,
    attributes: %{
      "db.statement" => "SELECT * FROM users WHERE id = $1",
      "db.table" => "users",
      "db.operation" => "SELECT"
    }
  )

IO.puts("   ✓ Span created: #{span1.name}")
IO.puts("   ✓ Duration: #{span1.duration_s}s")

ElixirTracer.OtherTransaction.stop_transaction()

# Example 3: Error Tracking
IO.puts("\n3. Error tracking...")

ElixirTracer.OtherTransaction.start_transaction("Example", "WithError")

try do
  raise RuntimeError, "Simulated error for demo"
rescue
  e ->
    error =
      ElixirTracer.Error.Reporter.notice_error(e, %{
        context: "payment_processing",
        user_id: 12345
      })

    IO.puts("   ✓ Error captured: #{error.error_type}")
    IO.puts("   ✓ Message: #{error.message}")
    IO.puts("   ✓ Custom attrs: #{inspect(error.user_attributes)}")
end

ElixirTracer.OtherTransaction.stop_transaction()

# Example 4: Metrics
IO.puts("\n4. Reporting metrics...")

ElixirTracer.Metric.Reporter.report_metric(
  {:datastore, "PostgreSQL", "orders", "INSERT"},
  duration_s: 0.023
)

ElixirTracer.Metric.Reporter.report_metric(
  {:datastore, "PostgreSQL", "orders", "INSERT"},
  duration_s: 0.031
)

ElixirTracer.Metric.Reporter.increment_metric("Custom/PageViews")
ElixirTracer.Metric.Reporter.increment_metric("Custom/PageViews")

IO.puts("   ✓ Metrics reported")

# Example 5: Custom Events
IO.puts("\n5. Custom events...")

ElixirTracer.CustomEvent.Reporter.report_custom_event("UserSignup", %{
  email: "demo@example.com",
  plan: "premium",
  source: "marketing_campaign"
})

ElixirTracer.CustomEvent.Reporter.report_custom_event("PurchaseCompleted", %{
  amount: 99.99,
  currency: "USD",
  product: "widget"
})

IO.puts("   ✓ Custom events reported")

# Query the data
IO.puts("\n=== Querying Collected Data ===\n")

stats = ElixirTracer.Query.get_stats()
IO.puts("Storage Statistics:")
IO.puts("  Transactions: #{stats.transactions}")
IO.puts("  Spans: #{stats.spans}")
IO.puts("  Errors: #{stats.errors}")
IO.puts("  Metrics: #{stats.metrics}")
IO.puts("  Custom Events: #{stats.custom_events}")
IO.puts("  Storage: #{stats.storage_type} (#{stats.storage_path})")

IO.puts("\nRecent Transactions:")

ElixirTracer.Query.get_transactions(limit: 5)
|> Enum.each(fn tx ->
  IO.puts("  • #{tx.name} - #{tx.duration_ms}ms")
end)

IO.puts("\nSpans:")

ElixirTracer.Query.get_spans()
|> Enum.each(fn span ->
  IO.puts("  • #{span.name} - #{span.duration_s}s (#{span.category})")
end)

IO.puts("\nErrors:")

ElixirTracer.Query.get_errors()
|> Enum.each(fn error ->
  IO.puts("  • #{error.error_type}: #{error.message}")
end)

IO.puts("\nMetrics:")

ElixirTracer.Query.get_metrics()
|> Enum.each(fn metric ->
  avg = metric.total_call_time / metric.call_count
  IO.puts("  • #{metric.name}")
  IO.puts("    Calls: #{metric.call_count}, Avg: #{Float.round(avg, 3)}s")
end)

IO.puts("\nCustom Events:")

ElixirTracer.Query.get_custom_events()
|> Enum.each(fn event ->
  IO.puts("  • #{event.type}: #{inspect(event.attributes)}")
end)

IO.puts("\n✅ Example complete!\n")
