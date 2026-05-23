defmodule Mix.Tasks.Trinity.Gates do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.gates`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.gates"

  @deprecated "Run mix trinity.gates from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_gates, argv)
end
