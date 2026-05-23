defmodule Mix.Tasks.Trinity.Sakana.ExportAdapted do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.sakana.export_adapted`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.sakana.export_adapted"

  @deprecated "Run mix trinity.sakana.export_adapted from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_export_adapted, argv)
end
