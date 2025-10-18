defmodule ElixirTracer.MetricTest do
  # SHARED STORAGE - must be sync
  use ElixirTracer.SupertesterCase, async: false

  describe "Metric.Reporter" do
    test "report_metric creates metric" do
      metric = Metric.Reporter.report_metric("Custom/TestMetric", duration_s: 0.5)

      assert metric.name == "Custom/TestMetric"
      assert metric.call_count == 1
      assert metric.total_call_time == 0.5
    end

    test "datastore metric identifier" do
      metric =
        Metric.Reporter.report_metric(
          {:datastore, "PostgreSQL", "users", "SELECT"},
          duration_s: 0.042
        )

      assert metric.name == "Datastore/statement/PostgreSQL/users/SELECT"
      assert metric.scope == ""
    end

    test "external metric identifier" do
      metric =
        Metric.Reporter.report_metric(
          {:external, "api.stripe.com", "POST"},
          duration_s: 0.234
        )

      assert metric.name == "External/api.stripe.com/POST"
    end

    test "function metric identifier" do
      metric =
        Metric.Reporter.report_metric(
          {:function, "MyModule", "my_function"},
          duration_s: 0.1
        )

      assert metric.name == "Function/MyModule/my_function"
    end

    test "increment_metric creates counter" do
      Metric.Reporter.increment_metric("Custom/PageViews")
      Metric.Reporter.increment_metric("Custom/PageViews")
      Metric.Reporter.increment_metric("Custom/PageViews")

      metrics = Query.get_metrics()
      metric = Enum.find(metrics, &(&1.name == "Custom/PageViews"))

      assert metric.call_count == 3
      assert metric.total_call_time == 0
    end

    test "metrics are aggregated in storage" do
      Metric.Reporter.report_metric("Test/Metric", duration_s: 0.1)
      Metric.Reporter.report_metric("Test/Metric", duration_s: 0.2)
      Metric.Reporter.report_metric("Test/Metric", duration_s: 0.15)

      metrics = Query.get_metrics()
      metric = Enum.find(metrics, &(&1.name == "Test/Metric"))

      assert metric.call_count == 3
      assert_in_delta metric.total_call_time, 0.45, 0.001
      assert metric.min_call_time == 0.1
      assert metric.max_call_time == 0.2
      # sum_of_squares calculation: 0.1^2 + 0.2^2 + 0.15^2 = 0.0725
      assert_in_delta metric.sum_of_squares, 0.0725, 0.001
    end

    test "different metrics stored separately" do
      Metric.Reporter.report_metric("Metric/A", duration_s: 0.1)
      Metric.Reporter.report_metric("Metric/B", duration_s: 0.2)
      Metric.Reporter.report_metric("Metric/C", duration_s: 0.3)

      metrics = Query.get_metrics()
      assert length(metrics) == 3

      names = Enum.map(metrics, & &1.name) |> Enum.sort()
      assert names == ["Metric/A", "Metric/B", "Metric/C"]
    end
  end

  describe "Metric.merge/2" do
    test "merge combines two metrics" do
      m1 = %Metric{
        name: "Test",
        scope: "",
        call_count: 2,
        total_call_time: 0.3,
        total_exclusive_time: 0.3,
        min_call_time: 0.1,
        max_call_time: 0.2,
        sum_of_squares: 0.05
      }

      m2 = %Metric{
        name: "Test",
        scope: "",
        call_count: 3,
        total_call_time: 0.6,
        total_exclusive_time: 0.6,
        min_call_time: 0.15,
        max_call_time: 0.25,
        sum_of_squares: 0.13
      }

      merged = Metric.merge(m1, m2)

      assert merged.call_count == 5
      assert_in_delta merged.total_call_time, 0.9, 0.001
      assert merged.min_call_time == 0.1
      assert merged.max_call_time == 0.25
      assert_in_delta merged.sum_of_squares, 0.18, 0.001
    end
  end
end
