#!/usr/bin/env elixir

# Distributed Tracing Example
# Shows how traces propagate across service boundaries

Mix.install([{:elixir_tracer, path: "."}])

{:ok, _} = Application.ensure_all_started(:elixir_tracer)

IO.puts("\n=== Distributed Tracing Example ===\n")

# Simulate Service A (upstream)
defmodule ServiceA do
  def process_request do
    ElixirTracer.OtherTransaction.start_transaction("ServiceA", "HandleRequest")

    ElixirTracer.Transaction.Reporter.add_attributes(
      service: "A",
      request_id: "req_123"
    )

    # Create trace headers for downstream call
    headers = ElixirTracer.DistributedTrace.create_distributed_trace_payload(:http)

    IO.puts("Service A:")
    tx_a = Process.get(:elixir_tracer_transaction)
    IO.puts("  Trace ID: #{tx_a.trace_id}")
    IO.puts("  Span ID: #{String.slice(tx_a.id, 0..7)}")
    IO.puts("  Headers: #{inspect(headers)}")

    :timer.sleep(10)
    ElixirTracer.OtherTransaction.stop_transaction()

    headers
  end
end

# Simulate Service B (downstream)
defmodule ServiceB do
  def process_request(incoming_headers) do
    ElixirTracer.OtherTransaction.start_transaction("ServiceB", "ProcessData")

    # Accept incoming trace
    ElixirTracer.DistributedTrace.accept_distributed_trace_payload(incoming_headers, :http)

    ElixirTracer.Transaction.Reporter.add_attributes(
      service: "B",
      upstream_headers: incoming_headers
    )

    IO.puts("\nService B:")
    tx_b = Process.get(:elixir_tracer_transaction)
    IO.puts("  Trace ID: #{tx_b.trace_id}")
    IO.puts("  Parent Span: #{tx_b.parent_span_id}")
    IO.puts("  (Notice: Same Trace ID!)")

    :timer.sleep(15)
    ElixirTracer.OtherTransaction.stop_transaction()
  end
end

# Execute the flow
IO.puts("Starting distributed trace flow...\n")

headers = ServiceA.process_request()
ServiceB.process_request(headers)

# Query and show the trace
IO.puts("\n=== Trace Analysis ===\n")

transactions = ElixirTracer.Query.get_transactions()
IO.puts("Transactions in trace: #{length(transactions)}")

Enum.each(transactions, fn tx ->
  IO.puts("\n#{tx.name}:")
  IO.puts("  Trace ID: #{tx.trace_id}")
  IO.puts("  Duration: #{tx.duration_ms}ms")
  IO.puts("  Service: #{tx.custom_attributes[:service]}")

  if tx.parent_span_id do
    IO.puts("  Parent Span: #{tx.parent_span_id}")
  end
end)

# Verify trace continuity
trace_ids = Enum.map(transactions, & &1.trace_id) |> Enum.uniq()
IO.puts("\n✅ All transactions share trace ID: #{length(trace_ids) == 1}")
IO.puts("   Trace ID: #{hd(trace_ids)}")

IO.puts("\n✅ Distributed tracing working!\n")
