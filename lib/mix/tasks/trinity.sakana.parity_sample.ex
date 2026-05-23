defmodule Mix.Tasks.Trinity.Sakana.ParitySample do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.sakana.parity_sample`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.sakana.parity_sample"

  @deprecated "Run mix trinity.sakana.parity_sample from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_parity_sample, argv)
end
