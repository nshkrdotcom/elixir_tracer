defmodule ElixirTracer.Transaction.Reporter do
  @moduledoc """
  Transaction Reporter - tracks active transactions per process.

  Uses process dictionary to store transaction context, matching New Relic's approach.
  """

  alias ElixirTracer.Transaction
  alias ElixirTracer.Storage

  @transaction_key :elixir_tracer_transaction
  @span_key :elixir_tracer_current_span

  ## Transaction Lifecycle

  @doc """
  Start a new transaction. Returns :collect if successful, :ignore if already in transaction.
  """
  def start_transaction(type, name) do
    case Process.get(@transaction_key) do
      nil ->
        tx = %Transaction{
          id: generate_id(),
          type: type,
          name: name,
          start_time: System.system_time(:millisecond),
          status: :in_progress,
          pid: self(),
          trace_id: generate_trace_id(),
          sampled: true,
          priority: :rand.uniform(),
          attributes: %{},
          custom_attributes: %{},
          spans: [],
          errors: [],
          metrics: %{}
        }

        Process.put(@transaction_key, tx)
        :collect

      _existing ->
        :ignore
    end
  end

  @doc """
  Stop and record the current transaction.
  """
  def stop_transaction do
    case Process.get(@transaction_key) do
      nil ->
        :no_transaction

      tx ->
        end_time = System.system_time(:millisecond)
        duration_ms = end_time - tx.start_time

        completed_tx = %{
          tx
          | end_time: end_time,
            duration_ms: duration_ms,
            status: if(tx.error, do: :error, else: :completed)
        }

        # Store in DETS
        Storage.store_transaction(completed_tx)

        # Clear from process dict
        Process.delete(@transaction_key)

        {:ok, completed_tx}
    end
  end

  ## Transaction Attributes

  @doc """
  Set the name of the current transaction.
  """
  def set_transaction_name(name) do
    update_transaction(fn tx -> %{tx | name: name} end)
  end

  @doc """
  Add custom attributes to the current transaction.
  Supports nested data structures via auto-flattening.
  """
  def add_attributes(attributes) when is_list(attributes) or is_map(attributes) do
    flattened = flatten_attributes(attributes)

    update_transaction(fn tx ->
      %{tx | custom_attributes: Map.merge(tx.custom_attributes, flattened)}
    end)
  end

  @doc """
  Increment numeric attributes (for counters).
  """
  def incr_attributes(attributes) when is_list(attributes) or is_map(attributes) do
    update_transaction(fn tx ->
      new_attrs =
        Enum.reduce(attributes, tx.custom_attributes, fn {key, value}, acc ->
          Map.update(acc, key, value, &(&1 + value))
        end)

      %{tx | custom_attributes: new_attrs}
    end)
  end

  @doc """
  Ignore the current transaction (it won't be reported).
  """
  def ignore_transaction do
    Process.delete(@transaction_key)
    :ignored
  end

  @doc """
  Exclude the current process from the parent transaction.
  """
  def exclude_from_transaction do
    Process.delete(@transaction_key)
    Process.delete(@span_key)
    :excluded
  end

  @doc """
  Get a reference to the current transaction for manual connection.
  """
  def get_transaction do
    Process.get(@transaction_key)
  end

  @doc """
  Connect the current process to an existing transaction.
  """
  def connect_to_transaction(tx_ref) when is_struct(tx_ref, Transaction) do
    Process.put(@transaction_key, tx_ref)
    :connected
  end

  def connect_to_transaction(_), do: :invalid_transaction

  @doc """
  Disconnect from the current transaction.
  """
  def disconnect_from_transaction do
    Process.delete(@transaction_key)
    :disconnected
  end

  ## Span Management

  @doc """
  Add a trace segment (span) to the current transaction.
  """
  def add_trace_segment(segment) do
    span_id = generate_id()

    update_transaction(fn tx ->
      span = %{
        id: span_id,
        parent_id: Process.get(@span_key),
        name: segment[:primary_name],
        start_time: segment[:start_time],
        end_time: segment[:end_time],
        duration_ms: segment[:end_time] - segment[:start_time],
        attributes: segment[:attributes] || %{}
      }

      %{tx | spans: [span | tx.spans]}
    end)

    # Set as current span for nesting
    Process.put(@span_key, span_id)
    span_id
  end

  ## Error Management

  @doc """
  Record an error in the current transaction.
  """
  def record_error(error, custom_attrs \\ %{}) do
    update_transaction(fn tx ->
      error_data = %{
        type: error_type(error),
        message: Exception.message(error),
        stacktrace:
          Exception.format_stacktrace(Process.info(self(), :current_stacktrace) |> elem(1)),
        timestamp: System.system_time(:millisecond),
        custom_attributes: custom_attrs
      }

      %{tx | errors: [error_data | tx.errors], error: error}
    end)
  end

  ## Metric Management

  @doc """
  Track a metric in the current transaction.
  """
  def track_metric({identifier, values}) do
    update_transaction(fn tx ->
      metric_key = metric_key(identifier)

      metric =
        Map.get(tx.metrics, metric_key, %{
          call_count: 0,
          total_time: 0,
          min_time: :infinity,
          max_time: 0
        })

      duration = Keyword.get(values, :duration_s, 0)

      updated_metric = %{
        call_count: metric.call_count + 1,
        total_time: metric.total_time + duration,
        min_time: min(metric.min_time, duration),
        max_time: max(metric.max_time, duration)
      }

      %{tx | metrics: Map.put(tx.metrics, metric_key, updated_metric)}
    end)
  end

  ## Helpers

  defp update_transaction(fun) do
    case Process.get(@transaction_key) do
      nil -> :no_transaction
      tx -> Process.put(@transaction_key, fun.(tx))
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp error_type(error) when is_exception(error) do
    error.__struct__ |> to_string()
  end

  defp error_type(_), do: "Error"

  defp metric_key({:datastore, db, table, op}), do: "Datastore/#{db}/#{table}/#{op}"
  defp metric_key({:external, host, method}), do: "External/#{host}/#{method}"
  defp metric_key({:function, module, function}), do: "Function/#{module}/#{function}"
  defp metric_key(name) when is_binary(name), do: name

  defp flatten_attributes(attrs, prefix \\ "")

  defp flatten_attributes(map, prefix) when is_map(map) do
    map
    |> Enum.take(10)
    |> Enum.flat_map(fn {k, v} ->
      key = if prefix == "", do: to_string(k), else: "#{prefix}.#{k}"
      flatten_attributes(v, key)
    end)
    |> Map.new()
    |> Map.put("#{prefix}.size", map_size(map))
  end

  defp flatten_attributes(list, prefix) when is_list(list) do
    list
    |> Enum.take(10)
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} ->
      flatten_attributes(v, "#{prefix}.#{i}")
    end)
    |> Map.new()
    |> Map.put("#{prefix}.length", length(list))
  end

  defp flatten_attributes(value, prefix) do
    %{prefix => inspect(value)}
  end
end
