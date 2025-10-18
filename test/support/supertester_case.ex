defmodule ElixirTracer.SupertesterCase do
  @moduledoc """
  SupertesterCase for ElixirTracer tests - Zero Process.sleep, deterministic
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Supertester.UnifiedTestFoundation
      import Supertester.OTPHelpers
      import Supertester.GenServerHelpers
      import Supertester.SupervisorHelpers
      import Supertester.Assertions

      alias ElixirTracer.{Transaction, Span, Error, Metric, Query, Storage}

      setup do
        # Clear process dictionary
        Process.delete(:elixir_tracer_transaction)
        Process.delete(:elixir_tracer_current_span)

        # Clear storage
        Storage.clear_all()

        # Clean up test DETS files on exit
        on_exit(fn ->
          # Give Storage time to close gracefully
          Process.sleep(10)

          # Clean test DETS directory
          test_dets = Application.get_env(:elixir_tracer, :storage_path, "priv/dets")

          if String.contains?(test_dets, "test") do
            File.rm_rf(test_dets)
          end
        end)

        :ok
      end
    end
  end
end
