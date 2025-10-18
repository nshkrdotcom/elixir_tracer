defmodule ElixirTracer.ErrorTest do
  # SHARED STORAGE - must be sync
  use ElixirTracer.SupertesterCase, async: false

  describe "Error.Reporter" do
    test "notice_error captures exception details" do
      Transaction.Reporter.start_transaction(:web, "/test")

      error = %RuntimeError{message: "Something went wrong"}
      reported = Error.Reporter.notice_error(error)

      assert reported.error_type =~ "RuntimeError"
      assert reported.message == "Something went wrong"
      assert is_binary(reported.id)
      assert is_integer(reported.timestamp)
      assert reported.pid == self()

      Transaction.Reporter.stop_transaction()
    end

    test "notice_error with custom attributes" do
      Transaction.Reporter.start_transaction(:web, "/checkout")

      error = %RuntimeError{message: "Payment failed"}

      reported =
        Error.Reporter.notice_error(error, %{
          payment_id: "pay_123",
          amount: 99.99,
          user_id: 456,
          retry_count: 3
        })

      assert reported.user_attributes[:payment_id] == "pay_123"
      assert reported.user_attributes[:amount] == 99.99
      assert reported.user_attributes[:user_id] == 456
      assert reported.user_attributes[:retry_count] == 3

      Transaction.Reporter.stop_transaction()
    end

    test "notice_error associates with transaction" do
      Transaction.Reporter.start_transaction(:web, "/api/endpoint")

      error = %ArgumentError{message: "Invalid input"}
      reported = Error.Reporter.notice_error(error)

      assert reported.transaction_name == "/api/endpoint"
      assert is_binary(reported.transaction_id)

      Transaction.Reporter.stop_transaction()
    end

    test "notice_error without transaction" do
      error = %RuntimeError{message: "Standalone error"}
      reported = Error.Reporter.notice_error(error)

      assert reported.transaction_name == nil
      assert reported.transaction_id == nil
      assert reported.message == "Standalone error"

      # Still stored
      errors = Query.get_errors()
      assert length(errors) == 1
    end

    test "error adds to transaction errors list" do
      Transaction.Reporter.start_transaction(:web, "/test")

      Error.Reporter.notice_error(%RuntimeError{message: "Error 1"})
      Error.Reporter.notice_error(%ArgumentError{message: "Error 2"})

      tx = Process.get(:elixir_tracer_transaction)
      assert length(tx.errors) == 2

      Transaction.Reporter.stop_transaction()
    end

    test "errors are stored in DETS" do
      Error.Reporter.notice_error(%RuntimeError{message: "Error 1"})
      Error.Reporter.notice_error(%ArgumentError{message: "Error 2"})
      Error.Reporter.notice_error(%KeyError{message: "Error 3"})

      errors = Query.get_errors()
      assert length(errors) == 3
    end

    test "error agent attributes from transaction" do
      Transaction.Reporter.start_transaction(:web, "/test")
      :timer.sleep(10)

      error = %RuntimeError{message: "Test"}
      reported = Error.Reporter.notice_error(error)

      # Agent attributes include transaction metadata
      assert is_map(reported.agent_attributes)

      Transaction.Reporter.stop_transaction()
    end
  end

  describe "Error struct" do
    test "Error.t() typespec validation" do
      error = %Error{
        id: "err123",
        timestamp: 1_234_567_890,
        transaction_name: "/Test/Transaction",
        transaction_id: "tx123",
        message: "Test error message",
        error_type: "RuntimeError",
        expected: false,
        stack_trace: "line 1\nline 2",
        pid: self(),
        agent_attributes: %{"duration_ms" => 100},
        user_attributes: %{"custom" => "value"}
      }

      assert error.message == "Test error message"
      assert error.expected == false
    end
  end
end
