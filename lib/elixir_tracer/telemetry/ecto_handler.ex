defmodule ElixirTracer.Telemetry.EctoHandler do
  @moduledoc """
  Ecto telemetry handler - tracks database queries.

  Auto-discovers and instruments Ecto repos.
  Captures:
  - Query duration (total, queue, decode times)
  - SQL statements
  - Database, host, port
  - Table and operation (SELECT, INSERT, UPDATE, DELETE)
  """

  alias ElixirTracer.{Transaction, Span, Metric}

  @doc """
  Attach to Ecto telemetry events for the given repo prefixes.

  ## Example

      ElixirTracer.Telemetry.EctoHandler.attach([
        [:my_app, :repo],
        [:my_app, :read_repo]
      ])
  """
  def attach(repo_prefixes) when is_list(repo_prefixes) do
    events = Enum.map(repo_prefixes, fn prefix -> prefix ++ [:query] end)

    :telemetry.attach_many(
      "elixir_tracer_ecto",
      events,
      &__MODULE__.handle_event/4,
      %{collect_queries: collect_queries?()}
    )
  end

  def detach do
    :telemetry.detach("elixir_tracer_ecto")
  end

  @doc false
  def handle_event(_event, measurements, metadata, config) do
    # Calculate timings
    total_time_ms = System.convert_time_unit(measurements.total_time, :native, :millisecond)

    query_time_ms =
      measurements[:query_time] &&
        System.convert_time_unit(measurements.query_time, :native, :millisecond)

    queue_time_ms =
      measurements[:queue_time] &&
        System.convert_time_unit(measurements.queue_time, :native, :millisecond)

    decode_time_ms =
      measurements[:decode_time] &&
        System.convert_time_unit(measurements.decode_time, :native, :millisecond)

    duration_s = total_time_ms / 1000.0
    end_time = System.system_time(:millisecond)
    start_time = end_time - total_time_ms

    # Parse query metadata
    {datastore, table, operation} = parse_query_metadata(metadata)

    query_text = if config.collect_queries, do: metadata.query, else: "[NOT_COLLECTED]"

    # Report span
    Span.Reporter.report_span(
      timestamp_ms: start_time,
      duration_s: duration_s,
      name: "Datastore/statement/#{datastore}/#{table}/#{operation}",
      category: :datastore,
      attributes: %{
        "db.statement" => query_text,
        "db.instance" => metadata.options[:database] || "unknown",
        "peer.hostname" => metadata.options[:hostname] || "unknown",
        "peer.address" => "#{metadata.options[:hostname]}:#{metadata.options[:port] || 5432}",
        "db.table" => table,
        "db.operation" => operation,
        "ecto.repo" => inspect(metadata.repo),
        "ecto.query_time.ms" => query_time_ms,
        "ecto.queue_time.ms" => queue_time_ms,
        "ecto.decode_time.ms" => decode_time_ms,
        "component" => datastore,
        "span.kind" => "client"
      }
    )

    # Report metric
    Metric.Reporter.report_metric(
      {:datastore, datastore, table, operation},
      duration_s: duration_s
    )

    # Increment transaction attributes
    Transaction.Reporter.incr_attributes(
      databaseCallCount: 1,
      databaseDuration: duration_s,
      datastore_call_count: 1,
      datastore_duration_ms: total_time_ms
    )

    :ok
  end

  defp parse_query_metadata(metadata) do
    query = metadata.query || ""

    # Determine datastore type from repo adapter
    datastore =
      cond do
        String.contains?(inspect(metadata.repo), "Postgres") -> "PostgreSQL"
        String.contains?(inspect(metadata.repo), "MySQL") -> "MySQL"
        String.contains?(inspect(metadata.repo), "MSSQL") -> "MSSQL"
        String.contains?(inspect(metadata.repo), "SQLite") -> "SQLite"
        true -> "SQL"
      end

    # Parse operation from query
    operation =
      cond do
        String.match?(query, ~r/^\s*SELECT/i) -> "SELECT"
        String.match?(query, ~r/^\s*INSERT/i) -> "INSERT"
        String.match?(query, ~r/^\s*UPDATE/i) -> "UPDATE"
        String.match?(query, ~r/^\s*DELETE/i) -> "DELETE"
        true -> "OTHER"
      end

    # Extract table name (simple heuristic)
    table =
      case Regex.run(~r/FROM\s+([a-z_]+)/i, query) do
        [_, table_name] -> table_name
        _ -> "unknown"
      end

    {datastore, table, operation}
  end

  defp collect_queries? do
    Application.get_env(:elixir_tracer, :collect_queries, true)
  end
end
