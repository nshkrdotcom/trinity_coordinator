defmodule Mix.Tasks.Trinity.Hitl.Gpu do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.hitl.gpu`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.hitl.gpu"

  @deprecated "Run mix trinity.hitl.gpu from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_gpu, argv)
end
