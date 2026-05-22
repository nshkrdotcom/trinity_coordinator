defmodule TrinityCoordinator.Runtime.BackendLabel do
  @moduledoc """
  Compatibility shim for backend-label recovery.

  The implementation now lives in `CrucibleTensorPatch.BackendLabel` so tensor
  patching and the coordinator share one backend-label contract.
  """

  defdelegate from_label(label), to: CrucibleTensorPatch.BackendLabel
  defdelegate from_label!(label), to: CrucibleTensorPatch.BackendLabel
end
