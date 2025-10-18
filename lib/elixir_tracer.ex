defmodule ElixirTracer.Tracer do
  @moduledoc """
  Local-first observability API with 100% feature parity to New Relic Agent.

  This module provides the same public API as NewRelic but stores all data
  locally in DETS for immediate visibility during development.

  ## Features

  - Transaction tracking (Web & Other)
  - Distributed tracing with W3C support
  - Span events with parent-child relationships
  - Error tracking with stack traces
  - Metrics aggregation
  - Custom attributes and events
  - Auto-instrumentation via telemetry

  ## Usage

      # Set transaction name
      ElixirTracer.set_transaction_name("/Controller/UsersController/index")

      # Add custom attributes
      ElixirTracer.add_attributes(user_id: 123, plan: "premium")

      # Report errors
      ElixirTracer.notice_error(%RuntimeError{message: "Something broke"})

      # Start other transaction
      ElixirTracer.start_transaction("Worker", "ProcessEmails")

      # Report custom events
      ElixirTracer.report_custom_event("UserSignup", %{email: "user@example.com"})
  """

  # Transaction API
  defdelegate set_transaction_name(name), to: ElixirTracer.Transaction.Reporter
  defdelegate add_attributes(attributes), to: ElixirTracer.Transaction.Reporter
  defdelegate incr_attributes(attributes), to: ElixirTracer.Transaction.Reporter
  defdelegate start_transaction(category, name), to: ElixirTracer.OtherTransaction
  defdelegate start_transaction(category, name, headers), to: ElixirTracer.OtherTransaction
  defdelegate stop_transaction(), to: ElixirTracer.OtherTransaction
  defdelegate ignore_transaction(), to: ElixirTracer.Transaction.Reporter
  defdelegate exclude_from_transaction(), to: ElixirTracer.Transaction.Reporter
  defdelegate get_transaction(), to: ElixirTracer.Transaction.Reporter
  defdelegate connect_to_transaction(tx_ref), to: ElixirTracer.Transaction.Reporter
  defdelegate disconnect_from_transaction(), to: ElixirTracer.Transaction.Reporter

  # Error API
  defdelegate notice_error(exception), to: ElixirTracer.Error.Reporter
  defdelegate notice_error(exception, custom_attributes), to: ElixirTracer.Error.Reporter

  # Span API
  defdelegate report_span(span_attrs), to: ElixirTracer.Span.Reporter

  # Metric API
  defdelegate report_metric(identifier, values), to: ElixirTracer.Metric.Reporter
  defdelegate increment_metric(identifier), to: ElixirTracer.Metric.Reporter

  # Custom Event API
  defdelegate report_custom_event(event_type, attributes),
    to: ElixirTracer.CustomEvent.Reporter

  # Distributed Trace API
  defdelegate create_distributed_trace_payload(type),
    to: ElixirTracer.DistributedTrace

  defdelegate accept_distributed_trace_payload(payload, transport_type),
    to: ElixirTracer.DistributedTrace

  # Query API for local data
  defdelegate get_transactions(opts \\ []), to: ElixirTracer.Query
  defdelegate get_spans(opts \\ []), to: ElixirTracer.Query
  defdelegate get_errors(opts \\ []), to: ElixirTracer.Query
  defdelegate get_metrics(opts \\ []), to: ElixirTracer.Query
  defdelegate get_custom_events(opts \\ []), to: ElixirTracer.Query

  @doc """
  Record an "Other" Transaction within the given block.

  ## Example

      ElixirTracer.other_transaction "Worker", "ProcessMessages" do
        # ... work ...
      end
  """
  defmacro other_transaction(category, name, do: block) do
    quote do
      ElixirTracer.start_transaction(unquote(category), unquote(name))
      res = unquote(block)
      ElixirTracer.stop_transaction()
      res
    end
  end

  defmacro other_transaction(category, name, headers, do: block) do
    quote do
      ElixirTracer.start_transaction(unquote(category), unquote(name), unquote(headers))
      res = unquote(block)
      ElixirTracer.stop_transaction()
      res
    end
  end
end
