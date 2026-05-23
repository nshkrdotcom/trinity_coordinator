defmodule Mix.Tasks.Trinity.Sakana.ImportPython do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.sakana.import_python`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.sakana.import_python"

  @deprecated "Run mix trinity.sakana.import_python from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_import_python, argv)
end
