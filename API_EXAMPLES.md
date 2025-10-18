# ElixirDashboard API Examples

Complete examples demonstrating 100% feature parity with New Relic Agent.

## Transaction Tracking

### Web Transactions (Auto-instrumented)

```elixir
# Automatically tracked via Plug/Phoenix telemetry
# Just add to your supervision tree and routes
```

### Other Transactions (Manual)

```elixir
# Background worker
defmodule MyApp.Worker do
  def process_batch(items) do
    ElixirDashboard.other_transaction "Worker", "ProcessBatch" do
      Enum.each(items, &process_item/1)
    end
  end
end

# GenServer
defmodule MyApp.Consumer do
  def handle_info({:process, data}, state) do
    ElixirDashboard.start_transaction("GenServer", "Consumer/ProcessMessage")
    # ... do work ...
    ElixirDashboard.stop_transaction()
    {:noreply, state}
  end
end
```

### Transaction Names

```elixir
# In a controller
def show(conn, %{"id" => id}) do
  ElixirDashboard.set_transaction_name("/Users/show/#{id}")
  # ... render ...
end
```

## Custom Attributes

### Simple Attributes

```elixir
ElixirDashboard.add_attributes(
  user_id: current_user.id,
  plan: current_user.plan,
  feature_flags: ["new_ui", "beta_features"]
)
```

### Nested Data (Auto-flattened)

```elixir
ElixirDashboard.add_attributes(
  user: %{
    id: 123,
    email: "user@example.com",
    subscription: %{
      plan: "premium",
      trial: false,
      mrr: 99.00
    }
  }
)

# Becomes:
# "user.id" => "123"
# "user.email" => "user@example.com"
# "user.subscription.plan" => "premium"
# "user.subscription.trial" => "false"
# "user.subscription.mrr" => "99.0"
# "user.size" => 3
```

### Counter Attributes

```elixir
# Increment counters during request
ElixirDashboard.incr_attributes(
  cache_hits: 1,
  database_queries: 1
)

ElixirDashboard.incr_attributes(
  cache_hits: 2  # Now total is 3
)
```

## Span Reporting

### Manual Spans

```elixir
# External HTTP call
ElixirDashboard.report_span(
  timestamp_ms: System.system_time(:millisecond),
  duration_s: 0.234,
  name: "External/api.stripe.com/POST",
  category: :http,
  attributes: %{
    "http.url" => "https://api.stripe.com/v1/charges",
    "http.method" => "POST",
    "http.status_code" => 200,
    "component" => "httpc"
  }
)

# Database operation
ElixirDashboard.report_span(
  duration_s: 0.042,
  name: "Datastore/PostgreSQL/users/SELECT",
  category: :datastore,
  attributes: %{
    "db.statement" => "SELECT * FROM users WHERE id = $1",
    "db.instance" => "production_db",
    "peer.hostname" => "db.example.com",
    "db.table" => "users",
    "db.operation" => "SELECT"
  }
)
```

### Auto-instrumented Spans

```elixir
# Ecto queries automatically create datastore spans
# Phoenix actions automatically create spans
# Just configure the telemetry handlers
```

## Error Tracking

### Basic Error Reporting

```elixir
try do
  dangerous_operation()
rescue
  e in RuntimeError ->
    ElixirDashboard.notice_error(e)
    {:error, :failed}
end
```

### Errors with Context

```elixir
try do
  process_payment(amount, card)
rescue
  e ->
    ElixirDashboard.notice_error(e, %{
      payment_amount: amount,
      card_last_4: String.slice(card.number, -4..-1),
      user_id: user.id,
      retry_attempt: attempt
    })

    {:error, :payment_failed}
end
```

### Expected Errors

```elixir
# Mark as expected (won't alert)
ElixirDashboard.notice_error(
  %ValidationError{message: "Invalid input"},
  %{expected: true, field: "email"}
)
```

## Metrics

### Datastore Metrics

```elixir
# Automatically collected via Ecto handler
# Or manually:
ElixirDashboard.report_metric(
  {:datastore, "PostgreSQL", "orders", "INSERT"},
  duration_s: 0.012
)
```

### External Service Metrics

```elixir
ElixirDashboard.report_metric(
  {:external, "api.github.com", "GET"},
  duration_s: 0.456
)
```

### Custom Metrics

```elixir
# Processing time
ElixirDashboard.report_metric(
  "Custom/ImageProcessing/ResizeTime",
  duration_s: 1.234
)

# Counter
ElixirDashboard.increment_metric("Custom/Cache/Hits")
ElixirDashboard.increment_metric("Custom/Queue/Messages")
```

## Custom Events

### Application Events

```elixir
# User signup
ElixirDashboard.report_custom_event("UserSignup", %{
  email: user.email,
  plan: "premium",
  source: "google_ads",
  campaign: "summer_sale"
})

# Purchase
ElixirDashboard.report_custom_event("PurchaseCompleted", %{
  order_id: order.id,
  amount: order.total,
  currency: "USD",
  items_count: length(order.items),
  payment_method: "stripe"
})

# Feature usage
ElixirDashboard.report_custom_event("FeatureUsed", %{
  feature: "pdf_export",
  user_id: user.id,
  duration_ms: 523
})
```

## Querying Data

### Get Transactions

```elixir
# Get slowest web transactions
slow_web = ElixirDashboard.get_transactions(
  type: :web,
  sort: :duration_desc,
  limit: 10
)

# Get failed transactions
errors = ElixirDashboard.get_transactions(status: :error)

# Get transactions from last hour
one_hour_ago = System.system_time(:millisecond) - 3_600_000
recent = ElixirDashboard.get_transactions(since: one_hour_ago)

# Analyze transaction data
Enum.each(slow_web, fn tx ->
  IO.puts("#{tx.name}: #{tx.duration_ms}ms")
  IO.puts("  Attributes: #{inspect(tx.custom_attributes)}")
  IO.puts("  Spans: #{length(tx.spans)}")
  IO.puts("  Errors: #{length(tx.errors)}")
end)
```

### Get Spans

```elixir
# Get all database spans
db_spans = ElixirDashboard.get_spans(category: :datastore, limit: 100)

# Analyze slow queries
db_spans
|> Enum.sort_by(& &1.duration_s, :desc)
|> Enum.take(10)
|> Enum.each(fn span ->
  IO.puts("#{span.duration_s}s - #{span.attributes["db.statement"]}")
end)
```

### Get Errors

```elixir
# Recent errors
errors = ElixirDashboard.get_errors(limit: 50)

# Group by error type
errors
|> Enum.group_by(& &1.error_type)
|> Enum.each(fn {type, errs} ->
  IO.puts("#{type}: #{length(errs)} occurrences")
end)
```

### Get Metrics

```elixir
# All metrics
metrics = ElixirDashboard.get_metrics()

# Top 10 slowest operations
metrics
|> Enum.sort_by(& &1.total_call_time, :desc)
|> Enum.take(10)
|> Enum.each(fn m ->
  avg = m.total_call_time / m.call_count
  IO.puts("#{m.name}")
  IO.puts("  Calls: #{m.call_count}")
  IO.puts("  Total: #{m.total_call_time}s")
  IO.puts("  Avg: #{avg}s")
  IO.puts("  Min: #{m.min_call_time}s")
  IO.puts("  Max: #{m.max_call_time}s")
end)
```

### Statistics

```elixir
stats = ElixirDashboard.get_stats()

IO.puts """
Observability Data:
  Transactions: #{stats.transactions}
  Spans: #{stats.spans}
  Errors: #{stats.errors}
  Metrics: #{stats.metrics}
  Custom Events: #{stats.custom_events}

Storage: #{stats.storage_type} (#{stats.storage_path})
"""
```

## Distributed Tracing

### Outgoing Requests

```elixir
# When making HTTP request to another service
defmodule MyApp.APIClient do
  def call_service do
    ElixirDashboard.start_transaction("Task", "CallExternalAPI")

    # Get trace headers
    trace_headers = ElixirDashboard.create_distributed_trace_payload(:http)

    # Add to your HTTP request
    headers = Map.merge(
      %{"authorization" => "Bearer #{token}"},
      trace_headers
    )

    HTTPoison.get("https://api.example.com/users", headers)

    ElixirDashboard.stop_transaction()
  end
end
```

### Incoming Requests

```elixir
# In your Plug/Phoenix app
defmodule MyAppWeb.Plugs.DistributedTrace do
  def call(conn, _opts) do
    # Extract trace headers
    headers = %{
      "traceparent" => get_req_header(conn, "traceparent"),
      "tracestate" => get_req_header(conn, "tracestate")
    }

    # This connects to parent trace
    ElixirDashboard.accept_distributed_trace_payload(headers, :http)

    conn
  end
end
```

## Complete Example: E-commerce Transaction

```elixir
defmodule MyApp.CheckoutController do
  def create(conn, %{"order" => order_params}) do
    ElixirDashboard.set_transaction_name("/Checkout/create")

    ElixirDashboard.add_attributes(
      user_id: current_user.id,
      cart_total: cart.total,
      items_count: length(cart.items),
      payment_method: order_params["payment_method"]
    )

    # Process payment (external API call tracked as span)
    case process_payment(cart, order_params) do
      {:ok, charge} ->
        ElixirDashboard.add_attributes(
          payment_success: true,
          charge_id: charge.id
        )

        ElixirDashboard.report_custom_event("PurchaseCompleted", %{
          order_id: order.id,
          amount: cart.total,
          user_id: current_user.id
        })

        ElixirDashboard.increment_metric("Custom/Checkout/Success")

        render(conn, "success.html", order: order)

      {:error, reason} ->
        ElixirDashboard.notice_error(
          %PaymentError{message: "Payment failed: #{reason}"},
          %{
            reason: reason,
            amount: cart.total,
            payment_method: order_params["payment_method"]
          }
        )

        ElixirDashboard.increment_metric("Custom/Checkout/Failed")

        render(conn, "error.html", error: reason)
    end
  end
end
```

## Viewing Data

### Via Mix Tasks

```bash
# Get statistics
mix dashboard.stats

# View recent data in IEx
iex -S mix
iex> ElixirDashboard.get_transactions(limit: 5)
iex> ElixirDashboard.get_errors()
iex> ElixirDashboard.get_metrics() |> Enum.take(10)
```

### Via LiveView Dashboards

Visit:
- http://localhost:4000/dev/performance/endpoints
- http://localhost:4000/dev/performance/queries
- http://localhost:4000/dev/performance/errors (coming soon)
- http://localhost:4000/dev/performance/spans (coming soon)

## Configuration

```elixir
# config/dev.exs
config :elixir_dashboard,
  # Data collection
  collect_queries: true,           # Collect full SQL text
  collect_stack_traces: true,      # Full stack traces for errors

  # Storage limits
  max_items: %{
    transactions: 1000,
    spans: 5000,
    errors: 500,
    metrics: 2000,
    events: 1000
  },

  # Telemetry
  repo_prefixes: [[:my_app, :repo]],

  # Display
  app_name: "MyApp Dashboard"
```

## Feature Parity Checklist

✅ **Transaction Tracking**
- Web transactions via HTTP telemetry
- Other transactions via API
- Transaction naming and renaming
- Start/stop control
- Nested transaction detection

✅ **Attributes**
- Custom attributes
- Nested attribute flattening
- Increment attributes (counters)
- Agent attributes (automatic)

✅ **Spans**
- Manual span reporting
- Auto-instrumented spans (Ecto, HTTP)
- Parent-child relationships
- Span categories (generic, http, datastore)
- Rich attributes per category

✅ **Error Tracking**
- Exception capture
- Stack traces
- Custom error attributes
- Transaction association
- Expected vs unexpected errors

✅ **Metrics**
- Datastore metrics
- External service metrics
- Custom metrics
- Metric aggregation (min/max/avg)
- Counter metrics

✅ **Custom Events**
- Arbitrary event types
- Rich attributes
- Timestamp tracking

✅ **Distributed Tracing**
- W3C Trace Context headers
- Trace ID propagation
- Parent-child trace linking
- Priority sampling

✅ **Process Management**
- Transaction references
- Cross-process connection
- Exclude from transaction
- Transaction scoping

✅ **Querying**
- Filter by time range
- Filter by type/status
- Sort by duration
- Limit results
- Rich data access

✅ **Storage**
- DETS persistent storage
- Automatic pruning
- Statistics API
- Clear all data

## What's Different from New Relic?

| Feature | New Relic | ElixirDashboard |
|---------|-----------|-----------------|
| Data Storage | Cloud (New Relic servers) | Local (DETS files) |
| Data Retention | Configurable (days/weeks) | Configurable (max items) |
| Viewing | New Relic Web UI | LiveView dashboards |
| Cost | Paid service | Free & open source |
| Setup | API key required | Zero configuration |
| Network | Sends data to cloud | All local |
| Production | Designed for production | Designed for development |
| Harvesting | Batched uploads every 60s | Immediate storage |
| Sampling | Adaptive sampling | Store all (or configure) |

## Next: LiveView Dashboards

Coming soon for the new data:
- Transaction timeline view
- Span flame graphs
- Error detail pages
- Metric trend charts
- Custom event explorer
