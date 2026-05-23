defmodule Mix.Tasks.Trinity.Sakana.LargeTensorChunks do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.sakana.large_tensor_chunks`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.sakana.large_tensor_chunks"

  @deprecated "Run mix trinity.sakana.large_tensor_chunks from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_large_tensor_chunks, argv)
end
