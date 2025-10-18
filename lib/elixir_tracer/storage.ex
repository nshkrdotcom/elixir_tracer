defmodule ElixirTracer.Storage do
  @moduledoc """
  Unified DETS storage for all observability data.

  Stores:
  - Transactions (web & other)
  - Spans
  - Errors
  - Metrics
  - Custom Events
  """
  use GenServer
  require Logger

  @dets_dir "priv/dets"
  @transactions_table :ed_transactions
  @spans_table :ed_spans
  @errors_table :ed_errors
  @metrics_table :ed_metrics
  @events_table :ed_custom_events

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def store_transaction(tx), do: GenServer.cast(__MODULE__, {:store_transaction, tx})
  def store_span(span), do: GenServer.cast(__MODULE__, {:store_span, span})
  def store_error(error), do: GenServer.cast(__MODULE__, {:store_error, error})
  def store_metric(metric), do: GenServer.cast(__MODULE__, {:store_metric, metric})
  def store_custom_event(event), do: GenServer.cast(__MODULE__, {:store_custom_event, event})

  def get_transactions(opts \\ []), do: GenServer.call(__MODULE__, {:get_transactions, opts})
  def get_spans(opts \\ []), do: GenServer.call(__MODULE__, {:get_spans, opts})
  def get_errors(opts \\ []), do: GenServer.call(__MODULE__, {:get_errors, opts})
  def get_metrics(opts \\ []), do: GenServer.call(__MODULE__, {:get_metrics, opts})
  def get_custom_events(opts \\ []), do: GenServer.call(__MODULE__, {:get_custom_events, opts})

  def clear_all, do: GenServer.cast(__MODULE__, :clear_all)

  def get_stats, do: GenServer.call(__MODULE__, :get_stats)

  ## Server Callbacks

  @impl true
  def init(_) do
    File.mkdir_p!(@dets_dir)

    tables = %{
      transactions: open_table(@transactions_table, "transactions.dets"),
      spans: open_table(@spans_table, "spans.dets"),
      errors: open_table(@errors_table, "errors.dets"),
      metrics: open_table(@metrics_table, "metrics.dets"),
      events: open_table(@events_table, "events.dets")
    }

    Logger.info("ElixirDashboard Storage initialized: #{@dets_dir}")

    {:ok, tables}
  end

  @impl true
  def handle_cast({:store_transaction, tx}, state) do
    key = {tx.start_time, tx.id}
    :dets.insert(state.transactions, {key, tx})
    prune_table(state.transactions, max_items(:transactions))
    {:noreply, state}
  end

  def handle_cast({:store_span, span}, state) do
    key = {span.timestamp, span.id}
    :dets.insert(state.spans, {key, span})
    prune_table(state.spans, max_items(:spans))
    {:noreply, state}
  end

  def handle_cast({:store_error, error}, state) do
    key = {error.timestamp, error.id}
    :dets.insert(state.errors, {key, error})
    prune_table(state.errors, max_items(:errors))
    {:noreply, state}
  end

  def handle_cast({:store_metric, metric}, state) do
    key = {metric.name, metric.scope}
    # Metrics are aggregated, not timestamped
    case :dets.lookup(state.metrics, key) do
      [{^key, existing}] ->
        merged = ElixirTracer.Metric.merge(existing, metric)
        :dets.insert(state.metrics, {key, merged})

      [] ->
        :dets.insert(state.metrics, {key, metric})
    end

    {:noreply, state}
  end

  def handle_cast({:store_custom_event, event}, state) do
    key = {event.timestamp, :rand.uniform(1_000_000)}
    :dets.insert(state.events, {key, event})
    prune_table(state.events, max_items(:events))
    {:noreply, state}
  end

  def handle_cast(:clear_all, state) do
    Enum.each(Map.values(state), &:dets.delete_all_objects/1)
    Logger.info("Cleared all ElixirDashboard data")
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_transactions, opts}, _from, state) do
    items = fetch_items(state.transactions, opts)
    {:reply, items, state}
  end

  def handle_call({:get_spans, opts}, _from, state) do
    items = fetch_items(state.spans, opts)
    {:reply, items, state}
  end

  def handle_call({:get_errors, opts}, _from, state) do
    items = fetch_items(state.errors, opts)
    {:reply, items, state}
  end

  def handle_call({:get_metrics, opts}, _from, state) do
    metrics =
      state.metrics
      |> :dets.match({:"$1", :"$2"})
      |> Enum.map(fn [_key, metric] -> metric end)
      |> apply_filters(opts)

    {:reply, metrics, state}
  end

  def handle_call({:get_custom_events, opts}, _from, state) do
    items = fetch_items(state.events, opts)
    {:reply, items, state}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      transactions: :dets.info(state.transactions, :size),
      spans: :dets.info(state.spans, :size),
      errors: :dets.info(state.errors, :size),
      metrics: :dets.info(state.metrics, :size),
      custom_events: :dets.info(state.events, :size),
      storage_path: @dets_dir,
      storage_type: "DETS"
    }

    {:reply, stats, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(Map.values(state), &:dets.close/1)
    :ok
  end

  ## Private Helpers

  defp open_table(name, filename) do
    path = Path.join(@dets_dir, filename) |> String.to_charlist()
    {:ok, table} = :dets.open_file(name, file: path, type: :set)
    table
  end

  defp fetch_items(table, opts) do
    table
    |> :dets.match({:"$1", :"$2"})
    |> Enum.map(fn [_key, item] -> item end)
    |> apply_filters(opts)
  end

  defp apply_filters(items, opts) do
    items
    |> filter_by_time(opts[:since], opts[:until])
    |> filter_by_type(opts[:type])
    |> filter_by_status(opts[:status])
    |> sort_items(opts[:sort])
    |> limit_items(opts[:limit])
  end

  defp filter_by_time(items, nil, nil), do: items

  defp filter_by_time(items, since, until) do
    Enum.filter(items, fn item ->
      ts = item.start_time || item.timestamp
      (since == nil || ts >= since) && (until == nil || ts <= until)
    end)
  end

  defp filter_by_type(items, nil), do: items
  defp filter_by_type(items, type), do: Enum.filter(items, &(&1.type == type))

  defp filter_by_status(items, nil), do: items
  defp filter_by_status(items, status), do: Enum.filter(items, &(&1.status == status))

  defp sort_items(items, nil), do: Enum.sort_by(items, &(&1.start_time || &1.timestamp), :desc)

  defp sort_items(items, :duration_desc),
    do: Enum.sort_by(items, &(&1.duration_ms || &1.duration_s), :desc)

  defp sort_items(items, :duration_asc),
    do: Enum.sort_by(items, &(&1.duration_ms || &1.duration_s), :asc)

  defp sort_items(items, _), do: items

  defp limit_items(items, nil), do: items
  defp limit_items(items, limit), do: Enum.take(items, limit)

  defp prune_table(table, max) do
    size = :dets.info(table, :size)

    if size > max do
      all = :dets.match(table, {:"$1", :"$2"})
      to_delete = Enum.drop(all, max)
      Enum.each(to_delete, fn [key, _] -> :dets.delete(table, key) end)
    end
  end

  defp max_items(type) do
    defaults = %{
      transactions: 1000,
      spans: 5000,
      errors: 500,
      metrics: 2000,
      events: 1000
    }

    Application.get_env(:elixir_tracer, :max_items, %{})
    |> Map.get(type, defaults[type])
  end
end
