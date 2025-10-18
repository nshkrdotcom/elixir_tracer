defmodule ElixirTracer.SpanTest do
  use ElixirTracer.SupertesterCase, async: true

  describe "Span.Reporter" do
    test "report_span creates span with all fields" do
      Transaction.Reporter.start_transaction(:web, "/test")

      span =
        Span.Reporter.report_span(
          name: "TestOperation",
          category: :generic,
          duration_s: 0.123,
          timestamp_ms: 1_234_567_890,
          attributes: %{"custom" => "value"}
        )

      assert span.name == "TestOperation"
      assert span.category == :generic
      assert span.duration_s == 0.123
      assert span.timestamp == 1_234_567_890
      assert span.attributes["custom"] == "value"
      assert is_binary(span.id)

      Transaction.Reporter.stop_transaction()
    end

    test "span inherits transaction context" do
      Transaction.Reporter.start_transaction(:web, "/test")
      tx = Process.get(:elixir_tracer_transaction)

      span =
        Span.Reporter.report_span(
          name: "Operation",
          duration_s: 0.1,
          category: :generic
        )

      assert span.transaction_id == tx.id
      assert span.trace_id == tx.trace_id
      assert span.priority == tx.priority

      Transaction.Reporter.stop_transaction()
    end

    test "span without transaction still works" do
      span =
        Span.Reporter.report_span(
          name: "Standalone",
          duration_s: 0.05,
          category: :generic
        )

      assert span.name == "Standalone"
      assert span.transaction_id == nil

      # Still stored
      spans = Query.get_spans()
      assert length(spans) == 1
    end

    test "span categories" do
      for category <- [:generic, :http, :datastore, :error] do
        Storage.clear_all()

        span =
          Span.Reporter.report_span(
            name: "Test",
            duration_s: 0.1,
            category: category
          )

        assert span.category == category
      end
    end

    test "datastore span attributes" do
      span =
        Span.Reporter.report_span(
          name: "Datastore/PostgreSQL/users/SELECT",
          category: :datastore,
          duration_s: 0.042,
          attributes: %{
            "db.statement" => "SELECT * FROM users",
            "db.instance" => "prod_db",
            "peer.hostname" => "db.example.com",
            "db.table" => "users",
            "db.operation" => "SELECT"
          }
        )

      assert span.category == :datastore
      assert span.attributes["db.statement"] == "SELECT * FROM users"
      assert span.attributes["db.table"] == "users"
    end

    test "http span attributes" do
      span =
        Span.Reporter.report_span(
          name: "External/api.example.com/POST",
          category: :http,
          duration_s: 0.234,
          attributes: %{
            "http.url" => "https://api.example.com/users",
            "http.method" => "POST",
            "http.status_code" => 200,
            "component" => "httpc"
          }
        )

      assert span.category == :http
      assert span.attributes["http.method"] == "POST"
      assert span.attributes["http.status_code"] == 200
    end

    test "parent-child span relationships" do
      Transaction.Reporter.start_transaction(:web, "/test")

      parent =
        Span.Reporter.report_span(
          name: "Parent",
          duration_s: 0.2,
          category: :generic
        )

      # Set parent as current
      Process.put(:elixir_tracer_current_span, parent.id)

      child =
        Span.Reporter.report_span(
          name: "Child",
          duration_s: 0.1,
          category: :generic
        )

      assert child.parent_id == parent.id

      Transaction.Reporter.stop_transaction()
    end

    test "spans are stored independently" do
      Span.Reporter.report_span(name: "Span1", duration_s: 0.1, category: :generic)
      Span.Reporter.report_span(name: "Span2", duration_s: 0.2, category: :generic)
      Span.Reporter.report_span(name: "Span3", duration_s: 0.3, category: :generic)

      spans = Query.get_spans()
      assert length(spans) == 3
    end
  end

  describe "Span struct" do
    test "Span.t() typespec validation" do
      span = %Span{
        id: "abc123",
        trace_id: "trace_abc",
        parent_id: "parent_abc",
        transaction_id: "tx_abc",
        name: "TestSpan",
        category: :generic,
        timestamp: 1_234_567_890,
        duration_s: 0.1,
        sampled: true,
        priority: 0.5,
        entry_point: false,
        attributes: %{"key" => "value"}
      }

      assert span.name == "TestSpan"
      assert span.category == :generic
    end
  end
end
