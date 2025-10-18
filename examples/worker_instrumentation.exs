#!/usr/bin/env elixir

# Worker/Background Job Instrumentation Example

Mix.install([{:elixir_tracer, path: "."}])

{:ok, _} = Application.ensure_all_started(:elixir_tracer)

IO.puts("\n=== Worker Instrumentation Example ===\n")

defmodule EmailWorker do
  @doc """
  Process a batch of emails with full instrumentation.
  """
  def process_batch(emails) do
    ElixirTracer.OtherTransaction.start_transaction("Worker", "EmailWorker/ProcessBatch")

    ElixirTracer.Transaction.Reporter.add_attributes(
      batch_size: length(emails),
      worker_type: "email"
    )

    results =
      Enum.map(emails, fn email ->
        process_email(email)
      end)

    successful = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 != :ok))

    ElixirTracer.Transaction.Reporter.add_attributes(
      successful: successful,
      failed: failed
    )

    ElixirTracer.Metric.Reporter.increment_metric("Custom/EmailWorker/BatchesProcessed")

    ElixirTracer.Metric.Reporter.report_metric(
      "Custom/EmailWorker/EmailsPerBatch",
      duration_s: length(emails) / 100.0
    )

    ElixirTracer.OtherTransaction.stop_transaction()

    {:ok, successful, failed}
  end

  defp process_email(email) do
    # Simulate email processing with span
    span =
      ElixirTracer.Span.Reporter.report_span(
        name: "External/smtp.gmail.com/SEND",
        category: :http,
        duration_s: :rand.uniform() * 0.1,
        attributes: %{
          "http.method" => "POST",
          "email.to" => email.to,
          "email.subject" => email.subject
        }
      )

    if :rand.uniform() > 0.9 do
      # 10% failure rate
      ElixirTracer.Error.Reporter.notice_error(
        %RuntimeError{message: "SMTP timeout"},
        %{email_to: email.to}
      )

      ElixirTracer.Metric.Reporter.increment_metric("Custom/EmailWorker/Failures")
      :error
    else
      ElixirTracer.Metric.Reporter.increment_metric("Custom/EmailWorker/Success")
      :ok
    end
  end
end

# Simulate processing batches
IO.puts("Processing email batches...\n")

emails_batch_1 = [
  %{to: "user1@example.com", subject: "Welcome!"},
  %{to: "user2@example.com", subject: "Newsletter"},
  %{to: "user3@example.com", subject: "Reminder"}
]

emails_batch_2 = [
  %{to: "user4@example.com", subject: "Invoice"},
  %{to: "user5@example.com", subject: "Update"}
]

{:ok, success1, fail1} = EmailWorker.process_batch(emails_batch_1)
IO.puts("Batch 1: #{success1} successful, #{fail1} failed")

{:ok, success2, fail2} = EmailWorker.process_batch(emails_batch_2)
IO.puts("Batch 2: #{success2} successful, #{fail2} failed")

# Query results
IO.puts("\n=== Analysis ===\n")

transactions = ElixirTracer.Query.get_transactions()
IO.puts("Transactions: #{length(transactions)}")

Enum.each(transactions, fn tx ->
  IO.puts("\n#{tx.name}:")
  IO.puts("  Duration: #{tx.duration_ms}ms")
  IO.puts("  Batch size: #{tx.custom_attributes[:batch_size]}")
  IO.puts("  Successful: #{tx.custom_attributes[:successful]}")
  IO.puts("  Failed: #{tx.custom_attributes[:failed]}")
  IO.puts("  Spans: #{length(tx.spans)}")
  IO.puts("  Errors: #{length(tx.errors)}")
end)

spans = ElixirTracer.Query.get_spans()
IO.puts("\nTotal Spans (email sends): #{length(spans)}")

errors = ElixirTracer.Query.get_errors()
IO.puts("Total Errors: #{length(errors)}")

metrics = ElixirTracer.Query.get_metrics()
IO.puts("\nMetrics:")

Enum.each(metrics, fn metric ->
  IO.puts("  • #{metric.name}: #{metric.call_count} calls")
end)

IO.puts("\n✅ Worker instrumentation complete!\n")
