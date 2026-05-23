defmodule Mix.Tasks.Trinity.Parity.Check do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.parity.check`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.parity.check"

  @deprecated "Run mix trinity.parity.check from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_parity_check, argv)
end
