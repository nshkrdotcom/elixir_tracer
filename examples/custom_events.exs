#!/usr/bin/env elixir

# Custom Events Example
# Shows how to track application-specific events

Mix.install([{:elixir_tracer, path: "."}])

{:ok, _} = Application.ensure_all_started(:elixir_tracer)

IO.puts("\n=== Custom Events Example ===\n")

# Example 1: User Signups
IO.puts("1. Tracking user signups...\n")

for i <- 1..3 do
  ElixirTracer.CustomEvent.Reporter.report_custom_event("UserSignup", %{
    user_id: 1000 + i,
    email: "user#{i}@example.com",
    plan: Enum.random(["free", "premium", "enterprise"]),
    source: Enum.random(["organic", "google_ads", "referral"]),
    trial_days: 14
  })

  IO.puts("   ✓ Signup #{i} recorded")
end

# Example 2: Purchases
IO.puts("\n2. Tracking purchases...\n")

purchases = [
  %{amount: 29.99, product: "Basic Plan", currency: "USD"},
  %{amount: 99.99, product: "Pro Plan", currency: "USD"},
  %{amount: 299.99, product: "Enterprise", currency: "USD"}
]

Enum.each(purchases, fn purchase ->
  ElixirTracer.CustomEvent.Reporter.report_custom_event("PurchaseCompleted", %{
    amount: purchase.amount,
    product: purchase.product,
    currency: purchase.currency,
    payment_method: "stripe",
    timestamp: System.system_time(:millisecond)
  })

  IO.puts("   ✓ Purchase recorded: #{purchase.product} - $#{purchase.amount}")
end)

# Example 3: Feature Usage
IO.puts("\n3. Tracking feature usage...\n")

features = ["pdf_export", "api_access", "advanced_analytics", "team_collaboration"]

Enum.each(features, fn feature ->
  ElixirTracer.CustomEvent.Reporter.report_custom_event("FeatureUsed", %{
    feature_name: feature,
    user_id: :rand.uniform(1000),
    session_duration_ms: :rand.uniform(30000),
    platform: Enum.random(["web", "mobile", "api"])
  })

  IO.puts("   ✓ Feature usage: #{feature}")
end)

# Query and analyze events
IO.puts("\n=== Event Analysis ===\n")

all_events = ElixirTracer.Query.get_custom_events()
IO.puts("Total events: #{length(all_events)}")

# Group by type
by_type = Enum.group_by(all_events, & &1.type)

Enum.each(by_type, fn {type, events} ->
  IO.puts("\n#{type}: #{length(events)} events")

  case type do
    "UserSignup" ->
      plans = Enum.map(events, & &1.attributes.plan)
      IO.puts("  Plans: #{inspect(Enum.frequencies(plans))}")

    "PurchaseCompleted" ->
      total = Enum.sum(Enum.map(events, & &1.attributes.amount))
      IO.puts("  Total revenue: $#{Float.round(total, 2)}")

    "FeatureUsed" ->
      features = Enum.map(events, & &1.attributes.feature_name)
      IO.puts("  Top features: #{inspect(Enum.frequencies(features))}")

    _ ->
      :ok
  end
end)

IO.puts("\n✅ Custom events example complete!\n")
