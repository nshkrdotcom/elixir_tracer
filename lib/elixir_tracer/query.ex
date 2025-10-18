defmodule ElixirTracer.Query do
  @moduledoc """
  Query API for retrieving stored observability data.

  Provides rich querying capabilities over transactions, spans, errors, metrics, and custom events.
  """

  alias ElixirTracer.Storage

  @doc """
  Get transactions with optional filters.

  ## Options

  - `:since` - Unix timestamp in milliseconds
  - `:until` - Unix timestamp in milliseconds
  - `:type` - `:web` or `:other`
  - `:status` - `:in_progress`, `:completed`, or `:error`
  - `:sort` - `:duration_desc`, `:duration_asc`
  - `:limit` - Maximum number of results

  ## Examples

      # Get slowest 10 web transactions
      ElixirTracer.get_transactions(type: :web, sort: :duration_desc, limit: 10)

      # Get failed transactions
      ElixirTracer.get_transactions(status: :error)

      # Get transactions from last hour
      one_hour_ago = System.system_time(:millisecond) - 3_600_000
      ElixirTracer.get_transactions(since: one_hour_ago)
  """
  defdelegate get_transactions(opts \\ []), to: Storage

  @doc """
  Get spans with optional filters.

  ## Examples

      # Get all datastore spans
      ElixirTracer.get_spans(category: :datastore, limit: 100)

      # Get slowest spans
      ElixirTracer.get_spans(sort: :duration_desc, limit: 20)
  """
  defdelegate get_spans(opts \\ []), to: Storage

  @doc """
  Get errors with optional filters.

  ## Examples

      # Get recent errors
      ElixirTracer.get_errors(limit: 50)

      # Get errors from specific transaction type
      ElixirTracer.get_errors(transaction_type: :web)
  """
  defdelegate get_errors(opts \\ []), to: Storage

  @doc """
  Get metrics with optional filters.

  ## Examples

      # Get all datastore metrics
      metrics = ElixirTracer.get_metrics()
      |> Enum.filter(&String.starts_with?(&1.name, "Datastore/"))

      # Get metrics sorted by total time
      metrics
      |> Enum.sort_by(& &1.total_call_time, :desc)
      |> Enum.take(10)
  """
  defdelegate get_metrics(opts \\ []), to: Storage

  @doc """
  Get custom events.

  ## Examples

      # Get all purchase events
      events = ElixirTracer.get_custom_events()
      |> Enum.filter(&(&1.type == "PurchaseCompleted"))
  """
  defdelegate get_custom_events(opts \\ []), to: Storage

  @doc """
  Get storage statistics.

  ## Example

      stats = ElixirTracer.get_stats()
      # => %{
      #   transactions: 1523,
      #   spans: 8472,
      #   errors: 42,
      #   metrics: 234,
      #   custom_events: 567
      # }
  """
  def get_stats do
    Storage.get_stats()
  end

  @doc """
  Clear all stored data.
  """
  def clear_all do
    Storage.clear_all()
  end
end
