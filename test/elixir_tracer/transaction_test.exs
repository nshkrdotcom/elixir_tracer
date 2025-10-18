defmodule ElixirTracer.TransactionTest do
  use ElixirTracer.SupertesterCase, async: true

  describe "Transaction lifecycle" do
    test "start transaction creates transaction in process dict" do
      assert Transaction.Reporter.start_transaction(:web, "/users/index") == :collect

      tx = Process.get(:elixir_tracer_transaction)
      assert tx != nil
      assert tx.type == :web
      assert tx.name == "/users/index"
      assert tx.status == :in_progress
      assert tx.pid == self()
      assert is_binary(tx.id)
      assert is_binary(tx.trace_id)
      assert tx.sampled == true
      assert is_float(tx.priority)
    end

    test "cannot start transaction if one already exists" do
      assert Transaction.Reporter.start_transaction(:web, "/first") == :collect
      assert Transaction.Reporter.start_transaction(:web, "/second") == :ignore

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.name == "/first"
    end

    test "stop transaction calculates duration and stores" do
      Transaction.Reporter.start_transaction(:other, "/job")
      :timer.sleep(20)

      {:ok, completed} = Transaction.Reporter.stop_transaction()

      assert completed.status == :completed
      assert completed.duration_ms >= 20
      assert completed.end_time != nil
      assert completed.end_time > completed.start_time

      # Verify stored
      txs = Query.get_transactions()
      assert length(txs) == 1
      assert hd(txs).id == completed.id
    end

    test "stop transaction when none exists" do
      assert Transaction.Reporter.stop_transaction() == :no_transaction
    end

    test "transaction with error status" do
      Transaction.Reporter.start_transaction(:web, "/error_endpoint")
      Transaction.Reporter.record_error(%RuntimeError{message: "boom"})

      {:ok, completed} = Transaction.Reporter.stop_transaction()

      assert completed.status == :error
      assert completed.error != nil
      assert length(completed.errors) == 1
    end
  end

  describe "Transaction naming" do
    test "set_transaction_name updates current transaction" do
      Transaction.Reporter.start_transaction(:web, "/default")
      Transaction.Reporter.set_transaction_name("/Custom/Name")

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.name == "/Custom/Name"

      Transaction.Reporter.stop_transaction()
    end

    test "set_transaction_name when no transaction" do
      result = Transaction.Reporter.set_transaction_name("/NoTx")
      assert result == :no_transaction
    end
  end

  describe "Custom attributes" do
    test "add simple attributes" do
      Transaction.Reporter.start_transaction(:web, "/test")

      Transaction.Reporter.add_attributes(
        user_id: 123,
        email: "test@example.com",
        premium: true
      )

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:user_id] == 123
      assert tx.custom_attributes[:email] == "test@example.com"
      assert tx.custom_attributes[:premium] == true

      Transaction.Reporter.stop_transaction()
    end

    test "add attributes as map" do
      Transaction.Reporter.start_transaction(:web, "/test")

      Transaction.Reporter.add_attributes(%{
        "string_key" => "value",
        atom_key: "atom value"
      })

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes["string_key"] == "value"
      assert tx.custom_attributes[:atom_key] == "atom value"

      Transaction.Reporter.stop_transaction()
    end

    test "attributes merge across multiple calls" do
      Transaction.Reporter.start_transaction(:web, "/test")
      Transaction.Reporter.add_attributes(first: 1)
      Transaction.Reporter.add_attributes(second: 2)
      Transaction.Reporter.add_attributes(third: 3)

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:first] == 1
      assert tx.custom_attributes[:second] == 2
      assert tx.custom_attributes[:third] == 3

      Transaction.Reporter.stop_transaction()
    end

    test "attributes persist in stored transaction" do
      Transaction.Reporter.start_transaction(:web, "/test")
      Transaction.Reporter.add_attributes(stored_attr: "value")
      Transaction.Reporter.stop_transaction()

      txs = Query.get_transactions()
      assert hd(txs).custom_attributes[:stored_attr] == "value"
    end
  end

  describe "Increment attributes" do
    test "increment creates attribute if not exists" do
      Transaction.Reporter.start_transaction(:web, "/test")
      Transaction.Reporter.incr_attributes(counter: 5)

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:counter] == 5

      Transaction.Reporter.stop_transaction()
    end

    test "increment adds to existing value" do
      Transaction.Reporter.start_transaction(:web, "/test")
      Transaction.Reporter.incr_attributes(hits: 1)
      Transaction.Reporter.incr_attributes(hits: 2)
      Transaction.Reporter.incr_attributes(hits: 3)

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:hits] == 6

      Transaction.Reporter.stop_transaction()
    end

    test "increment multiple attributes at once" do
      Transaction.Reporter.start_transaction(:web, "/test")
      Transaction.Reporter.incr_attributes(cache_hits: 1, db_calls: 1)
      Transaction.Reporter.incr_attributes(cache_hits: 3, db_calls: 2)

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:cache_hits] == 4
      assert tx.custom_attributes[:db_calls] == 3

      Transaction.Reporter.stop_transaction()
    end
  end

  describe "Transaction control" do
    test "ignore_transaction removes from process dict and doesn't store" do
      Transaction.Reporter.start_transaction(:web, "/health")
      Transaction.Reporter.ignore_transaction()

      assert Process.get(:elixir_tracer_transaction) == nil

      # Not stored
      assert Query.get_transactions() == []
    end

    test "get_transaction returns current transaction reference" do
      Transaction.Reporter.start_transaction(:web, "/test")
      tx_ref = Transaction.Reporter.get_transaction()

      assert tx_ref != nil
      assert tx_ref.name == "/test"

      Transaction.Reporter.stop_transaction()
    end

    test "get_transaction when none exists" do
      assert Transaction.Reporter.get_transaction() == nil
    end
  end

  describe "Process management" do
    test "connect_to_transaction from another process" do
      Transaction.Reporter.start_transaction(:web, "/parent")
      Transaction.Reporter.add_attributes(parent_pid: self())

      tx_ref = Transaction.Reporter.get_transaction()

      task =
        Task.async(fn ->
          # Initially no transaction
          assert Process.get(:elixir_tracer_transaction) == nil

          # Connect
          assert Transaction.Reporter.connect_to_transaction(tx_ref) == :connected

          # Now have transaction
          tx = Process.get(:elixir_tracer_transaction)
          assert tx.name == "/parent"

          # Can add attributes
          Transaction.Reporter.add_attributes(child_pid: self())

          :done
        end)

      Task.await(task)

      # Parent still has transaction
      tx = Process.get(:elixir_tracer_transaction)
      assert tx.custom_attributes[:parent_pid] == self()
      # NOTE: Child attributes NOT visible in parent (separate process memory - correct behavior)

      Transaction.Reporter.stop_transaction()
    end

    test "disconnect_from_transaction" do
      Transaction.Reporter.start_transaction(:web, "/test")
      assert Transaction.Reporter.disconnect_from_transaction() == :disconnected
      assert Process.get(:elixir_tracer_transaction) == nil
    end

    test "exclude_from_transaction removes transaction and span" do
      Transaction.Reporter.start_transaction(:web, "/test")
      Process.put(:elixir_tracer_current_span, "span_123")

      Transaction.Reporter.exclude_from_transaction()

      assert Process.get(:elixir_tracer_transaction) == nil
      assert Process.get(:elixir_tracer_current_span) == nil
    end

    test "connect with invalid reference" do
      assert Transaction.Reporter.connect_to_transaction("not_a_tx") == :invalid_transaction
    end
  end

  describe "Span management within transaction" do
    test "add_trace_segment creates span in transaction" do
      Transaction.Reporter.start_transaction(:web, "/test")

      segment = %{
        primary_name: "Database/Query",
        start_time: 1000,
        end_time: 1050,
        attributes: %{"db.statement" => "SELECT *"}
      }

      span_id = Transaction.Reporter.add_trace_segment(segment)

      tx = Process.get(:elixir_tracer_transaction)
      assert length(tx.spans) == 1

      span = hd(tx.spans)
      assert span.id == span_id
      assert span.name == "Database/Query"
      assert span.duration_ms == 50
      assert span.attributes["db.statement"] == "SELECT *"

      Transaction.Reporter.stop_transaction()
    end

    test "nested segments have parent-child relationship" do
      Transaction.Reporter.start_transaction(:web, "/test")

      parent_id =
        Transaction.Reporter.add_trace_segment(%{
          primary_name: "Parent",
          start_time: 1000,
          end_time: 2000
        })

      child_id =
        Transaction.Reporter.add_trace_segment(%{
          primary_name: "Child",
          start_time: 1200,
          end_time: 1500
        })

      tx = Process.get(:elixir_tracer_transaction)
      child_span = Enum.find(tx.spans, &(&1.id == child_id))
      assert child_span.parent_id == parent_id

      Transaction.Reporter.stop_transaction()
    end
  end

  describe "Error tracking in transaction" do
    test "record_error adds error to transaction" do
      Transaction.Reporter.start_transaction(:web, "/test")

      error = %RuntimeError{message: "Something failed"}
      Transaction.Reporter.record_error(error, %{context: "payment"})

      tx = Process.get(:elixir_tracer_transaction)
      assert length(tx.errors) == 1
      assert tx.error == error

      error_data = hd(tx.errors)
      assert error_data.type =~ "RuntimeError"
      assert error_data.message == "Something failed"
      assert error_data.custom_attributes[:context] == "payment"

      Transaction.Reporter.stop_transaction()
    end

    test "multiple errors can be recorded" do
      Transaction.Reporter.start_transaction(:web, "/test")

      Transaction.Reporter.record_error(%RuntimeError{message: "Error 1"})
      Transaction.Reporter.record_error(%ArgumentError{message: "Error 2"})

      tx = Process.get(:elixir_tracer_transaction)
      assert length(tx.errors) == 2

      Transaction.Reporter.stop_transaction()
    end
  end

  describe "Metric tracking in transaction" do
    test "track_metric adds metric to transaction" do
      Transaction.Reporter.start_transaction(:web, "/test")

      Transaction.Reporter.track_metric({
        {:datastore, "PostgreSQL", "users", "SELECT"},
        duration_s: 0.042
      })

      tx = Process.get(:elixir_tracer_transaction)
      assert map_size(tx.metrics) == 1

      metric = tx.metrics["Datastore/PostgreSQL/users/SELECT"]
      assert metric.call_count == 1
      assert metric.total_time == 0.042

      Transaction.Reporter.stop_transaction()
    end

    test "track same metric multiple times aggregates" do
      Transaction.Reporter.start_transaction(:web, "/test")

      Transaction.Reporter.track_metric({
        {:datastore, "PostgreSQL", "orders", "INSERT"},
        duration_s: 0.01
      })

      Transaction.Reporter.track_metric({
        {:datastore, "PostgreSQL", "orders", "INSERT"},
        duration_s: 0.02
      })

      tx = Process.get(:elixir_tracer_transaction)
      metric = tx.metrics["Datastore/PostgreSQL/orders/INSERT"]

      assert metric.call_count == 2
      assert metric.total_time == 0.03
      assert metric.min_time == 0.01
      assert metric.max_time == 0.02

      Transaction.Reporter.stop_transaction()
    end
  end

  describe "OtherTransaction module" do
    test "start_transaction formats name correctly" do
      ElixirTracer.OtherTransaction.start_transaction("Worker", "EmailProcessor")

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.name == "/Worker/EmailProcessor"
      assert tx.type == :other

      Transaction.Reporter.stop_transaction()
    end

    test "start with headers" do
      headers = %{"traceparent" => "00-trace123-parent456-01"}
      ElixirTracer.OtherTransaction.start_transaction("Task", "Import", headers)

      tx = Process.get(:elixir_tracer_transaction)
      assert tx.name == "/Task/Import"

      Transaction.Reporter.stop_transaction()
    end

    test "stop_transaction delegates properly" do
      ElixirTracer.OtherTransaction.start_transaction("Task", "Test")
      :timer.sleep(5)

      {:ok, completed} = ElixirTracer.OtherTransaction.stop_transaction()

      assert completed.duration_ms >= 5
    end
  end
end
