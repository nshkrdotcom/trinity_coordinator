defmodule TrinityCoordinator.ArtifactFetch.Pin do
  @moduledoc """
  Compatibility wrapper for the TRINITY artifact pin descriptor.

  The strict pin parser and verifier now live in
  `CrucibleModelRegistry.Pins.ArtifactPin`. This module preserves the
  coordinator's historical struct shape for one release window.
  """

  alias CrucibleModelRegistry.Pins.{ArtifactPin, RequiredFile}

  @enforce_keys [:version, :repo_id, :revision, :manifest_sha256, :files]
  defstruct [:version, :repo_id, :revision, :manifest_sha256, :files]

  @type entry :: %{required(:path) => String.t(), required(:sha256) => String.t()}
  @type t :: %__MODULE__{
          version: integer(),
          repo_id: String.t(),
          revision: String.t(),
          manifest_sha256: String.t(),
          files: [entry()]
        }

  @doc "Loads a pin descriptor from disk."
  @spec load_pin!(Path.t()) :: t()
  def load_pin!(path) do
    path
    |> ArtifactPin.load!()
    |> from_registry_pin()
  end

  @doc false
  @spec from_registry_pin(ArtifactPin.t()) :: t()
  def from_registry_pin(%ArtifactPin{} = pin) do
    %__MODULE__{
      version: pin.version,
      repo_id: pin.repo_id,
      revision: pin.revision,
      manifest_sha256: pin.manifest_sha256,
      files: Enum.map(pin.files, &from_required_file/1)
    }
  end

  @doc false
  @spec to_registry_pin(t()) :: ArtifactPin.t()
  def to_registry_pin(%__MODULE__{} = pin) do
    ArtifactPin.new!(%{
      version: pin.version,
      repo_id: pin.repo_id,
      revision: pin.revision,
      manifest_sha256: pin.manifest_sha256,
      files: pin.files
    })
  end

  defp from_required_file(%RequiredFile{} = file),
    do: %{path: file.path, sha256: file.sha256}
end
