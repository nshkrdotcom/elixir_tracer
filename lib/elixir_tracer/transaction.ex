defmodule ElixirTracer.Transaction do
  @moduledoc """
  Transaction data structure - represents a complete web request or background job.
  """

  defstruct [
    :id,
    :type,
    # :web or :other
    :name,
    :category,
    :start_time,
    # milliseconds
    :end_time,
    # milliseconds
    :duration_ms,
    :status,
    # :in_progress, :completed, :error
    :error,
    :pid,
    :trace_id,
    :parent_span_id,
    :sampled,
    :priority,
    attributes: %{},
    custom_attributes: %{},
    spans: [],
    errors: [],
    metrics: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          type: :web | :other,
          name: String.t(),
          category: String.t() | nil,
          start_time: non_neg_integer(),
          end_time: non_neg_integer() | nil,
          duration_ms: float() | nil,
          status: :in_progress | :completed | :error,
          error: any(),
          pid: pid(),
          trace_id: String.t() | nil,
          parent_span_id: String.t() | nil,
          sampled: boolean(),
          priority: float(),
          attributes: map(),
          custom_attributes: map(),
          spans: list(),
          errors: list(),
          metrics: map()
        }
end
