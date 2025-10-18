defmodule ElixirTracer.SupertesterCase do
  @moduledoc """
  SupertesterCase for ElixirTracer tests.

  CRITICAL: With async:true, we CANNOT use shared global storage.
  Each test must have isolated storage or run sync.

  For now: Force async:false for tests that use Storage.
  Future: Implement per-test isolated storage backends.
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

        # IMPORTANT: Storage.clear_all() is NOT safe with async:true
        # because all tests share the same DETS tables.
        # Tests that query storage MUST use async:false OR
        # we need per-test storage isolation (TODO)

        Storage.clear_all()

        :ok
      end
    end
  end
end
