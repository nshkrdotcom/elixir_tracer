defmodule ElixirTracer.Error.Reporter do
  @moduledoc """
  Error Reporter - captures and stores error traces.
  """

  alias ElixirTracer.{Error, Storage, Transaction}

  @doc """
  Report an error/exception.

  ## Examples

      try do
        raise "Something broke"
      rescue
        e -> ElixirTracer.notice_error(e)
      end

      ElixirTracer.notice_error(
        %RuntimeError{message: "Custom error"},
        %{user_id: 123, context: "payment"}
      )
  """
  def notice_error(exception, custom_attributes \\ %{}) do
    tx = Process.get(:elixir_tracer_transaction)

    error = %Error{
      id: generate_id(),
      timestamp: System.system_time(:millisecond),
      transaction_name: tx && tx.name,
      transaction_id: tx && tx.id,
      message: Exception.message(exception),
      error_type: error_type(exception),
      expected: false,
      stack_trace: format_stacktrace(),
      pid: self(),
      agent_attributes: extract_agent_attributes(tx),
      user_attributes: custom_attributes
    }

    # Store error
    Storage.store_error(error)

    # Also record in transaction if active
    if tx, do: Transaction.Reporter.record_error(exception, custom_attributes)

    error
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp error_type(error) when is_exception(error) do
    error.__struct__ |> to_string()
  end

  defp error_type(_), do: "Error"

  defp format_stacktrace do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} ->
        stacktrace
        |> Enum.drop(2)
        |> Exception.format_stacktrace()

      _ ->
        []
    end
  end

  defp extract_agent_attributes(nil), do: %{}

  defp extract_agent_attributes(tx) do
    %{
      "duration_ms" => tx.duration_ms,
      "transaction_type" => tx.type,
      "pid" => inspect(tx.pid)
    }
  end
end
