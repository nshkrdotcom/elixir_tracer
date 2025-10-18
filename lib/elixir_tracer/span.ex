defmodule ElixirTracer.Span do
  @moduledoc """
  Span data structure - represents a unit of work within a transaction.
  """

  defstruct [
    :id,
    :trace_id,
    :parent_id,
    :transaction_id,
    :name,
    :category,
    # :generic, :http, :datastore, :error
    :timestamp,
    :duration_s,
    :sampled,
    :priority,
    :entry_point,
    attributes: %{}
  ]

  @type category :: :generic | :http | :datastore | :error

  @type t :: %__MODULE__{
          id: String.t(),
          trace_id: String.t(),
          parent_id: String.t() | nil,
          transaction_id: String.t(),
          name: String.t(),
          category: category(),
          timestamp: non_neg_integer(),
          duration_s: float(),
          sampled: boolean(),
          priority: float(),
          entry_point: boolean(),
          attributes: map()
        }
end
