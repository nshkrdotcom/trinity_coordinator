defmodule Mix.Tasks.Trinity.Sakana.RouterTrace do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.sakana.router_trace`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.sakana.router_trace"

  @deprecated "Run mix trinity.sakana.router_trace from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_router_trace, argv)
end
