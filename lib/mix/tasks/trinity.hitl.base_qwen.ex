defmodule Mix.Tasks.Trinity.Hitl.BaseQwen do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.hitl.base_qwen`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.hitl.base_qwen"

  @deprecated "Run mix trinity.hitl.base_qwen from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_base_qwen, argv)
end
