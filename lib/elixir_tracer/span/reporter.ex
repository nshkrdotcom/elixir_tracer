defmodule ElixirTracer.Span.Reporter do
  @moduledoc """
  Span Reporter - creates and stores span events.
  """

  alias ElixirTracer.{Span, Storage}

  @doc """
  Report a span event.

  ## Example

      ElixirTracer.report_span(
        timestamp_ms: 1234567890,
        duration_s: 0.123,
        name: "Datastore/PostgreSQL/users/SELECT",
        category: "datastore",
        attributes: %{
          "db.statement" => "SELECT * FROM users",
          "db.instance" => "my_db"
        }
      )
  """
  def report_span(attrs) do
    tx = Process.get(:elixir_tracer_transaction)

    span = %Span{
      id: attrs[:id] || generate_id(),
      trace_id: attrs[:trace_id] || (tx && tx.trace_id),
      parent_id: attrs[:parent_id] || Process.get(:elixir_tracer_current_span),
      transaction_id: tx && tx.id,
      name: attrs[:name],
      category: attrs[:category] || :generic,
      timestamp: attrs[:timestamp_ms] || System.system_time(:millisecond),
      duration_s: attrs[:duration_s],
      sampled: attrs[:sampled] || true,
      priority: attrs[:priority] || (tx && tx.priority) || :rand.uniform(),
      entry_point: attrs[:entry_point] || false,
      attributes: attrs[:attributes] || %{}
    }

    Storage.store_span(span)
    span
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
