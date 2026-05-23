defmodule Mix.Tasks.Trinity.Demo do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.demo`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.demo"

  @deprecated "Run mix trinity.demo from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_demo, argv)
end
