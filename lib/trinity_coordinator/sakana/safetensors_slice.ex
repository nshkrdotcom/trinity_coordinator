defmodule TrinityCoordinator.Sakana.SafetensorsSlice do
  @moduledoc """
  Release-window compatibility shim for bounded lazy SafeTensors row reads.

  The implementation now lives in `Crucible.Safetensors.Slice`. This module
  keeps existing coordinator call sites stable while downstream code migrates to
  the crucible package directly.
  """

  defdelegate row_slice!(lazy_tensor, row_start, row_count), to: Crucible.Safetensors.Slice
  defdelegate materialize!(tensor), to: Crucible.Safetensors.Slice
end
