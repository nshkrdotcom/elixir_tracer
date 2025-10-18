defmodule ElixirTracer.Telemetry.PhoenixHandler do
  @moduledoc """
  Phoenix telemetry handler - adds Phoenix-specific instrumentation.

  Tracks:
  - Controller actions
  - Phoenix routes
  - Template rendering
  - Errors
  """

  alias ElixirTracer.Transaction

  @phoenix_router_start [:phoenix, :router_dispatch, :start]
  @phoenix_endpoint_start [:phoenix, :endpoint, :start]
  @phoenix_endpoint_stop [:phoenix, :endpoint, :stop]
  @phoenix_error [:phoenix, :error_rendered]

  @phoenix_events [
    @phoenix_router_start,
    @phoenix_endpoint_start,
    @phoenix_endpoint_stop,
    @phoenix_error
  ]

  def attach do
    :telemetry.attach_many(
      "elixir_tracer_phoenix",
      @phoenix_events,
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  def detach do
    :telemetry.detach("elixir_tracer_phoenix")
  end

  @doc false
  def handle_event(event, measurements, metadata, config)

  def handle_event([:phoenix, :endpoint, :start], _measurements, metadata, _config) do
    conn = metadata.conn
    path = "#{conn.method} #{conn.request_path}"

    Transaction.Reporter.start_transaction(:web, path)

    Transaction.Reporter.add_attributes([
      {"phoenix.endpoint", inspect(conn.private[:phoenix_endpoint])},
      {"http.method", conn.method},
      {"http.url", conn.request_path},
      {"request.headers.host", get_header(conn, "host")},
      {"request.headers.user_agent", get_header(conn, "user-agent")}
    ])
  end

  def handle_event([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    conn = metadata.conn

    Transaction.Reporter.add_attributes([
      {"http.status_code", conn.status},
      {"response.status", conn.status},
      {"phoenix.format", conn.private[:phoenix_format]},
      {"duration_ms", duration_ms}
    ])

    Transaction.Reporter.stop_transaction()
  end

  def handle_event([:phoenix, :router_dispatch, :start], _measurements, meta, _config) do
    Transaction.Reporter.set_transaction_name(phoenix_name(meta))

    Transaction.Reporter.add_attributes([
      {"phoenix.plug_name", plug_name(meta.conn, meta.route)},
      {"phoenix.controller", inspect(meta.plug)},
      {"phoenix.action", action_name(meta.plug_opts)},
      {"phoenix.router", inspect(meta.conn.private[:phoenix_router])}
    ])
  end

  def handle_event([:phoenix, :error_rendered], _measurements, metadata, _config) do
    Transaction.Reporter.add_attributes([
      {"phoenix.error.kind", metadata.kind},
      {"phoenix.error.reason", inspect(metadata.reason)},
      {"error", true}
    ])
  end

  defp phoenix_name(%{route: route, plug: controller, plug_opts: action}) do
    "/Phoenix/#{route}/#{controller_name(controller)}/#{action_name(action)}"
  end

  defp controller_name(controller) do
    controller
    |> inspect()
    |> String.replace("Elixir.", "")
    |> String.replace("Controller", "")
  end

  defp action_name(action) when is_atom(action), do: to_string(action)
  defp action_name(action), do: inspect(action)

  defp plug_name(conn, route) do
    case {conn.private[:phoenix_controller], conn.private[:phoenix_action]} do
      {nil, nil} -> route
      {controller, action} -> "#{inspect(controller)}##{action}"
    end
  end

  defp get_header(conn, name) do
    case List.keyfind(conn.req_headers, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end
end
