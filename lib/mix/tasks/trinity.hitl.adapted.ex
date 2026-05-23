defmodule Mix.Tasks.Trinity.Hitl.Adapted do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.hitl.adapted`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.hitl.adapted"

  @deprecated "Run mix trinity.hitl.adapted from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_adapted, argv)
end
