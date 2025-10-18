# ElixirTracer

<p align="center">
  <img src="assets/elixir_tracer.svg" alt="ElixirTracer Logo" width="200"/>
</p>

Local-first observability for Elixir with New Relic API parity. ElixirTracer provides a complete tracing and observability solution that works entirely offline while maintaining compatibility with New Relic's API surface.

## Features

- **Local-First Architecture**: All data stays on your machine - no external dependencies or cloud services required
- **New Relic API Parity**: Drop-in replacement for New Relic agents with identical API surface
- **Zero Configuration**: Works out of the box with sensible defaults
- **Lightweight**: Minimal performance overhead with efficient in-memory storage
- **Privacy-Focused**: Your application data never leaves your development environment
- **Development-Optimized**: Perfect for local development, testing, and debugging

## Installation

Add `elixir_tracer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:elixir_tracer, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# In your application.ex
def start(_type, _args) do
  children = [
    # Start the ElixirTracer
    ElixirTracer,
    # ... your other children
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

That's it! ElixirTracer will automatically instrument your application and collect traces.

## Usage

ElixirTracer provides the same API as New Relic, so if you're familiar with New Relic, you already know how to use it:

```elixir
# Custom transactions
ElixirTracer.start_transaction("my_transaction")
ElixirTracer.add_custom_attributes(%{user_id: 123, action: "purchase"})
ElixirTracer.end_transaction()

# Custom events
ElixirTracer.record_custom_event("UserAction", %{
  action: "login",
  user_id: 123,
  timestamp: DateTime.utc_now()
})

# Error tracking
ElixirTracer.notice_error(%RuntimeError{message: "Something went wrong"})

# Custom metrics
ElixirTracer.record_metric("Custom/MyMetric", 42.0)
```

## Configuration

Configure ElixirTracer in your `config/config.exs`:

```elixir
config :elixir_tracer,
  # Enable/disable tracing
  enabled: true,

  # Storage backend (default: in-memory)
  storage: ElixirTracer.Storage.Memory,

  # Data retention (in seconds)
  retention_period: 3600,

  # Sampling rate (0.0 to 1.0)
  sample_rate: 1.0
```

## Why ElixirTracer?

### Local-First Development

In today's cloud-centric world, we believe developers should have full control over their observability data during development. ElixirTracer gives you:

- **Complete Privacy**: Your application data stays local
- **No Network Dependency**: Works offline and in air-gapped environments
- **Cost-Free**: No subscription fees or API limits
- **Instant Feedback**: No latency from sending data to external services

### New Relic Compatibility

If you're using New Relic in production but want a local solution for development:

- **Same API**: Switch between ElixirTracer and New Relic with minimal code changes
- **Easy Testing**: Test your instrumentation locally before deploying
- **Migration Path**: Start local, move to cloud when ready

## Documentation

Full documentation is available at [https://hexdocs.pm/elixir_tracer](https://hexdocs.pm/elixir_tracer).

## Roadmap

- [ ] OpenTelemetry compatibility layer
- [ ] Web UI for viewing traces and metrics
- [ ] Export to various formats (Zipkin, Jaeger, etc.)
- [ ] Distributed tracing support
- [ ] Integration with ElixirDashboard

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

## Links

- [GitHub](https://github.com/nshkrdotcom/elixir_tracer)
- [Documentation](https://hexdocs.pm/elixir_tracer)
- [Changelog](https://github.com/nshkrdotcom/elixir_tracer/blob/master/CHANGELOG.md)
- [Issues](https://github.com/nshkrdotcom/elixir_tracer/issues)

---

Built with care for the Elixir community.
