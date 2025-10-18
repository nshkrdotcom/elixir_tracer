defmodule ElixirTracer.DistributedTrace do
  @moduledoc """
  Distributed tracing with W3C Trace Context support.

  Enables trace propagation across service boundaries.
  """

  @doc """
  Create a distributed trace payload for outgoing requests.

  ## Example

      headers = ElixirTracer.create_distributed_trace_payload(:http)
      # Add headers to your HTTP request
  """
  def create_distributed_trace_payload(_type) do
    tx = Process.get(:elixir_tracer_transaction)

    if tx do
      %{
        "traceparent" => format_traceparent(tx),
        "tracestate" => format_tracestate(tx)
      }
    else
      %{}
    end
  end

  @doc """
  Accept and process incoming distributed trace headers.

  ## Example

      ElixirTracer.accept_distributed_trace_payload(headers, :http)
  """
  def accept_distributed_trace_payload(payload, _transport_type) when is_map(payload) do
    case parse_traceparent(payload["traceparent"]) do
      {:ok, trace_data} ->
        update_transaction_with_trace(trace_data)
        :ok

      :error ->
        :error
    end
  end

  defp format_traceparent(tx) do
    # W3C Trace Context format: version-trace_id-parent_id-flags
    "00-#{tx.trace_id}-#{tx.id |> String.slice(0..15)}-#{if tx.sampled, do: "01", else: "00"}"
  end

  defp format_tracestate(tx) do
    # Simple tracestate with priority
    "ed@p=#{Float.round(tx.priority, 6)}"
  end

  defp parse_traceparent(nil), do: :error

  defp parse_traceparent(header) when is_binary(header) do
    case String.split(header, "-") do
      ["00", trace_id, parent_id, flags] when byte_size(trace_id) == 32 ->
        {:ok,
         %{
           trace_id: trace_id,
           parent_span_id: parent_id,
           sampled: String.slice(flags, 0, 2) == "01"
         }}

      _ ->
        :error
    end
  end

  defp update_transaction_with_trace(trace_data) do
    tx = Process.get(:elixir_tracer_transaction)

    if tx do
      updated =
        %{tx | trace_id: trace_data.trace_id, parent_span_id: trace_data.parent_span_id}

      Process.put(:elixir_tracer_transaction, updated)
    end
  end
end
