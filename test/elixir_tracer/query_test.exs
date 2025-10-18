defmodule ElixirTracer.QueryTest do
  # SHARED STORAGE - must be sync
  use ElixirTracer.SupertesterCase, async: false

  describe "Query.get_transactions/1" do
    setup do
      # Create test transactions
      Transaction.Reporter.start_transaction(:web, "/slow")
      :timer.sleep(50)
      Transaction.Reporter.stop_transaction()

      Transaction.Reporter.start_transaction(:web, "/fast")
      :timer.sleep(10)
      Transaction.Reporter.stop_transaction()

      Transaction.Reporter.start_transaction(:other, "/job")
      :timer.sleep(30)
      Transaction.Reporter.stop_transaction()

      :ok
    end

    test "get all transactions" do
      txs = Query.get_transactions()
      assert length(txs) == 3
    end

    test "filter by type" do
      web_txs = Query.get_transactions(type: :web)
      assert length(web_txs) == 2

      other_txs = Query.get_transactions(type: :other)
      assert length(other_txs) == 1
    end

    test "filter by status" do
      # All should be completed
      completed = Query.get_transactions(status: :completed)
      assert length(completed) == 3

      # None should be in progress
      in_progress = Query.get_transactions(status: :in_progress)
      assert length(in_progress) == 0
    end

    test "sort by duration descending" do
      txs = Query.get_transactions(sort: :duration_desc)
      durations = Enum.map(txs, & &1.duration_ms)

      assert hd(durations) >= 50
      assert durations == Enum.sort(durations, :desc)
    end

    test "sort by duration ascending" do
      txs = Query.get_transactions(sort: :duration_asc)
      durations = Enum.map(txs, & &1.duration_ms)

      assert hd(durations) >= 10
      assert durations == Enum.sort(durations, :asc)
    end

    test "limit results" do
      txs = Query.get_transactions(limit: 2)
      assert length(txs) == 2
    end

    test "combine filters" do
      txs =
        Query.get_transactions(
          type: :web,
          sort: :duration_desc,
          limit: 1
        )

      assert length(txs) == 1
      assert hd(txs).type == :web
      assert hd(txs).duration_ms >= 50
    end

      Span.Reporter.report_span(name: "Span1", duration_s: 0.1, category: :generic)
      Span.Reporter.report_span(name: "Span2", duration_s: 0.2, category: :datastore)
      Span.Reporter.report_span(name: "Span3", duration_s: 0.3, category: :http)
      :ok
    end

    test "get all spans" do
      spans = Query.get_spans()
      assert length(spans) == 3
    end

    test "sort by duration" do
      spans = Query.get_spans(sort: :duration_desc)
      assert hd(spans).duration_s == 0.3
    end

    test "limit spans" do
      spans = Query.get_spans(limit: 2)
      assert length(spans) == 2
    end
  end

  describe "Query.get_errors/1" do
    test "get all errors" do
      Error.Reporter.notice_error(%RuntimeError{message: "Error 1"})
      Error.Reporter.notice_error(%ArgumentError{message: "Error 2"})

      errors = Query.get_errors()
      assert length(errors) == 2
    end

    test "limit errors" do
      for i <- 1..5 do
        Error.Reporter.notice_error(%RuntimeError{message: "Error #{i}"})
      end

      errors = Query.get_errors(limit: 3)
      assert length(errors) == 3
    end
  end

  describe "Query.get_metrics/1" do
    test "get all metrics" do
      Metric.Reporter.report_metric("Metric/A", duration_s: 0.1)
      Metric.Reporter.report_metric("Metric/B", duration_s: 0.2)

      metrics = Query.get_metrics()
      assert length(metrics) == 2
    end

    test "limit metrics" do
      for i <- 1..5 do
        Metric.Reporter.report_metric("Metric/#{i}", duration_s: 0.1)
      end

      metrics = Query.get_metrics(limit: 3)
      assert length(metrics) == 3
    end
  end

  describe "Query.get_custom_events/1" do
    test "get all custom events" do
      ElixirTracer.CustomEvent.Reporter.report_custom_event("Event1", %{data: 1})
      ElixirTracer.CustomEvent.Reporter.report_custom_event("Event2", %{data: 2})

      events = Query.get_custom_events()
      assert length(events) == 2
    end

    test "limit events" do
      for i <- 1..10 do
        ElixirTracer.CustomEvent.Reporter.report_custom_event("Event", %{num: i})
      end

      events = Query.get_custom_events(limit: 5)
      assert length(events) == 5
    end
  end

  describe "Query.get_stats/0" do
    test "returns counts for all data types" do
      Transaction.Reporter.start_transaction(:web, "/test")
      Transaction.Reporter.stop_transaction()

      Span.Reporter.report_span(name: "Span", duration_s: 0.1, category: :generic)
      Error.Reporter.notice_error(%RuntimeError{message: "Error"})
      Metric.Reporter.report_metric("Metric", duration_s: 0.1)
      ElixirTracer.CustomEvent.Reporter.report_custom_event("Event", %{})

      stats = Query.get_stats()

      assert stats.transactions >= 1
      assert stats.spans >= 1
      assert stats.errors >= 1
      assert stats.metrics >= 1
      assert stats.custom_events >= 1
      assert stats.storage_type == "DETS"
      assert stats.storage_path == "test/fixtures/dets"
    end
  end

  describe "Query.clear_all/0" do
    test "clears all stored data" do
      Transaction.Reporter.start_transaction(:web, "/test")
      Transaction.Reporter.stop_transaction()
      Span.Reporter.report_span(name: "Span", duration_s: 0.1, category: :generic)
      Error.Reporter.notice_error(%RuntimeError{message: "Error"})

      Query.clear_all()

      assert Query.get_transactions() == []
      assert Query.get_spans() == []
      assert Query.get_errors() == []
    end
  end
end
