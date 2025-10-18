defmodule ElixirTracer.TracerTest do
  use ExUnit.Case, async: false

  alias ElixirTracer.{Tracer, Query, Storage}

  setup do
    # Clear all data before each test
    Storage.clear_all()
    # Clear process dictionary
    Process.delete(:elixir_tracer_transaction)
    Process.delete(:elixir_tracer_current_span)
    :ok
  end

  describe "Transaction API - Feature Parity with New Relic" do
    test "start and stop web transaction" do
      # Start transaction
      assert Tracer.start_transaction("Web", "/users/index") == :collect

      # Verify it's in process dict
      tx = Process.get(:elixir_tracer_transaction)
      assert tx != nil
      assert tx.type == :other
      assert tx.name == "/Web/users/index"
      assert tx.status == :in_progress

      # Stop transaction
      Process.sleep(10)
      {:ok, completed} = Tracer.stop_transaction()

      assert completed.status == :completed
      assert completed.duration_ms >= 10
      assert completed.end_time != nil

      # Verify it's stored
      transactions = Query.get_transactions()
      assert length(transactions) == 1
      assert hd(transactions).name == "/Web/users/index"
    end

    test "set transaction name" do
      Tracer.start_transaction("Worker", "ProcessEmails")
      Tracer.set_transaction_name("/CustomName/MyTransaction")

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.name == "/CustomName/MyTransaction"

      Tracer.stop_transaction()
    end

    test "add custom attributes" do
      Tracer.start_transaction("Task", "DataImport")

      # Add simple attributes
      Tracer.add_attributes(user_id: 123, plan: "premium")

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes["user_id"] == "123"
      assert tx.custom_attributes["plan"] == "premium"

      Tracer.stop_transaction()
    end

    test "add nested attributes with auto-flattening" do
      Tracer.start_transaction("Task", "Test")

      # Nested map
      Tracer.add_attributes(
        user: %{
          id: 123,
          email: "test@example.com",
          metadata: %{plan: "premium", trial: false}
        }
      )

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes["user.id"] == "123"
      assert tx.custom_attributes["user.email"] == "test@example.com"
      assert tx.custom_attributes["user.metadata.plan"] == "premium"
      assert tx.custom_attributes["user.size"] == 3

      Tracer.stop_transaction()
    end

    test "increment attributes (counters)" do
      Tracer.start_transaction("Task", "Test")

      Tracer.incr_attributes(cache_hits: 1)
      Tracer.incr_attributes(cache_hits: 3)
      Tracer.incr_attributes(cache_misses: 2)

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:cache_hits] == 4
      assert tx.custom_attributes[:cache_misses] == 2

      Tracer.stop_transaction()
    end

    test "ignore transaction" do
      Tracer.start_transaction("Task", "HealthCheck")
      Tracer.ignore_transaction()

      # Transaction removed from process dict
      assert Process.get(:elixir_tracer_transaction) == nil

      # Not stored
      assert Query.get_transactions() == []
    end

    test "other_transaction macro" do
      result =
        Tracer.other_transaction "Worker", "ProcessBatch" do
          Process.sleep(5)
          :processed
        end

      assert result == :processed

      # Transaction completed and stored
      transactions = Query.get_transactions()
      assert length(transactions) == 1
      assert hd(transactions).name == "/Worker/ProcessBatch"
      assert hd(transactions).type == :other
      assert hd(transactions).duration_ms >= 5
    end
  end

  describe "Span API" do
    test "report span events" do
      Tracer.start_transaction("Task", "Test")

      span1 =
        Tracer.report_span(
          timestamp_ms: System.system_time(:millisecond),
          duration_s: 0.042,
          name: "Database/Query",
          category: :datastore,
          attributes: %{"db.statement" => "SELECT * FROM users"}
        )

      assert span1.category == :datastore
      assert span1.duration_s == 0.042
      assert span1.attributes["db.statement"] == "SELECT * FROM users"

      Tracer.stop_transaction()

      # Verify span stored
      spans = Query.get_spans()
      assert length(spans) == 1
    end

    test "nested spans with parent-child relationships" do
      Tracer.start_transaction("Task", "Test")

      parent_span =
        Tracer.report_span(
          name: "ParentOperation",
          duration_s: 0.1,
          category: :generic
        )

      Process.put(:elixir_tracer_current_span, parent_span.id)

      child_span =
        Tracer.report_span(
          name: "ChildOperation",
          duration_s: 0.05,
          category: :generic
        )

      assert child_span.parent_id == parent_span.id

      Tracer.stop_transaction()
    end
  end

  describe "Error API" do
    test "notice_error captures exceptions" do
      Tracer.start_transaction("Task", "Test")

      error = %RuntimeError{message: "Something went wrong"}
      reported = Tracer.notice_error(error)

      assert reported.error_type =~ "RuntimeError"
      assert reported.message == "Something went wrong"
      assert is_binary(reported.stack_trace)

      Tracer.stop_transaction()

      # Verify error stored
      errors = Query.get_errors()
      assert length(errors) == 1
    end

    test "notice_error with custom attributes" do
      Tracer.start_transaction("Task", "Payment")

      error = %RuntimeError{message: "Payment failed"}

      Tracer.notice_error(error, %{
        payment_id: "pay_123",
        amount: 99.99,
        user_id: 456
      })

      errors = Query.get_errors()
      error_data = hd(errors)

      assert error_data.user_attributes[:payment_id] == "pay_123"
      assert error_data.user_attributes[:amount] == 99.99

      Tracer.stop_transaction()
    end
  end

  describe "Metric API" do
    test "report_metric creates and aggregates metrics" do
      # Report same metric twice
      Tracer.report_metric({:datastore, "PostgreSQL", "users", "SELECT"}, duration_s: 0.1)
      Tracer.report_metric({:datastore, "PostgreSQL", "users", "SELECT"}, duration_s: 0.2)

      metrics = Query.get_metrics()
      assert length(metrics) >= 1

      # Find our metric
      metric =
        Enum.find(metrics, fn m ->
          String.contains?(m.name, "users") && String.contains?(m.name, "SELECT")
        end)

      assert metric.call_count == 2
      assert metric.total_call_time == 0.3
      assert metric.min_call_time == 0.1
      assert metric.max_call_time == 0.2
    end

    test "increment_metric for counters" do
      Tracer.increment_metric("Custom/Cache/Hits")
      Tracer.increment_metric("Custom/Cache/Hits")
      Tracer.increment_metric("Custom/Cache/Hits")

      metrics = Query.get_metrics()
      metric = Enum.find(metrics, &(&1.name == "Custom/Cache/Hits"))

      assert metric.call_count == 3
    end
  end

  describe "Custom Event API" do
    test "report_custom_event stores application events" do
      Tracer.report_custom_event("UserSignup", %{
        email: "test@example.com",
        plan: "premium",
        source: "organic"
      })

      Tracer.report_custom_event("PurchaseCompleted", %{
        amount: 99.99,
        product: "widget"
      })

      events = Query.get_custom_events()
      assert length(events) == 2

      signup = Enum.find(events, &(&1.type == "UserSignup"))
      assert signup.attributes.email == "test@example.com"
      assert signup.attributes.plan == "premium"
    end
  end

  describe "Query API" do
    test "get_transactions with filters" do
      # Create various transactions
      Tracer.other_transaction "Worker", "Job1" do
        Process.sleep(50)
      end

      Tracer.other_transaction "Worker", "Job2" do
        Process.sleep(30)
      end

      Tracer.other_transaction "Task", "Job3" do
        Process.sleep(20)
      end

      # Get all
      all_txs = Query.get_transactions()
      assert length(all_txs) == 3

      # Get slowest
      slowest = Query.get_transactions(sort: :duration_desc, limit: 2)
      assert length(slowest) == 2
      assert hd(slowest).duration_ms >= 50

      # Get by type
      other_txs = Query.get_transactions(type: :other)
      assert length(other_txs) == 3
    end

    test "get_stats shows all data counts" do
      Tracer.other_transaction "Task", "Test" do
        :ok
      end

      Tracer.report_span(name: "TestSpan", duration_s: 0.1, category: :generic)
      Tracer.notice_error(%RuntimeError{message: "Test error"})
      Tracer.report_metric("Custom/Test", duration_s: 0.5)
      Tracer.report_custom_event("TestEvent", %{foo: "bar"})

      stats = Query.get_stats()

      assert stats.transactions >= 1
      assert stats.spans >= 1
      assert stats.errors >= 1
      assert stats.metrics >= 1
      assert stats.custom_events >= 1
      assert stats.storage_type == "DETS"
    end
  end

  describe "Distributed Tracing" do
    test "create and accept distributed trace headers" do
      Tracer.start_transaction("Task", "ServiceA")

      # Create headers for outgoing request
      headers = Tracer.create_distributed_trace_payload(:http)

      assert headers["traceparent"] != nil
      assert headers["tracestate"] != nil
      assert String.starts_with?(headers["traceparent"], "00-")

      Tracer.stop_transaction()

      # Accept headers in new transaction (simulating Service B)
      Tracer.start_transaction("Task", "ServiceB")
      :ok = Tracer.accept_distributed_trace_payload(headers, :http)

      tx = Process.get(:elixir_tracer_transaction)
      # Trace ID should be propagated
      assert tx.trace_id != nil

      Tracer.stop_transaction()
    end
  end

  describe "Process Management" do
    test "get and connect to transaction from another process" do
      Tracer.start_transaction("Task", "Parent")
      Tracer.add_attributes(parent: true)

      tx_ref = Tracer.get_transaction()
      assert tx_ref != nil

      # Spawn new process and connect it
      task =
        Task.async(fn ->
          # Initially no transaction
          assert Process.get(:elixir_tracer_transaction) == nil

          # Connect to parent
          :connected = Tracer.connect_to_transaction(tx_ref)

          # Now we're in the transaction
          tx = Process.get(:elixir_tracer_transaction)
          assert tx.custom_attributes["parent"] == "true"

          # Add our own attribute
          Tracer.add_attributes(child: true)

          :done
        end)

      Task.await(task)
      Tracer.stop_transaction()

      # Both attributes should be there
      txs = Query.get_transactions()
      tx = hd(txs)
      assert tx.custom_attributes["parent"] == "true"
      assert tx.custom_attributes["child"] == "true"
    end

    test "exclude_from_transaction" do
      Tracer.start_transaction("Task", "Parent")

      task =
        Task.async(fn ->
          # Get reference first
          tx_ref = Tracer.get_transaction()
          assert tx_ref == nil

          # Even if we tried to connect
          Tracer.exclude_from_transaction()

          # Still no transaction
          assert Process.get(:elixir_tracer_transaction) == nil
        end)

      Task.await(task)
      Tracer.stop_transaction()
    end
  end
end
