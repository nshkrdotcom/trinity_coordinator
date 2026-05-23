defmodule TrinityCoordinatorShimTest do
  use ExUnit.Case, async: true

  test "keeps legacy metadata helpers during the deprecation window" do
    assert TrinityCoordinator.roles() == %{0 => "Worker", 1 => "Thinker", 2 => "Verifier"}
    assert TrinityCoordinator.gpu_demo_command() =~ "mix trinity.route.demo"
  end

  test "re-exports framework facades" do
    assert Code.ensure_loaded?(TrinityCoordinator)
    assert function_exported?(TrinityCoordinator, :compile_config, 1)
    assert function_exported?(TrinityCoordinator, :compile_config!, 1)
    assert function_exported?(TrinityCoordinator, :route, 2)
    assert function_exported?(TrinityCoordinator, :start_session, 1)
    assert function_exported?(TrinityCoordinator, :route_messages, 2)
    assert function_exported?(TrinityCoordinator, :load_runtime, 1)
  end
end
