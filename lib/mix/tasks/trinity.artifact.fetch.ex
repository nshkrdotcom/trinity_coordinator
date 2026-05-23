defmodule Mix.Tasks.Trinity.Artifact.Fetch do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.artifact.fetch`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.artifact.fetch"

  @deprecated "Run mix trinity.artifact.fetch from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_artifact_fetch, argv)
end
