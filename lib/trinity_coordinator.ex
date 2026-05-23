# credo:disable-for-this-file Credo.Check.Refactor.Apply
defmodule TrinityCoordinator do
  @moduledoc """
  Compatibility facade for `trinity_framework`.

  New code should depend on `trinity_framework` and call `Trinity` or
  `Trinity.SingleNode` directly. This package remains only for one deprecation
  window while downstream imports are switched.
  """

  @roles %{0 => "Worker", 1 => "Thinker", 2 => "Verifier"}
  @gpu_demo_command "XLA_TARGET=cuda12 mix trinity.route.demo --mock-provider"

  @deprecated "Use Trinity.compile_config/1 from trinity_framework"
  defdelegate compile_config(input), to: Trinity

  @deprecated "Use Trinity.compile_config!/1 from trinity_framework"
  defdelegate compile_config!(input), to: Trinity

  @deprecated "Use Trinity.route/2 from trinity_framework"
  defdelegate route(config, context), to: Trinity

  @deprecated "Use Trinity.start_session/1 from trinity_framework"
  defdelegate start_session(input), to: Trinity

  @deprecated "Use Trinity.SingleNode.load_runtime/1 from trinity_framework"
  def load_runtime(opts \\ []), do: apply(single_node_module(), :load_runtime, [opts])

  @deprecated "Use Trinity.SingleNode.route/2 from trinity_framework"
  def route_messages(messages, opts \\ []),
    do: apply(single_node_module(), :route, [messages, opts])

  @deprecated "Use Trinity.SingleNode.dispatch/3 from trinity_framework"
  def dispatch(decision_or_route, messages, opts \\ []) do
    apply(single_node_module(), :dispatch, [decision_or_route, messages, opts])
  end

  @deprecated "Use Trinity.RolePack or framework config instead"
  def roles, do: @roles

  @deprecated "Run mix trinity.route.demo --mock-provider from trinity_framework"
  def gpu_demo_command, do: @gpu_demo_command

  defp single_node_module, do: Module.concat([Trinity, SingleNode])
end
