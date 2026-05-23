defmodule Mix.Tasks.Trinity.Route.Demo do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.route.demo`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.route.demo"

  @deprecated "Run mix trinity.route.demo from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_route_demo, argv)
end
