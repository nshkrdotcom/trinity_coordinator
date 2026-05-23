defmodule Mix.Tasks.Trinity.Hitl.MockLoop do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.hitl.mock_loop`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.hitl.mock_loop"

  @deprecated "Run mix trinity.hitl.mock_loop from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_mock_loop, argv)
end
