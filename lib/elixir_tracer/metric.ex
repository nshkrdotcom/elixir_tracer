defmodule ElixirTracer.Metric do
  @moduledoc """
  Metric data structure - represents aggregated performance data.
  """

  defstruct [
    :name,
    :scope,
    :call_count,
    :total_call_time,
    :total_exclusive_time,
    :min_call_time,
    :max_call_time,
    :sum_of_squares
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          scope: String.t(),
          call_count: non_neg_integer(),
          total_call_time: float(),
          total_exclusive_time: float(),
          min_call_time: float(),
          max_call_time: float(),
          sum_of_squares: float()
        }

  @doc """
  Merge two metrics with the same name/scope.
  """
  def merge(%__MODULE__{} = m1, %__MODULE__{} = m2) do
    %__MODULE__{
      name: m1.name,
      scope: m1.scope,
      call_count: m1.call_count + m2.call_count,
      total_call_time: m1.total_call_time + m2.total_call_time,
      total_exclusive_time: m1.total_exclusive_time + m2.total_exclusive_time,
      min_call_time: min(m1.min_call_time, m2.min_call_time),
      max_call_time: max(m1.max_call_time, m2.max_call_time),
      # Sum of squares adds
      sum_of_squares: m1.sum_of_squares + m2.sum_of_squares
    }
  end
end
