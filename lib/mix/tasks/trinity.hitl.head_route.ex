defmodule Mix.Tasks.Trinity.Hitl.HeadRoute do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.hitl.head_route`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.hitl.head_route"

  @deprecated "Run mix trinity.hitl.head_route from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_head_route, argv)
end
