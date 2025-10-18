defmodule ElixirTracerTest do
  # SHARED STORAGE - must be sync
  use ElixirTracer.SupertesterCase, async: false

  describe "Transaction API" do
    test "start and stop transaction" do
      assert Transaction.Reporter.start_transaction(:other, "/Test/transaction") == :collect

      tx = Process.get(:elixir_tracer_transaction)
      assert tx != nil

      :timer.sleep(10)
      {:ok, completed} = Transaction.Reporter.stop_transaction()

      assert completed.status == :completed
      assert completed.duration_ms >= 10

      transactions = Query.get_transactions()
      assert length(transactions) == 1
    end

    test "add attributes" do
      Transaction.Reporter.start_transaction(:other, "/Test")
      Transaction.Reporter.add_attributes(user_id: 123, plan: "premium")

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:user_id] == 123
      assert tx.custom_attributes[:plan] == "premium"

      Transaction.Reporter.stop_transaction()
    end

    test "increment attributes" do
      Transaction.Reporter.start_transaction(:other, "/Test")

      Transaction.Reporter.incr_attributes(count: 1)
      Transaction.Reporter.incr_attributes(count: 3)

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:count] == 4

      Transaction.Reporter.stop_transaction()
    end
  end

  describe "Span API" do
    test "report span" do
      Transaction.Reporter.start_transaction(:other, "/Test")

      span =
        Span.Reporter.report_span(
          duration_s: 0.042,
          name: "TestSpan",
          category: :generic
        )

      assert span.category == :generic
      assert span.duration_s == 0.042

      Transaction.Reporter.stop_transaction()

      spans = Query.get_spans()
      assert length(spans) == 1
    end
  end

  describe "Error API" do
    test "notice error" do
      Transaction.Reporter.start_transaction(:other, "/Test")

      error = %RuntimeError{message: "Test error"}
      reported = Error.Reporter.notice_error(error)

      assert reported.error_type =~ "RuntimeError"
      assert reported.message == "Test error"

      Transaction.Reporter.stop_transaction()

      errors = Query.get_errors()
      assert length(errors) == 1
    end
  end

  describe "Metric API" do
    test "report metric" do
      Metric.Reporter.report_metric("Custom/Test", duration_s: 0.1)
      Metric.Reporter.report_metric("Custom/Test", duration_s: 0.2)

      metrics = Query.get_metrics()
      metric = Enum.find(metrics, &(&1.name == "Custom/Test"))

      assert metric.call_count == 2
      # Use approximate comparison for floats
      assert_in_delta metric.total_call_time, 0.3, 0.001
    end

    test "increment metric" do
      Metric.Reporter.increment_metric("Custom/Counter")
      Metric.Reporter.increment_metric("Custom/Counter")

      metrics = Query.get_metrics()
      metric = Enum.find(metrics, &(&1.name == "Custom/Counter"))

      assert metric.call_count == 2
    end
  end

  describe "Custom Events" do
    test "report custom event" do
      ElixirTracer.CustomEvent.Reporter.report_custom_event("UserSignup", %{
        email: "test@example.com"
      })

      events = Query.get_custom_events()
      assert length(events) == 1
      assert hd(events).type == "UserSignup"
    end
  end

  describe "Storage" do
    test "get_stats" do
      Transaction.Reporter.start_transaction(:other, "/Test")
      Transaction.Reporter.stop_transaction()

      stats = Query.get_stats()
      assert stats.transactions >= 1
      assert stats.storage_type == "DETS"
    end

    test "clear_all" do
      Transaction.Reporter.start_transaction(:other, "/Test")
      Transaction.Reporter.stop_transaction()

      assert length(Query.get_transactions()) >= 1

      Storage.clear_all()

      assert Query.get_transactions() == []
    end
  end
end
