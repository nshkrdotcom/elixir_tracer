# New Relic Elixir Agent - Comprehensive Feature Analysis

**Version:** Based on agent codebase analysis
**Purpose:** Technical reference for building a local-first observability solution
**Generated:** 2025-10-17

---

## Table of Contents

1. [Core Features](#1-core-features)
2. [Telemetry Handlers & Auto-Instrumentation](#2-telemetry-handlers--auto-instrumentation)
3. [Public API Reference](#3-public-api-reference)
4. [Data Structures](#4-data-structures)
5. [Supported Frameworks & Libraries](#5-supported-frameworks--libraries)
6. [Manual Instrumentation](#6-manual-instrumentation)
7. [Configuration & Feature Toggles](#7-configuration--feature-toggles)
8. [Data Collection & Reporting](#8-data-collection--reporting)

---

## 1. Core Features

### 1.1 Transaction Tracking

New Relic tracks two types of transactions:

**Web Transactions:**
- Auto-detected via telemetry events from web servers (Cowboy, Bandit)
- Tracks HTTP request/response lifecycle
- Captures request metadata, headers, timing, memory, reductions

**Other Transactions:**
- Background jobs, message queue consumers, scheduled tasks
- Manually started/stopped via API
- Examples: Oban jobs, GenStage consumers, custom workers

**Key Capabilities:**
- Transaction naming and grouping
- Custom attributes (key-value pairs)
- Automatic and manual error tracking
- Process monitoring (memory, reductions, message queue)
- Distributed tracing integration

### 1.2 Distributed Tracing

**Protocol Support:**
- W3C Trace Context (traceparent, tracestate headers)
- New Relic proprietary format
- Automatic context propagation across service boundaries

**Features:**
- Trace ID generation and propagation
- Parent-child span relationships
- Sampling with priority
- Cross-process span tracking
- Transport duration calculation

**Implementation Details:**
```elixir
# From distributed_trace.ex
defstruct source: nil,
          account_id: nil,
          app_id: nil,
          parent_id: nil,
          span_guid: nil,
          trace_id: nil,
          priority: nil,
          sampled: nil,
          timestamp: nil,
          trust_key: nil
```

### 1.3 Span Events

Spans represent individual units of work within a transaction:

**Span Categories:**
- `:generic` - Default category for any work
- `:http` - External HTTP calls
- `:datastore` - Database/cache operations
- `:error` - Failed operations

**Span Attributes:**
```elixir
# From span/event.ex
defstruct type: "Span",
          trace_id: nil,
          guid: nil,
          parent_id: nil,
          transaction_id: nil,
          sampled: nil,
          priority: nil,
          timestamp: nil,
          duration: nil,
          name: nil,
          category: nil,
          entry_point: false,
          category_attributes: %{}
```

**HTTP Span Attributes:**
- `http.url`, `http.method`, `component`, `span.kind`

**Datastore Span Attributes:**
- `db.statement`, `db.instance`, `peer.address`, `peer.hostname`, `component`

### 1.4 Error Tracking

**Error Collection:**
- Automatic exception capture in transactions
- Manual error reporting via `notice_error/2`
- Stack trace capture
- Error context (transaction name, timestamp)

**Error Structure:**
```elixir
# From error/trace.ex
defstruct timestamp: nil,
          transaction_name: "",
          message: nil,
          expected: false,
          error_type: nil,
          cat_guid: "",
          stack_trace: nil,
          agent_attributes: %{},
          user_attributes: %{}
```

### 1.5 Metrics

**Metric Types:**
- Transaction metrics (duration, throughput)
- Datastore metrics (query performance)
- External metrics (HTTP call performance)
- Custom metrics
- Dimensional metrics (count, gauge, summary)

**Metric Structure:**
```elixir
# From metric/metric.ex
defstruct name: "",
          scope: "",
          call_count: 0,
          total_call_time: 0,
          total_exclusive_time: 0,
          min_call_time: 0,
          max_call_time: 0,
          sum_of_squares: 0
```

---

## 2. Telemetry Handlers & Auto-Instrumentation

### 2.1 Plug Instrumentation

**File:** `lib/new_relic/telemetry/plug.ex`

**Events Monitored:**
```elixir
[:cowboy, :request, :start]
[:cowboy, :request, :stop]
[:cowboy, :request, :exception]
[:bandit, :request, :start]
[:bandit, :request, :stop]
[:bandit, :request, :exception]
[:plug, :router_dispatch, :start]
```

**Data Collected:**
- HTTP method, path, host
- Request/response headers
- Status code
- Duration (total, request body, response body)
- Remote IP
- User agent, referer, content type
- Memory usage, reductions
- Request queue time (via `x-request-start` header)

**Key Code:**
```elixir
defp add_start_attrs(meta, meas, headers, :cowboy) do
  [
    pid: inspect(self()),
    "http.server": "cowboy",
    start_time: meas[:system_time],
    host: meta.req.host,
    path: meta.req.path,
    remote_ip: meta.req.peer |> elem(0) |> :inet_parse.ntoa() |> to_string(),
    referer: headers["referer"],
    user_agent: headers["user-agent"],
    content_type: headers["content-type"],
    request_method: meta.req.method
  ]
  |> NewRelic.add_attributes()
end
```

### 2.2 Phoenix Instrumentation

**File:** `lib/new_relic/telemetry/phoenix.ex`

**Events Monitored:**
```elixir
[:phoenix, :router_dispatch, :start]
[:phoenix, :controller, :render, :start]
[:phoenix, :controller, :render, :stop]
[:phoenix, :error_rendered]
```

**Data Collected:**
- Controller and action names
- Phoenix endpoint, router
- Template, view, format
- Render duration
- Transaction naming based on controller/action

**Transaction Naming:**
```elixir
defp phoenix_name(%{plug: controller, plug_opts: action}) when is_atom(action) do
  "/Phoenix/#{inspect(controller)}/#{action}"
end
```

### 2.3 Phoenix LiveView Instrumentation

**File:** `lib/new_relic/telemetry/phoenix_live_view.ex`

**Events Monitored:**
```elixir
[:phoenix, :live_view, :mount, :start/stop/exception]
[:phoenix, :live_view, :handle_params, :start/stop/exception]
[:phoenix, :live_view, :handle_event, :start/stop/exception]
[:phoenix, :live_view, :render, :start/stop/exception]
```

**Data Collected:**
- LiveView module name
- Mount/handle_params/handle_event parameters
- Socket ID, action
- Router, endpoint
- Lifecycle event durations
- Render changed/forced flags

**Special Handling:**
```elixir
# Creates transaction for WebSocket process events
if meta.socket.transport_pid do
  with :collect <- Transaction.Reporter.start_transaction(:web, path) do
    NewRelic.DistributedTrace.start(:other)
    # ... collect transaction data
  end
end
```

### 2.4 Ecto Instrumentation

**File:** `lib/new_relic/telemetry/ecto/handler.ex`

**Events Monitored:**
```elixir
# Dynamically attached based on Ecto repos
[repo, :query]  # e.g., [:my_app, :repo, :query]
```

**Data Collected:**
- SQL query text (optional, controlled by config)
- Database name, hostname, port
- Query duration (total, query, queue, decode)
- Table name, operation (SELECT, INSERT, UPDATE, DELETE)
- Repo name

**Query Parsing:**
```elixir
# From ecto/metadata.ex
def parse(%{result: {:ok, %{command: command} = result}}) do
  datastore = "Postgres"  # or MySQL, etc.
  operation = command |> to_string() |> String.upcase()
  table = extract_table(result)
  {datastore, {operation, table}}
end
```

**Metrics Reported:**
```elixir
metric_name = "Datastore/statement/#{datastore}/#{table}/#{operation}"

NewRelic.incr_attributes(
  databaseCallCount: 1,
  databaseDuration: duration_s,
  datastore_call_count: 1,
  datastore_duration_ms: duration_ms
)
```

### 2.5 Redix Instrumentation

**File:** `lib/new_relic/telemetry/redix.ex`

**Events Monitored:**
```elixir
[:redix, :connection]
[:redix, :pipeline, :stop]
```

**Data Collected:**
- Redis command or pipeline
- Connection name/address
- Operation duration
- Host, port
- Query text (optional)

**Command Parsing:**
```elixir
defp parse_command([[operation | _args] = command], collect: true) do
  query = Enum.join(command, " ")
  {operation, query}
end

defp parse_command(pipeline, collect: true) do
  query = pipeline |> Enum.map(&Enum.join(&1, " ")) |> Enum.join("; ")
  {"PIPELINE", query}
end
```

### 2.6 Oban Instrumentation

**File:** `lib/new_relic/telemetry/oban.ex`

**Events Monitored:**
```elixir
[:oban, :job, :start]
[:oban, :job, :stop]
[:oban, :job, :exception]
```

**Data Collected:**
- Worker module, queue name
- Job arguments (inspected)
- Job tags, attempt number, priority
- Queue time, execution duration
- Job result/state
- Memory usage, reductions

**Transaction Naming:**
```elixir
other_transaction_name: "Oban/#{meta.queue}/#{meta.worker}/perform"
```

### 2.7 Finch Instrumentation

**File:** `lib/new_relic/telemetry/finch.ex`

**Events Monitored:**
```elixir
[:finch, :request, :start]
[:finch, :request, :stop]
[:finch, :request, :exception]
```

**Data Collected:**
- HTTP method, URL (scheme, host, path)
- Request duration
- Response status
- Finch pool name
- Error information

**External Metrics:**
```elixir
metric_name = "External/#{request.host}/Finch/#{request.method}"

NewRelic.incr_attributes(
  "external.#{request.host}.call_count": 1,
  "external.#{request.host}.duration_ms": duration_ms
)
```

### 2.8 Absinthe (GraphQL) Instrumentation

**File:** `lib/new_relic/telemetry/absinthe.ex`

**Events Monitored:**
```elixir
[:absinthe, :execute, :operation, :start]
[:absinthe, :execute, :operation, :stop]
[:absinthe, :resolve, :field, :start]
[:absinthe, :resolve, :field, :stop]
```

**Data Collected:**
- GraphQL query text (optional)
- Operation type (query, mutation, subscription)
- Operation name
- Schema module
- Field resolution details (path, type, arguments)
- Resolver function info

**Transaction Naming:**
```elixir
defp transaction_name(schema, operation) do
  deepest_path = operation |> collect_deepest_path() |> Enum.join(".")
  "Absinthe/#{inspect(schema)}/#{operation.type}/#{deepest_path}"
end
```

---

## 3. Public API Reference

### 3.1 Transaction Control

#### `set_transaction_name/1`
```elixir
@spec set_transaction_name(String.t()) :: any()
NewRelic.set_transaction_name("/Plug/custom/transaction/name")
```
Sets the transaction name. First segment is the namespace (e.g., "Plug", "Phoenix").

#### `start_transaction/2` and `start_transaction/3`
```elixir
@spec start_transaction(String.t(), String.t()) :: any()
@spec start_transaction(String.t(), String.t(), headers :: map) :: any()

NewRelic.start_transaction("GenStage", "MyConsumer/EventType")
NewRelic.start_transaction("Task", "TaskName")
NewRelic.start_transaction("WebSocket", "Handler", %{"newrelic" => "..."})
```
Starts an "Other" (non-web) transaction with optional distributed trace headers.

#### `stop_transaction/0`
```elixir
@spec stop_transaction() :: any()
NewRelic.stop_transaction()
```
Stops the current "Other" transaction.

#### `other_transaction/3` (macro)
```elixir
NewRelic.other_transaction("Worker", "ProcessMessages") do
  # Work happens here
end
```
Wraps a block of code in a transaction (start + execute + stop).

#### `ignore_transaction/0`
```elixir
@spec ignore_transaction() :: any()

def health_check(conn, _) do
  NewRelic.ignore_transaction()
  send_resp(conn, 200, "OK")
end
```
Prevents current transaction from being reported.

### 3.2 Attributes

#### `add_attributes/1`
```elixir
@spec add_attributes(attributes :: Keyword.t()) :: any()

NewRelic.add_attributes(user_id: "abc123", tier: "premium")
NewRelic.add_attributes(map: %{foo: "bar", baz: "qux"})
NewRelic.add_attributes(list: ["a", "b", "c"])
```
Adds custom attributes to the current transaction. Supports nested maps/lists (auto-flattened).

**Flattening behavior:**
- `%{foo: "bar"}` → `"map.foo" => "bar"`, `"map.size" => 1`
- `["a", "b"]` → `"list.0" => "a"`, `"list.1" => "b"`, `"list.length" => 2`

### 3.3 Distributed Tracing

#### `distributed_trace_headers/1`
```elixir
@spec distributed_trace_headers(:http) :: [{key :: String.t(), value :: String.t()}]
@spec distributed_trace_headers(:other) :: map()

headers = NewRelic.distributed_trace_headers(:http)
# Returns W3C traceparent, tracestate, and New Relic headers
Req.get(url, headers: headers)
```
Generates distributed trace headers for outgoing requests. Must be called immediately before making the request.

### 3.4 Span Management

#### `set_span/2`
```elixir
@spec set_span(:generic, attributes :: Keyword.t()) :: any()
@spec set_span(:http, url: String.t(), method: String.t(), component: String.t()) :: any()
@spec set_span(:datastore,
  statement: String.t(),
  instance: String.t(),
  address: String.t(),
  hostname: String.t(),
  component: String.t()
) :: any()

NewRelic.set_span(:http,
  url: "https://api.example.com",
  method: "GET",
  component: "HTTPoison"
)
```
Sets the current span's category and attributes.

#### `add_span_attributes/1`
```elixir
@spec add_span_attributes(attributes :: Keyword.t()) :: any()

NewRelic.add_span_attributes(user_role: "admin", cache_hit: true)
```
Adds attributes to the current span (not transaction).

#### `span/2` (macro)
```elixir
NewRelic.span("do.some_work", user_id: "abc123") do
  # Work happens here
end
```
Wraps a block in a span for instrumentation.

### 3.5 Error Reporting

#### `notice_error/2`
```elixir
@spec notice_error(Exception.t(), Exception.stacktrace()) :: any()

try do
  raise RuntimeError, "Something went wrong"
rescue
  exception ->
    NewRelic.notice_error(exception, __STACKTRACE__)
    # Continue handling...
end
```
Manually reports an exception that was rescued.

### 3.6 Process Management

#### `exclude_from_transaction/0`
```elixir
@spec exclude_from_transaction() :: any()

Task.async(fn ->
  NewRelic.exclude_from_transaction()
  Work.wont_be_included()
end)
```
Excludes current process from parent transaction.

#### `get_transaction/0` and `connect_to_transaction/1`
```elixir
@spec get_transaction() :: tx_ref
@spec connect_to_transaction(tx_ref) :: any()

tx = NewRelic.get_transaction()

spawn(fn ->
  NewRelic.connect_to_transaction(tx)
  # This work is now part of the transaction
end)
```
Advanced: Manual transaction connection across processes.

#### `disconnect_from_transaction/0`
```elixir
@spec disconnect_from_transaction() :: any()
NewRelic.disconnect_from_transaction()
```
Manually disconnects from current transaction.

### 3.7 Custom Events & Metrics

#### `report_custom_event/2`
```elixir
@spec report_custom_event(type :: String.t(), event :: map()) :: any()

NewRelic.report_custom_event("Purchase", %{
  "amount" => 99.99,
  "currency" => "USD",
  "user_id" => "123"
})
```
Reports a custom event to NRDB.

#### `report_custom_metric/2`
```elixir
@spec report_custom_metric(name :: String.t(), value :: number()) :: any()

NewRelic.report_custom_metric("Custom/MyMetric/ResponseTime", 150)
```
Reports a custom metric value.

#### `increment_custom_metric/2`
```elixir
@spec increment_custom_metric(name :: String.t(), count :: integer()) :: any()

NewRelic.increment_custom_metric("Custom/Cache/Hits")
NewRelic.increment_custom_metric("Custom/Queue/Size", 5)
```
Increments a counter metric.

#### `report_dimensional_metric/4`
```elixir
@spec report_dimensional_metric(
  type :: :count | :gauge | :summary,
  name :: String.t(),
  value :: number,
  attributes :: map()
) :: any()

NewRelic.report_dimensional_metric(:count, "my_metric_name", 1, %{
  region: "us-west",
  environment: "production"
})
```
Reports dimensional (tagged) metrics.

### 3.8 Process Sampling

#### `sample_process/0`
```elixir
@spec sample_process() :: any()

defmodule ImportantProcess do
  use GenServer

  def init(:ok) do
    NewRelic.sample_process()
    {:ok, %{}}
  end
end
```
Enables process monitoring (message queue, reductions, memory).

---

## 4. Data Structures

### 4.1 Transaction Event

**Structure:**
```elixir
defstruct type: "Transaction",
          web_duration: nil,
          database_duration: nil,
          timestamp: nil,
          name: nil,
          duration: nil,
          total_time: nil,
          user_attributes: %{}
```

**Format for reporting:**
```elixir
[
  %{
    webDuration: 0.5,
    totalTime: 0.6,
    databaseDuration: 0.2,
    timestamp: 1697500000000,
    name: "/Phoenix/UserController/show",
    duration: 0.5,
    type: "Transaction"
  },
  %{
    # User attributes
    user_id: "123",
    plan: "premium"
  }
]
```

### 4.2 Span Event

**Structure:**
```elixir
defstruct type: "Span",
          trace_id: nil,
          guid: nil,
          parent_id: nil,
          transaction_id: nil,
          sampled: nil,
          priority: nil,
          timestamp: nil,
          duration: nil,
          name: nil,
          category: nil,
          entry_point: false,
          category_attributes: %{}
```

**HTTP Span Format:**
```elixir
%{
  type: "Span",
  traceId: "abc123",
  guid: "span456",
  parentId: "parent789",
  "http.url": "https://api.example.com/users",
  "http.method": "GET",
  component: "Finch",
  "span.kind": "client"
}
```

**Datastore Span Format:**
```elixir
%{
  type: "Span",
  "db.statement": "SELECT * FROM users WHERE id = $1",
  "db.instance": "myapp_prod",
  "peer.address": "localhost:5432",
  "peer.hostname": "localhost",
  component: "Postgres",
  "span.kind": "client"
}
```

### 4.3 Error Trace

**Structure:**
```elixir
defstruct timestamp: nil,
          transaction_name: "",
          message: nil,
          expected: false,
          error_type: nil,
          cat_guid: "",
          stack_trace: nil,
          agent_attributes: %{},
          user_attributes: %{}
```

**Format for reporting:**
```elixir
[
  timestamp,
  transaction_name,
  message,
  error_type,
  %{
    stack_trace: [...],
    agentAttributes: %{request_uri: "/users/123"},
    userAttributes: %{user_id: "123"},
    intrinsics: %{"error.expected": false, traceId: "abc", guid: "xyz"}
  },
  cat_guid
]
```

### 4.4 Metric

**Structure:**
```elixir
defstruct name: "",
          scope: "",
          call_count: 0,
          total_call_time: 0,
          total_exclusive_time: 0,
          min_call_time: 0,
          max_call_time: 0,
          sum_of_squares: 0
```

**Metric Types:**
- `Datastore/statement/{datastore}/{table}/{operation}`
- `External/{host}/{component}/{method}`
- `WebTransaction/Phoenix/{controller}/{action}`
- `OtherTransaction/{category}/{name}`
- `Custom/{metric_name}`

### 4.5 Distributed Trace Context

**Structure:**
```elixir
defstruct source: nil,
          account_id: nil,
          app_id: nil,
          parent_id: nil,
          span_guid: nil,
          trace_id: nil,
          priority: nil,
          sampled: nil,
          timestamp: nil,
          trust_key: nil,
          type: nil
```

---

## 5. Supported Frameworks & Libraries

### 5.1 Web Frameworks

| Framework | Support Level | Events Monitored | Data Collected |
|-----------|--------------|------------------|----------------|
| **Plug** | Full | Request lifecycle | Request/response metadata, timing, errors |
| **Phoenix** | Full | Router dispatch, controller render | Controller/action, templates, views |
| **Phoenix LiveView** | Full | Mount, params, events, render | Lifecycle events, params, WebSocket transactions |

**HTTP Servers:**
- Cowboy (via telemetry)
- Bandit (via telemetry)

### 5.2 Databases

| Database | Library | Support Level | Events Monitored | Data Collected |
|----------|---------|---------------|------------------|----------------|
| **PostgreSQL** | Ecto | Full | Query execution | SQL, timing, connection info |
| **MySQL** | Ecto | Full | Query execution | SQL, timing, connection info |
| **MSSQL** | Ecto | Full | Query execution | SQL, timing, connection info |
| **Redis** | Redix | Full | Pipeline/commands | Commands, timing, connection |

### 5.3 Background Jobs

| Library | Support Level | Events Monitored | Data Collected |
|---------|--------------|------------------|----------------|
| **Oban** | Full | Job lifecycle | Worker, queue, args, timing, results |

### 5.4 HTTP Clients

| Library | Support Level | Events Monitored | Data Collected |
|---------|--------------|------------------|----------------|
| **Finch** | Full | Request lifecycle | URL, method, status, timing |

### 5.5 GraphQL

| Library | Support Level | Events Monitored | Data Collected |
|---------|--------------|------------------|----------------|
| **Absinthe** | Full | Operations, field resolution | Queries, operations, resolvers |

### 5.6 Automatic Instrumentation Summary

**Zero-configuration instrumentation available for:**
1. Plug pipelines (Cowboy, Bandit)
2. Phoenix controllers and templates
3. Phoenix LiveView lifecycle
4. Ecto database queries
5. Redix Redis operations
6. Oban background jobs
7. Finch HTTP requests
8. Absinthe GraphQL operations

All instrumentation can be disabled via configuration flags.

---

## 6. Manual Instrumentation

### 6.1 Function Tracing with `@trace`

**File:** `lib/new_relic/tracer.ex`

**Basic Usage:**
```elixir
defmodule MyModule do
  use NewRelic.Tracer

  @trace :my_function
  def my_function do
    # Will report as "MyModule.my_function/0"
  end

  @trace :custom_name
  def another_function(arg1, arg2) do
    # Will report as "MyModule.another_function:custom_name/2"
  end
end
```

**Disable Argument Collection:**
```elixir
@trace {:login, args: false}
def login(username, password) do
  # Arguments won't be collected
end
```

**External Service Tracing:**
```elixir
@trace {:http_request, category: :external}
def make_request(url) do
  NewRelic.set_span(:http,
    url: url,
    method: "GET",
    component: "HTTPClient"
  )

  headers = NewRelic.distributed_trace_headers(:http)
  HTTPClient.get(url, headers)
end
```

**How it works:**
```elixir
# From tracer/macro.ex
# Tracing wraps function with:
# 1. Span creation
# 2. Timing measurement
# 3. Error catching
# 4. Metric reporting
# 5. Span event generation
```

**Limitations:**
- Cannot trace recursive functions (not tail-call optimized)
- Cannot trace functions with multiple clause syntaxes (rescue, catch, etc.)
- Cannot trace function heads

### 6.2 Direct Span API

**File:** `lib/new_relic/tracer/direct.ex`

```elixir
id = make_ref()
NewRelic.Tracer.Direct.start_span(id, "MySpan",
  attributes: [user_id: "123"]
)

# Do work...

NewRelic.Tracer.Direct.stop_span(id)
```

**With timing:**
```elixir
NewRelic.Tracer.Direct.start_span(id, "MySpan",
  system_time: System.system_time(),
  attributes: [...]
)

NewRelic.Tracer.Direct.stop_span(id,
  duration: duration_in_native_time
)
```

---

## 7. Configuration & Feature Toggles

### 7.1 Required Configuration

```elixir
# config.exs
config :new_relic_agent,
  app_name: "MyApp",
  license_key: "abc123"
```

**Environment Variables:**
```bash
NEW_RELIC_APP_NAME=MyApp
NEW_RELIC_LICENSE_KEY=abc123
```

### 7.2 Feature Flags

All features default to **enabled** but can be toggled:

**Security/Privacy:**
```elixir
config :new_relic_agent,
  error_collector_enabled: false,           # Disable error collection
  query_collection_enabled: false,          # Disable SQL/query collection
  function_argument_collection_enabled: false  # Disable arg collection
```

**Instrumentation (opt-out):**
```elixir
config :new_relic_agent,
  plug_instrumentation_enabled: false,
  phoenix_instrumentation_enabled: false,
  phoenix_live_view_instrumentation_enabled: false,
  ecto_instrumentation_enabled: false,
  redix_instrumentation_enabled: false,
  oban_instrumentation_enabled: false,
  finch_instrumentation_enabled: false,
  absinthe_instrumentation_enabled: false
```

**Performance:**
```elixir
config :new_relic_agent,
  distributed_tracing_enabled: true,          # DT protocol support
  request_queuing_metrics_enabled: true,      # Request queue time
  extended_attributes_enabled: true           # Per-source attributes
```

### 7.3 Advanced Features

**Logs in Context:**
```elixir
config :new_relic_agent,
  logs_in_context: :forwarder  # or :direct or :disabled
```

**Infinite Tracing:**
```elixir
config :new_relic_agent,
  infinite_tracing_trace_observer_host: "trace-observer.host"
```

**Automatic Attributes:**
```elixir
config :new_relic_agent,
  automatic_attributes: [
    environment: {:system, "APP_ENV"},
    node_name: {Node, :self, []},
    team_name: "MyTeam"
  ]
```

**Ignore Paths:**
```elixir
config :new_relic_agent,
  ignore_paths: [
    "/health",
    ~r/longpoll/
  ]
```

**Harvest Limits:**
```elixir
config :new_relic_agent,
  analytic_event_per_minute: 1000,
  custom_event_per_minute: 1000,
  error_event_per_minute: 100,
  span_event_per_minute: 1000
```

---

## 8. Data Collection & Reporting

### 8.1 Data Types Collected

**Transaction Data:**
1. **Transaction Events** - Aggregated transaction information
2. **Transaction Traces** - Detailed segment breakdowns
3. **Transaction Metrics** - Time-series metric data

**Distributed Trace Data:**
1. **Span Events** - Individual span information with parent/child relationships
2. **Trace Context** - W3C trace propagation data

**Error Data:**
1. **Error Traces** - Full error details with stack traces
2. **Error Events** - Error occurrence metadata

**Metric Data:**
1. **Datastore Metrics** - Database operation performance
2. **External Metrics** - HTTP call performance
3. **Custom Metrics** - User-defined metrics
4. **Dimensional Metrics** - Tagged metric data

**Sample Data:**
1. **Process Samples** - Memory, reductions, message queue
2. **BEAM Samples** - VM-level metrics
3. **ETS Samples** - ETS table statistics

### 8.2 Harvesting & Reporting

**Harvest Cycle:**
- Default: 60 seconds
- Configurable per data type
- Rate-limited based on configuration

**Data Endpoints:**
```elixir
# Collector API endpoints
/agent_listener/invoke_raw_method
  - Transaction events
  - Transaction traces
  - Error traces
  - Metrics
  - Span events

# Telemetry SDK endpoints
/trace/v1  - Infinite Tracing spans
/log/v1    - Log forwarding
/metric/v1 - Dimensional metrics
```

### 8.3 Attribute Flattening

**Nested Maps:**
```elixir
%{user: %{name: "Alice", age: 30}}
# Becomes:
%{
  "user.name" => "Alice",
  "user.age" => 30,
  "user.size" => 2
}
```

**Lists:**
```elixir
["a", "b", "c"]
# Becomes:
%{
  "list.0" => "a",
  "list.1" => "b",
  "list.2" => "c",
  "list.length" => 3
}
```

**Truncation:**
- Maps/lists truncated at 10 items
- Prevents attribute explosion

### 8.4 Process Tracking

**Transaction Sidecar:**
- Each transaction tracked via separate sidecar process
- Stores attributes, metrics, spans
- Survives process crashes within transaction
- Completed on transaction end

**Span Hierarchy:**
- Process dictionary stores current span
- Parent-child relationships via references
- Duration accounting (exclusive vs total time)

**Code Reference:**
```elixir
# From distributed_trace.ex
def set_current_span(label: label, ref: ref) do
  current = {label, ref}
  previous_span = Process.delete(:nr_current_span)
  previous_span_attrs = Process.delete(:nr_current_span_attrs)
  Process.put(:nr_current_span, current)
  {current, previous_span, previous_span_attrs}
end
```

---

## 9. Key Implementation Patterns

### 9.1 Telemetry Event Handling

**Pattern:**
```elixir
# 1. GenServer with handler attachment
def init(%{enabled?: true} = config) do
  :telemetry.attach_many(
    config.handler_id,
    @events,
    &__MODULE__.handle_event/4,
    config
  )
  {:ok, config}
end

# 2. Event handling
def handle_event([:my, :event, :start], measurements, metadata, config) do
  # Start tracking
end

def handle_event([:my, :event, :stop], measurements, metadata, config) do
  # Report data
end
```

### 9.2 Distributed Trace Propagation

**Incoming:**
```elixir
# Extract from headers
w3c_headers(headers) || newrelic_header(headers) || :no_payload

# Set context
determine_context(headers)
|> track_transaction(transport_type: "HTTP")
```

**Outgoing:**
```elixir
# Generate headers
context = get_tracing_context()
nr_header = NewRelicContext.generate(context)
{traceparent, tracestate} = W3CTraceContext.generate(context)

[
  {"newrelic", nr_header},
  {"traceparent", traceparent},
  {"tracestate", tracestate}
]
```

### 9.3 Error Handling in Traces

**Pattern:**
```elixir
try do
  do_work()
rescue
  exception ->
    message = NewRelic.Util.Error.format_reason(:error, exception)
    NewRelic.DistributedTrace.set_span(:error, message: message)
    reraise exception, __STACKTRACE__
catch
  :exit, value ->
    message = NewRelic.Util.Error.format_reason(:exit, value)
    NewRelic.DistributedTrace.set_span(:error, message: "(EXIT) #{message}")
    exit(value)
end
```

---

## 10. Architecture Insights

### 10.1 Supervision Tree

```
NewRelic.Application
├── NewRelic.Harvest.Supervisor
│   ├── Collector.Supervisor (APM data)
│   └── TelemetrySdk.Supervisor (Spans, Logs, Metrics)
├── NewRelic.Telemetry.Supervisor
│   ├── Plug
│   ├── Phoenix
│   ├── PhoenixLiveView
│   ├── Ecto.Supervisor
│   ├── Redix
│   ├── Oban
│   ├── Finch
│   └── Absinthe
├── NewRelic.Transaction.Supervisor
└── NewRelic.Sampler.Supervisor
```

### 10.2 Data Flow

```
Application Code
    ↓
Telemetry Events / @trace / Public API
    ↓
Transaction.Reporter / DistributedTrace
    ↓
Transaction.Sidecar (process storage)
    ↓
Transaction.Complete (on end)
    ↓
Harvesters (buffering)
    ↓
HTTP API (New Relic backend)
```

### 10.3 Key Design Decisions

1. **Telemetry-based:** Non-invasive instrumentation via telemetry events
2. **Sidecar pattern:** Transaction data stored in separate process for crash safety
3. **Process dictionary:** Current span tracking via process dictionary (fast, local)
4. **Persistent term:** Configuration stored in persistent_term (fast reads)
5. **Macro-based tracing:** Compile-time function wrapping for low overhead
6. **Backoff sampling:** Adaptive sampling to prevent data overload

---

## 11. Local-First Implementation Considerations

### 11.1 Data to Capture

**Essential:**
- Transaction events with attributes
- Span events with parent/child relationships
- Error traces with stack traces
- Metric aggregations

**Optional but valuable:**
- Transaction traces (detailed breakdown)
- Process samples
- Custom events
- Dimensional metrics

### 11.2 Storage Strategy

**Time-series database:**
- Transaction metrics (duration, throughput, error rate)
- Datastore metrics (query performance)
- External metrics (HTTP call performance)

**Document/Event store:**
- Span events (with trace/parent/child IDs)
- Error traces
- Transaction events
- Custom events

**Relationships:**
- Trace ID → Spans (one-to-many)
- Transaction → Spans (one-to-many)
- Span → Parent Span (tree structure)

### 11.3 UI/Visualization Needs

**Transaction view:**
- List of transactions by name
- Throughput, avg duration, error rate
- Drill-down to individual traces

**Trace detail:**
- Waterfall/Gantt chart of spans
- Span details (category, attributes)
- Error highlighting

**Service map:**
- External service calls
- Database dependencies
- GraphQL operations

**Metrics dashboard:**
- Time-series graphs
- Percentiles (p50, p95, p99)
- Error rate trends

### 11.4 Required Adaptations

**Remove New Relic backend dependencies:**
- Replace harvest/reporting with local storage
- Remove license key requirements
- Disable agent communication

**Keep telemetry handlers:**
- All instrumentation works without backend
- Only change where data is sent

**Local storage harvesters:**
- Replace HTTP POST with database writes
- Maintain same data structures
- Respect same sampling/limits

**Query API:**
- Build query layer for stored data
- Support filtering by attributes
- Time-range queries
- Aggregations

---

## 12. Code Examples from Source

### 12.1 Transaction Lifecycle

```elixir
# From telemetry/plug.ex
def handle_event([server, :request, :start], measurements, meta, _config) do
  with :collect <- Transaction.Reporter.start_transaction(:web, path(meta, server)) do
    headers = get_headers(meta, server)
    DistributedTrace.start(:http, headers)
    add_start_attrs(meta, measurements, headers, server)
    maybe_report_queueing(headers)
  end
end

def handle_event([server, :request, :stop], meas, meta, _config) do
  add_stop_attrs(meas, meta, server)
  Transaction.Reporter.stop_transaction(:web)
end
```

### 12.2 Span Creation

```elixir
# From tracer/direct.ex
def start_span(id, name, opts \\ []) do
  attributes = Keyword.get(opts, :attributes, [])
  system_time = Keyword.get(opts, :system_time, System.system_time())

  {span, previous_span, previous_span_attrs} =
    NewRelic.DistributedTrace.set_current_span(label: name, ref: id)

  Process.put({:nr_span_start, id}, {span, system_time, previous_span, previous_span_attrs})

  attributes
  |> Map.new()
  |> NewRelic.DistributedTrace.add_span_attributes()
end
```

### 12.3 Metric Reporting

```elixir
# From telemetry/ecto/handler.ex
NewRelic.report_metric(
  {:datastore, datastore, table, operation},
  duration_s: duration_s
)

NewRelic.Transaction.Reporter.track_metric({
  {:datastore, datastore, table, operation},
  duration_s: duration_s
})

NewRelic.incr_attributes(
  databaseCallCount: 1,
  databaseDuration: duration_s
)
```

### 12.4 Error Capture

```elixir
# From telemetry/plug.ex
def handle_event([server, :request, :exception], meas, meta, _config) do
  add_stop_attrs(meas, meta, server)

  if NewRelic.Config.feature?(:error_collector) do
    {reason, stacktrace} = reason_and_stacktrace(meta)
    Transaction.Reporter.error(%{
      kind: meta.kind,
      reason: reason,
      stack: stacktrace
    })
  end

  Transaction.Reporter.stop_transaction(:web)
end
```

---

## Summary

The New Relic Elixir Agent is a comprehensive observability solution with:

**Strengths:**
- Zero-config auto-instrumentation for major Elixir libraries
- Deep integration with BEAM/OTP telemetry
- Distributed tracing with W3C standard support
- Rich attribute collection and custom events
- Minimal performance overhead

**Architecture:**
- Telemetry event-based (non-invasive)
- Sidecar pattern for transaction safety
- Compile-time function tracing
- Configurable sampling and limits

**For Local-First Implementation:**
- All data structures are well-defined and serializable
- Instrumentation code is independent of backend
- Clear separation between collection and reporting
- Rich metadata makes local querying powerful

**Key Files to Study:**
- `/lib/new_relic.ex` - Public API surface
- `/lib/new_relic/telemetry/*.ex` - Auto-instrumentation handlers
- `/lib/new_relic/distributed_trace.ex` - Trace context management
- `/lib/new_relic/transaction/reporter.ex` - Transaction lifecycle
- `/lib/new_relic/span/event.ex` - Span data structure
- `/lib/new_relic/error/trace.ex` - Error data structure

This analysis provides a complete reference for understanding how New Relic instruments Elixir applications and what data it collects, enabling the design of a compatible local-first alternative.
