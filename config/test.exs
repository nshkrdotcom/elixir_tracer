import Config

# Silence info logs during tests
config :logger, level: :warning

# Use separate DETS directory for tests (gets cleaned up)
config :elixir_tracer,
  storage_path: "test/fixtures/dets"
