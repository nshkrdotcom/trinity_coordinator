defmodule TrinityCoordinator.ArtifactFetchTest do
  use ExUnit.Case, async: false

  alias TrinityCoordinator.ArtifactFetch
  alias TrinityCoordinator.ArtifactFetch.Pin

  @tmp_prefix "trinity_artifact_fetch_unit_test"

  setup do
    tmp = unique_tmp_dir()
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "Pin.load_pin!/1" do
    test "returns a Pin struct with repo_id, revision, files", %{tmp: tmp} do
      pin_path = Path.join(tmp, "pin.json")
      manifest_sha = sha256("manifest-bytes")
      router_sha = sha256("router-head-bytes")

      File.write!(
        pin_path,
        Jason.encode!(%{
          version: 1,
          repo_id: "owner/repo",
          revision: "v1.2.3",
          manifest_sha256: manifest_sha,
          files: [
            %{path: "manifest.json", sha256: manifest_sha},
            %{path: "router_head.safetensors", sha256: router_sha}
          ]
        })
      )

      pin = Pin.load_pin!(pin_path)
      assert pin.repo_id == "owner/repo"
      assert pin.revision == "v1.2.3"
      assert pin.manifest_sha256 == manifest_sha
      assert length(pin.files) == 2
      assert hd(pin.files).path == "manifest.json"
      assert hd(pin.files).sha256 == manifest_sha
    end

    test "raises a descriptive error on schema violations", %{tmp: tmp} do
      pin_path = Path.join(tmp, "bad.json")
      File.write!(pin_path, ~s({"version": 1, "repo_id": "x"}))

      assert_raise ArgumentError, fn ->
        Pin.load_pin!(pin_path)
      end
    end

    test "raises if pin file does not exist", %{tmp: tmp} do
      pin_path = Path.join(tmp, "missing.json")

      assert_raise File.Error, fn ->
        Pin.load_pin!(pin_path)
      end
    end

    test "raises on unsupported version", %{tmp: tmp} do
      pin_path = Path.join(tmp, "wrong.json")

      File.write!(pin_path, """
      {"version": 999, "repo_id": "x", "revision": "v1", "files": []}
      """)

      assert_raise ArgumentError, fn ->
        Pin.load_pin!(pin_path)
      end
    end
  end

  describe "fetch!/3 with injected downloader" do
    test "downloads each pin file via the injected downloader", %{tmp: tmp} do
      files = [
        {"manifest.json", "manifest-bytes"},
        {"router_head.safetensors", "router-head-bytes"}
      ]

      pin = synthetic_pin(files)
      dest = Path.join(tmp, "bundle")
      cache = Path.join(tmp, "cache")

      seed_cache_files(cache, files)

      downloader = stub_downloader_ok(cache)

      :ok = ArtifactFetch.fetch!(pin, dest: dest, downloader: downloader)

      assert File.read!(Path.join(dest, "manifest.json")) == "manifest-bytes"
      assert File.read!(Path.join(dest, "router_head.safetensors")) == "router-head-bytes"
    end

    test "creates nested directories for files under checkpoints/", %{tmp: tmp} do
      files = [{"checkpoints/foo.safetensors", "foo-bytes"}]
      pin = synthetic_pin(files)
      dest = Path.join(tmp, "bundle")
      cache = Path.join(tmp, "cache")

      seed_cache_files(cache, files)

      downloader = stub_downloader_ok(cache)

      :ok = ArtifactFetch.fetch!(pin, dest: dest, downloader: downloader)

      assert File.read!(Path.join(dest, "checkpoints/foo.safetensors")) == "foo-bytes"
    end

    test "raises when downloader returns a checksum_mismatch error", %{tmp: tmp} do
      pin = synthetic_pin(["manifest.json"])
      dest = Path.join(tmp, "bundle")

      downloader = fn _args ->
        {:error, {:checksum_mismatch, "expected_sha", "actual_sha"}}
      end

      assert_raise RuntimeError, fn ->
        ArtifactFetch.fetch!(pin, dest: dest, downloader: downloader)
      end
    end

    test "skips re-downloading files already present with correct sha256", %{tmp: tmp} do
      pin = synthetic_pin(["manifest.json"], shas: %{"manifest.json" => sha256("present")})
      dest = Path.join(tmp, "bundle")
      File.mkdir_p!(dest)
      File.write!(Path.join(dest, "manifest.json"), "present")

      downloader = fn _args ->
        send(self(), :downloader_invoked)
        {:ok, "/should/not/be/used"}
      end

      :ok = ArtifactFetch.fetch!(pin, dest: dest, downloader: downloader)
      refute_received :downloader_invoked
    end

    test "honours offline_mode by passing through to the downloader options",
         %{tmp: tmp} do
      dest = Path.join(tmp, "bundle")
      cache = Path.join(tmp, "cache")
      files = [{"manifest.json", "manifest-bytes"}]
      pin = synthetic_pin(files)
      seed_cache_files(cache, files)

      received_opts = self()

      downloader = fn args ->
        send(received_opts, {:downloader_args, args})
        {:ok, Path.join(cache, args[:filename])}
      end

      :ok =
        ArtifactFetch.fetch!(pin,
          dest: dest,
          downloader: downloader,
          offline_mode: true
        )

      assert_receive {:downloader_args, args}
      assert args[:offline_mode] == true
    end

    test "forwards repo_id and revision from the pin to the downloader",
         %{tmp: tmp} do
      files = [{"manifest.json", "manifest-bytes"}]

      pin =
        synthetic_pin(files,
          repo_id: "owner/repo",
          revision: "v9.9.9"
        )

      dest = Path.join(tmp, "bundle")
      cache = Path.join(tmp, "cache")
      seed_cache_files(cache, files)

      parent = self()

      downloader = fn args ->
        send(parent, {:downloader_args, args})
        {:ok, Path.join(cache, args[:filename])}
      end

      :ok = ArtifactFetch.fetch!(pin, dest: dest, downloader: downloader)

      assert_receive {:downloader_args, args}
      assert args[:repo_id] == "owner/repo"
      assert args[:revision] == "v9.9.9"
      assert args[:repo_type] == :dataset
      assert args[:verify_checksum] == true
    end
  end

  describe "default_pin_path/0" do
    test "returns the project's pinned pin file location" do
      assert ArtifactFetch.default_pin_path() ==
               "priv/sakana_trinity/artifact_pin.json"
    end
  end

  describe "default_dest/0" do
    test "returns the default artifact directory" do
      assert ArtifactFetch.default_dest() ==
               "priv/sakana_trinity/adapted_qwen3_0_6b_layer26"
    end
  end

  # ───────────── helpers ─────────────

  defp synthetic_pin(files, opts \\ []) do
    shas = Keyword.get(opts, :shas, %{})
    paths = Enum.map(files, &file_path/1)

    %Pin{
      version: 1,
      repo_id: Keyword.get(opts, :repo_id, "owner/repo"),
      revision: Keyword.get(opts, :revision, "v1"),
      manifest_sha256: Map.get(shas, "manifest.json", "deadbeef"),
      files:
        Enum.map(files, fn file ->
          path = file_path(file)

          %{
            path: path,
            sha256: Map.get(shas, path, file_sha(file))
          }
        end)
    }
    |> maybe_put_manifest_sha(paths, shas)
  end

  defp maybe_put_manifest_sha(%Pin{} = pin, paths, shas) do
    manifest_sha =
      cond do
        Map.has_key?(shas, "manifest.json") ->
          Map.fetch!(shas, "manifest.json")

        "manifest.json" in paths ->
          pin.files |> Enum.find(&(&1.path == "manifest.json")) |> Map.fetch!(:sha256)

        true ->
          sha256("")
      end

    %{pin | manifest_sha256: manifest_sha}
  end

  defp file_path({path, _content}), do: path
  defp file_path(path) when is_binary(path), do: path

  defp file_sha({_path, content}), do: sha256(content)
  defp file_sha(path) when is_binary(path), do: sha256(path)

  defp seed_cache_files(cache_root, files) do
    File.mkdir_p!(cache_root)

    Enum.each(files, fn {rel, content} ->
      target = Path.join(cache_root, rel)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, content)
    end)
  end

  defp stub_downloader_ok(cache_root) do
    fn args ->
      {:ok, Path.join(cache_root, args[:filename])}
    end
  end

  defp sha256(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  end

  defp unique_tmp_dir do
    Path.join([
      System.tmp_dir!(),
      "#{@tmp_prefix}-#{System.unique_integer([:positive])}"
    ])
  end
end
