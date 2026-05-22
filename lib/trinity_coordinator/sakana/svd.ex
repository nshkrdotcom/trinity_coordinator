defmodule TrinityCoordinator.Sakana.SVD do
  @moduledoc """
  Release-window compatibility shim for SVD/SVF tensor mechanics.

  The implementation now lives in `Crucible.Factorization.SVD`. This module
  keeps existing coordinator call sites stable while downstream code migrates to
  the crucible package directly.
  """

  defdelegate thin(tensor, opts \\ []), to: Crucible.Factorization.SVD
  defdelegate thin!(tensor, opts \\ []), to: Crucible.Factorization.SVD
  defdelegate decomposable_tensor?(tensor), to: Crucible.Factorization.SVD
  defdelegate decompose_tensor(tensor, opts \\ []), to: Crucible.Factorization.SVD

  defdelegate reconstruct(decomposition, scale_offsets, opts \\ []),
    to: Crucible.Factorization.SVD

  defdelegate flatten_tensors(container), to: Crucible.Factorization.SVD
  defdelegate flatten_tensor_entries(container), to: Crucible.Factorization.SVD
  defdelegate decomposable_tensors(container, opts \\ []), to: Crucible.Factorization.SVD
  defdelegate decomposable_tensor_entries(container, opts \\ []), to: Crucible.Factorization.SVD
  defdelegate layer_index_filter(indices), to: Crucible.Factorization.SVD
  defdelegate singular_value_count(tensors), to: Crucible.Factorization.SVD
  defdelegate tensor_manifest(tensors), to: Crucible.Factorization.SVD
  defdelegate decompose_tensors(tensors, opts \\ []), to: Crucible.Factorization.SVD

  defdelegate reconstruct_tensors(decompositions, scale_offsets, opts \\ []),
    to: Crucible.Factorization.SVD

  defdelegate adapt_tensors(tensors, scale_offsets, opts \\ []), to: Crucible.Factorization.SVD
  defdelegate put_tensor_entries(container, tensor_entries), to: Crucible.Factorization.SVD

  defdelegate load_router_vector!(path, tensor_name \\ "trinity_router_es_vector"),
    to: Crucible.Factorization.SVD

  defdelegate split_router_vector(vector, scale_count, hidden_size, output_count),
    to: Crucible.Factorization.SVD

  defdelegate put_linear_head_weights(params, head_weights, layer_name \\ "routing_head"),
    to: Crucible.Factorization.SVD
end
