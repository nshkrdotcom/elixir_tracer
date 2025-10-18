defmodule ElixirTracer.CustomEvent.Reporter do
  @moduledoc """
  Custom Event Reporter - stores application-specific events.
  """

  alias ElixirTracer.Storage

  @doc """
  Report a custom event.

  ## Examples

      ElixirTracer.report_custom_event("UserSignup", %{
        email: "user@example.com",
        plan: "premium",
        referral_code: "SAVE20"
      })

      ElixirTracer.report_custom_event("PurchaseCompleted", %{
        amount: 99.99,
        currency: "USD",
        product_id: "prod_123"
      })
  """
  def report_custom_event(event_type, attributes) when is_map(attributes) do
    event = %{
      type: event_type,
      timestamp: System.system_time(:millisecond),
      attributes: attributes
    }

    Storage.store_custom_event(event)
    event
  end
end
