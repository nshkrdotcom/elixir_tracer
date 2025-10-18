defmodule ElixirTracer.DistributedTraceTest do
  use ElixirTracer.SupertesterCase, async: true

  alias ElixirTracer.DistributedTrace

  describe "create_distributed_trace_payload/1" do
    test "creates W3C traceparent header" do
      Transaction.Reporter.start_transaction(:web, "/test")

      payload = DistributedTrace.create_distributed_trace_payload(:http)

      assert is_map(payload)
      assert Map.has_key?(payload, "traceparent")
      assert Map.has_key?(payload, "tracestate")

      traceparent = payload["traceparent"]
      assert String.starts_with?(traceparent, "00-")
      assert String.length(traceparent) >= 55

      Transaction.Reporter.stop_transaction()
    end

    test "traceparent includes trace_id and span_id" do
      Transaction.Reporter.start_transaction(:web, "/test")
      tx = Process.get(:elixir_tracer_transaction)

      payload = DistributedTrace.create_distributed_trace_payload(:http)
      traceparent = payload["traceparent"]

      # Format: 00-{trace_id}-{parent_id}-{flags}
      parts = String.split(traceparent, "-")
      assert length(parts) == 4
      assert Enum.at(parts, 0) == "00"
      assert Enum.at(parts, 1) == tx.trace_id

      Transaction.Reporter.stop_transaction()
    end

    test "tracestate includes priority" do
      Transaction.Reporter.start_transaction(:web, "/test")

      payload = DistributedTrace.create_distributed_trace_payload(:http)
      tracestate = payload["tracestate"]

      assert String.starts_with?(tracestate, "ed@p=")
      assert String.contains?(tracestate, "0.")

      Transaction.Reporter.stop_transaction()
    end

    test "returns empty map when no transaction" do
      payload = DistributedTrace.create_distributed_trace_payload(:http)
      assert payload == %{}
    end
  end

  describe "accept_distributed_trace_payload/2" do
    test "accepts and propagates trace_id" do
      # Service A creates trace
      Transaction.Reporter.start_transaction(:web, "/service_a")
      tx_a = Process.get(:elixir_tracer_transaction)
      original_trace_id = tx_a.trace_id

      headers = DistributedTrace.create_distributed_trace_payload(:http)
      Transaction.Reporter.stop_transaction()

      # Service B accepts trace
      Transaction.Reporter.start_transaction(:web, "/service_b")
      :ok = DistributedTrace.accept_distributed_trace_payload(headers, :http)

      tx_b = Process.get(:elixir_tracer_transaction)
      assert tx_b.trace_id == original_trace_id
      assert tx_b.parent_span_id != nil

      Transaction.Reporter.stop_transaction()
    end

    test "handles invalid traceparent" do
      payload = %{"traceparent" => "invalid-format"}

      Transaction.Reporter.start_transaction(:web, "/test")
      result = DistributedTrace.accept_distributed_trace_payload(payload, :http)

      assert result == :error

      Transaction.Reporter.stop_transaction()
    end

    test "handles missing traceparent" do
      Transaction.Reporter.start_transaction(:web, "/test")
      result = DistributedTrace.accept_distributed_trace_payload(%{}, :http)

      assert result == :error

      Transaction.Reporter.stop_transaction()
    end

    test "full distributed trace flow" do
      # Upstream service
      Transaction.Reporter.start_transaction(:web, "/upstream")
      Transaction.Reporter.add_attributes(service: "A")

      headers = DistributedTrace.create_distributed_trace_payload(:http)
      tx_upstream = Process.get(:elixir_tracer_transaction)
      upstream_trace_id = tx_upstream.trace_id

      Transaction.Reporter.stop_transaction()

      # Downstream service
      Transaction.Reporter.start_transaction(:web, "/downstream")
      DistributedTrace.accept_distributed_trace_payload(headers, :http)
      Transaction.Reporter.add_attributes(service: "B")

      tx_downstream = Process.get(:elixir_tracer_transaction)

      # Trace ID propagated
      assert tx_downstream.trace_id == upstream_trace_id

      Transaction.Reporter.stop_transaction()

      # Both transactions share trace_id
      txs = Query.get_transactions()
      trace_ids = Enum.map(txs, & &1.trace_id) |> Enum.uniq()
      assert length(trace_ids) == 1
      assert hd(trace_ids) == upstream_trace_id
    end
  end
end
