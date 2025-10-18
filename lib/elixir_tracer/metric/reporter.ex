defmodule ElixirTracer.Metric.Reporter do
  @moduledoc """
  Metric Reporter - aggregates and stores performance metrics.
  """

  alias ElixirTracer.{Metric, Storage}

  @doc """
  Report a metric.

  ## Examples

      # Datastore metric
      ElixirTracer.report_metric(
        {:datastore, "PostgreSQL", "users", "SELECT"},
        duration_s: 0.042
      )

      # External HTTP metric
      ElixirTracer.report_metric(
        {:external, "api.example.com", "POST"},
        duration_s: 0.123
      )

      # Custom metric
      ElixirTracer.report_metric(
        "Custom/MyMetric/ProcessingTime",
        duration_s: 1.5,
        count: 1
      )
  """
  def report_metric(identifier, values) do
    metric = build_metric(identifier, values)
    Storage.store_metric(metric)
    metric
  end

  @doc """
  Increment a counter metric.

  ## Example

      ElixirTracer.increment_metric("Custom/Cache/Hits")
  """
  def increment_metric(identifier) do
    report_metric(identifier, count: 1, duration_s: 0)
  end

  defp build_metric(identifier, values) do
    {name, scope} = parse_identifier(identifier)
    duration = Keyword.get(values, :duration_s, 0)
    count = Keyword.get(values, :count, 1)

    %Metric{
      name: name,
      scope: scope,
      call_count: count,
      total_call_time: duration,
      total_exclusive_time: duration,
      min_call_time: duration,
      max_call_time: duration,
      sum_of_squares: duration * duration
    }
  end

  defp parse_identifier({:datastore, db, table, op}) do
    {"Datastore/statement/#{db}/#{table}/#{op}", ""}
  end

  defp parse_identifier({:external, host, method}) do
    {"External/#{host}/#{method}", ""}
  end

  defp parse_identifier({:function, module, function}) do
    {"Function/#{module}/#{function}", ""}
  end

  defp parse_identifier(name) when is_binary(name) do
    {name, ""}
  end

  defp parse_identifier({name, scope}) do
    {name, scope}
  end
end
