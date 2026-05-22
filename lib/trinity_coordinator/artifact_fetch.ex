defmodule TrinityCoordinator.ArtifactFetch do
  @moduledoc """
  Compatibility facade for fetching the Sakana-adapted Qwen3 artifact bundle.

  Fetch and verification now live in `CrucibleModelRegistry.Pins.*`; this
  module preserves the coordinator's public task-facing API for one release
  window.
  """

  alias CrucibleModelRegistry.Pins.Fetcher
  alias TrinityCoordinator.ArtifactFetch.Pin

  @default_pin_path "priv/sakana_trinity/artifact_pin.json"
  @default_dest "priv/sakana_trinity/adapted_qwen3_0_6b_layer26"

  @typedoc "Downloader callback signature."
  @type downloader :: (keyword() -> {:ok, Path.t()} | {:error, term()})

  @doc "Default location for the project's pinned artifact descriptor."
  @spec default_pin_path() :: Path.t()
  def default_pin_path, do: @default_pin_path

  @doc "Default destination for the materialised artifact bundle."
  @spec default_dest() :: Path.t()
  def default_dest, do: @default_dest

  @doc "Loads the pinned descriptor from disk."
  @spec load_pin!(Path.t()) :: Pin.t()
  def load_pin!(path \\ @default_pin_path), do: Pin.load_pin!(path)

  @doc """
  Fetches every file listed in `pin` into `:dest`.

  Returns `:ok` to preserve the historical coordinator API. The underlying
  registry fetcher returns a receipt, which future callers should use directly.
  """
  @spec fetch!(Pin.t(), keyword()) :: :ok
  def fetch!(%Pin{} = pin, opts \\ []) when is_list(opts) do
    opts =
      Keyword.validate!(opts,
        dest: @default_dest,
        downloader: &default_download/1,
        offline_mode: false,
        progress_callback: nil
      )

    fetcher_opts = [
      downloader: Keyword.fetch!(opts, :downloader),
      offline_mode: Keyword.fetch!(opts, :offline_mode),
      progress_callback: Keyword.get(opts, :progress_callback)
    ]

    pin
    |> Pin.to_registry_pin()
    |> Fetcher.fetch!(Keyword.fetch!(opts, :dest), fetcher_opts)

    :ok
  end

  @doc "Default downloader. Delegates to `HfHub.Download.hf_hub_download/1`."
  @spec default_download(keyword()) :: {:ok, Path.t()} | {:error, term()}
  def default_download(args) do
    HfHub.Download.hf_hub_download(args)
  end
end
