defmodule ElixirTracer.Telemetry.PlugHandler do
  @moduledoc """
  Plug/HTTP telemetry handler - tracks web transactions.

  Instruments Cowboy and Bandit web servers to capture HTTP request/response lifecycle.
  """

  alias ElixirTracer.Transaction

  @cowboy_start [:cowboy, :request, :start]
  @cowboy_stop [:cowboy, :request, :stop]
  @cowboy_exception [:cowboy, :request, :exception]
  @bandit_start [:bandit, :request, :start]
  @bandit_stop [:bandit, :request, :stop]
  @bandit_exception [:bandit, :request, :exception]

  @plug_events [
    @cowboy_start,
    @cowboy_stop,
    @cowboy_exception,
    @bandit_start,
    @bandit_stop,
    @bandit_exception
  ]

  def attach do
    :telemetry.attach_many(
      "elixir_tracer_plug",
      @plug_events,
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  def detach do
    :telemetry.detach("elixir_tracer_plug")
  end

  @doc false
  def handle_event(event, measurements, meta, config)

  def handle_event([_server, :request, :start], measurements, meta, _config) do
    path = extract_path(meta)
    method = extract_method(meta)

    Transaction.Reporter.start_transaction(:web, "#{method} #{path}")

    Transaction.Reporter.add_attributes([
      {"http.method", method},
      {"http.url", path},
      {"request.uri", path},
      {"request.method", method},
      {"timestamp", measurements[:system_time] || System.system_time()}
    ])
  end

  def handle_event([_server, :request, :stop], measurements, meta, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    status = extract_status(meta)

    Transaction.Reporter.add_attributes([
      {"http.status_code", status},
      {"response.status", status},
      {"duration_ms", duration_ms}
    ])

    Transaction.Reporter.stop_transaction()
  end

  def handle_event([_server, :request, :exception], _measurements, meta, _config) do
    if meta[:kind] && meta[:reason] do
      Transaction.Reporter.record_error(meta.reason, %{
        kind: meta.kind,
        stacktrace: meta[:stacktrace]
      })
    end

    Transaction.Reporter.stop_transaction()
  end

  defp extract_path(%{req: req}) when is_map(req) do
    req[:path] || req[:request_path] || "/"
  end

  defp extract_path(%{conn: conn}) when is_map(conn) do
    conn.request_path || "/"
  end

  defp extract_path(_), do: "/"

  defp extract_method(%{req: req}) when is_map(req) do
    req[:method] || req[:request_method] || "GET"
  end

  defp extract_method(%{conn: conn}) when is_map(conn) do
    conn.method || "GET"
  end

  defp extract_method(_), do: "GET"

  defp extract_status(%{resp: resp}) when is_map(resp), do: resp[:status] || 200
  defp extract_status(%{conn: conn}) when is_map(conn), do: conn.status || 200
  defp extract_status(_), do: 200
end
