defmodule ElixirTracer.OtherTransaction do
  @moduledoc """
  Support for "Other" (non-web) transactions like background jobs, workers, etc.
  """

  alias ElixirTracer.Transaction.Reporter

  @doc """
  Start an other transaction.

  ## Examples

      ElixirTracer.start_transaction("Worker", "EmailProcessor")
      ElixirTracer.start_transaction("GenStage", "MyConsumer/EventType")
      ElixirTracer.start_transaction("Task", "DataImport")
  """
  def start_transaction(category, name, _headers \\ %{}) do
    full_name = "/#{category}/#{name}"
    Reporter.start_transaction(:other, full_name)
  end

  @doc """
  Stop the current other transaction.
  """
  def stop_transaction do
    Reporter.stop_transaction()
  end
end
