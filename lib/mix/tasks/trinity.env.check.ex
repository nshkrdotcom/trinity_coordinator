defmodule Mix.Tasks.Trinity.Env.Check do
  @moduledoc """
  Deprecated compatibility shim for `mix trinity.env.check`.
  """

  use Mix.Task

  alias Trinity.Ops.Tasks

  @shortdoc "Deprecated shim for mix trinity.env.check"

  @deprecated "Run mix trinity.env.check from trinity_framework/trinity_ops"
  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_env_check, argv)
end
