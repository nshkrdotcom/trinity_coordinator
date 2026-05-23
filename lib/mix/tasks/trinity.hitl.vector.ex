defmodule Mix.Tasks.Trinity.Hitl.Vector do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.hitl.vector`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.hitl.vector"

  @deprecated "Run mix trinity.hitl.vector from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_vector, argv)
end
