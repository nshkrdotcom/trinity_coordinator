defmodule TrinityCoordinator.Runtime.BackendLabel do
  @moduledoc """
  Recovers an Nx backend specifier from a `TrinityCoordinator.Runtime.tensor_backend/1` label.

  ## Why this exists

  Three Sakana-side modules (`Artifact`, `Head`, `PythonImporter`) round-trip
  a tensor through `Runtime.tensor_backend/1` to capture a label, then need
  to recover the originating backend so the freshly-built (or imported)
  tensor can be transferred / aligned onto the same backend the source
  tensor lived on. Before this module existed each of those three modules
  carried its own private `backend_from_label/1` clauses, and each silently
  fell back to `Nx.BinaryBackend` for any label the cond did not explicitly
  enumerate. Once `tensor_backend/1` started producing generic labels for
  backends like `"EMLX.Backend"` or `"Emily.Backend"` (Phase 2), the silent
  fallback meant Apple-resident tensors were quietly being coerced to host
  memory inside alignment paths — a correctness hazard, not cosmetics.

  ## Contract

    * `from_label/1` returns `{:ok, backend_spec}` for every label the
      project knows how to round-trip, and `{:error, {:unknown_backend_label, label}}`
      otherwise. Callers that can refuse use this form.

    * `from_label!/1` is a safe-fallback variant: known labels return the
      same `backend_spec` (without the `:ok` wrapper); unknown labels emit
      a `Logger.warning/1` and return `Nx.BinaryBackend`. This preserves
      the prior silent-fallback semantics for callers that have to keep
      running — they just become *audible*.

  Adding a new backend lane (e.g. an eventual `:emily` first-class profile)
  is a one-line addition here. Do **not** scatter new backend cases across
  the Sakana modules.
  """

  require Logger

  @type backend_spec :: module() | {module(), keyword()}

  @doc """
  Returns `{:ok, backend_spec}` for known labels, `{:error, {:unknown_backend_label, label}}` otherwise.
  """
  @spec from_label(String.t()) ::
          {:ok, backend_spec()} | {:error, {:unknown_backend_label, String.t()}}
  def from_label("EXLA.Backend<cuda" <> _), do: {:ok, {EXLA.Backend, client: :cuda}}
  def from_label("EXLA.Backend<rocm" <> _), do: {:ok, {EXLA.Backend, client: :rocm}}
  def from_label("EXLA.Backend<host" <> _), do: {:ok, {EXLA.Backend, client: :host}}
  def from_label("Nx.BinaryBackend"), do: {:ok, Nx.BinaryBackend}
  def from_label("EMLX.Backend" <> _), do: {:ok, {EMLX.Backend, device: :gpu}}
  def from_label(other) when is_binary(other), do: {:error, {:unknown_backend_label, other}}

  @doc """
  Same as `from_label/1` but logs and returns `Nx.BinaryBackend` for unknown labels.

  This mirrors the historical silent-fallback semantics of the three private
  `backend_from_label/1` clauses in `Artifact`, `Head`, and `PythonImporter`,
  with the audible upgrade that unknown labels now show up in logs instead
  of disappearing.
  """
  @spec from_label!(String.t()) :: backend_spec()
  def from_label!(label) when is_binary(label) do
    case from_label(label) do
      {:ok, backend_spec} ->
        backend_spec

      {:error, {:unknown_backend_label, ^label}} ->
        Logger.warning(
          "unknown backend label #{inspect(label)}, falling back to Nx.BinaryBackend"
        )

        Nx.BinaryBackend
    end
  end
end
