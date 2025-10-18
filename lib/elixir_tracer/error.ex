defmodule ElixirTracer.Error do
  @moduledoc """
  Error trace data structure - represents an exception that occurred.
  """

  defstruct [
    :id,
    :timestamp,
    :transaction_name,
    :transaction_id,
    :message,
    :error_type,
    :expected,
    :stack_trace,
    :pid,
    agent_attributes: %{},
    user_attributes: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          timestamp: non_neg_integer(),
          transaction_name: String.t(),
          transaction_id: String.t() | nil,
          message: String.t(),
          error_type: String.t(),
          expected: boolean(),
          stack_trace: list(),
          pid: pid(),
          agent_attributes: map(),
          user_attributes: map()
        }
end
