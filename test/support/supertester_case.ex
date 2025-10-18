defmodule ElixirTracer.SupertesterCase do
  @moduledoc """
  SupertesterCase for ElixirTracer tests - Zero Process.sleep, 100% async:true
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import Supertester tools
      import Supertester.UnifiedTestFoundation
      import Supertester.OTPHelpers
      import Supertester.GenServerHelpers
      import Supertester.SupervisorHelpers
      import Supertester.Assertions

      # Aliases
      alias ElixirTracer.{Transaction, Span, Error, Metric, Query, Storage}

      # Setup isolated environment
      setup do
        # Clear process dictionary before each test
        Process.delete(:elixir_tracer_transaction)
        Process.delete(:elixir_tracer_current_span)

        # Storage is started by Application, just clear data
        Storage.clear_all()

        :ok
      end
    end
  end
end
