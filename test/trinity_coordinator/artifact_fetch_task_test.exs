defmodule Mix.Tasks.Trinity.Artifact.FetchTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Trinity.Artifact.Fetch
  alias TrinityCoordinator.ArtifactFetch.Pin

  @tmp_prefix "trinity_artifact_fetch_task_test"

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)
    on_exit(fn -> Mix.shell(previous_shell) end)

    tmp = unique_tmp_dir()
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)
    {:ok, tmp: tmp}
  end

  test "prints --help and returns :ok without invoking the downloader", %{tmp: tmp} do
    pin_path = write_synthetic_pin!(tmp, [{"manifest.json", ""}])

    parent = self()

    downloader = fn _ ->
      send(parent, :downloader_invoked)
      {:ok, "/should/not/be/used"}
    end

    Process.put(:trinity_artifact_fetch_downloader, downloader)
    on_exit(fn -> Process.delete(:trinity_artifact_fetch_downloader) end)

    assert :ok = Fetch.run(["--help", "--pin", pin_path, "--dest", Path.join(tmp, "dest")])

    refute_received :downloader_invoked
  end

  test "fetches into the given --dest using the injected downloader", %{tmp: tmp} do
    pin_path = write_synthetic_pin!(tmp, [{"manifest.json", "manifest-bytes"}])
    cache = Path.join(tmp, "cache")
    File.mkdir_p!(cache)
    File.write!(Path.join(cache, "manifest.json"), "manifest-bytes")

    downloader = fn args ->
      {:ok, Path.join(cache, args[:filename])}
    end

    Process.put(:trinity_artifact_fetch_downloader, downloader)
    on_exit(fn -> Process.delete(:trinity_artifact_fetch_downloader) end)

    dest = Path.join(tmp, "dest")

    assert :ok = Fetch.run(["--pin", pin_path, "--dest", dest])
    assert File.read!(Path.join(dest, "manifest.json")) == "manifest-bytes"
  end

  test "--offline forwards offline_mode through to the downloader", %{tmp: tmp} do
    pin_path = write_synthetic_pin!(tmp, [{"manifest.json", "x"}])
    cache = Path.join(tmp, "cache")
    File.mkdir_p!(cache)
    File.write!(Path.join(cache, "manifest.json"), "x")

    parent = self()

    downloader = fn args ->
      send(parent, {:downloader_args, args})
      {:ok, Path.join(cache, args[:filename])}
    end

    Process.put(:trinity_artifact_fetch_downloader, downloader)
    on_exit(fn -> Process.delete(:trinity_artifact_fetch_downloader) end)

    assert :ok =
             Fetch.run([
               "--pin",
               pin_path,
               "--dest",
               Path.join(tmp, "dest"),
               "--offline"
             ])

    assert_receive {:downloader_args, args}
    assert args[:offline_mode] == true
  end

  test "fails with Mix.Error when the pin file does not exist", %{tmp: tmp} do
    missing = Path.join(tmp, "no_such_pin.json")

    assert_raise Mix.Error, fn ->
      Fetch.run(["--pin", missing])
    end
  end

  # Regression for the fresh-clone onboarding crash uncovered by the
  # clean-room test on 2026-05-21:
  #
  #     ** (ArgumentError) unknown registry: Req.Finch
  #
  # The task wires through `HfHub.Download.hf_hub_download/1`, which uses
  # Req + Finch under the hood. On a fresh clone the
  # `mix trinity.artifact.fetch` invocation never started the application
  # supervision tree, so Finch's registry was never spun up. Every other
  # `mix trinity.*` task in `lib/mix/tasks/` calls
  # `Mix.Task.run("app.start")` first; this task was the outlier.
  #
  # We do not hit the network here: the injected downloader returns a
  # valid cached file. We only assert that `:hf_hub` is started after the
  # task returns, which is the observable signal that `app.start` ran.
  test "starts the application supervision tree before invoking the downloader",
       %{tmp: tmp} do
    Application.stop(:trinity_coordinator)
    Application.stop(:hf_hub)

    refute :hf_hub in Enum.map(Application.started_applications(), &elem(&1, 0))

    pin_path = write_synthetic_pin!(tmp, [{"manifest.json", "manifest-bytes"}])
    cache = Path.join(tmp, "cache")
    File.mkdir_p!(cache)
    File.write!(Path.join(cache, "manifest.json"), "manifest-bytes")

    downloader = fn args -> {:ok, Path.join(cache, args[:filename])} end
    Process.put(:trinity_artifact_fetch_downloader, downloader)
    on_exit(fn -> Process.delete(:trinity_artifact_fetch_downloader) end)

    assert :ok = Fetch.run(["--pin", pin_path, "--dest", Path.join(tmp, "dest")])

    assert :hf_hub in Enum.map(Application.started_applications(), &elem(&1, 0)),
           "trinity.artifact.fetch must start the application tree so Finch/Req are available"
  end

  defp write_synthetic_pin!(tmp, files, opts \\ []) do
    pin_path = Path.join(tmp, "pin.json")
    shas = Keyword.get(opts, :shas, %{})
    paths = Enum.map(files, &file_path/1)

    pin =
      %Pin{
        version: 1,
        repo_id: Keyword.get(opts, :repo_id, "owner/repo"),
        revision: Keyword.get(opts, :revision, "v1"),
        manifest_sha256: manifest_sha(paths, files, shas),
        files:
          Enum.map(files, fn file ->
            path = file_path(file)
            %{path: path, sha256: Map.get(shas, path, file_sha(file))}
          end)
      }
      |> Map.from_struct()
      |> Jason.encode!()

    File.write!(pin_path, pin)
    pin_path
  end

  defp manifest_sha(paths, files, shas) do
    cond do
      Map.has_key?(shas, "manifest.json") ->
        Map.fetch!(shas, "manifest.json")

      "manifest.json" in paths ->
        files |> Enum.find(&(file_path(&1) == "manifest.json")) |> file_sha()

      true ->
        sha256("")
    end
  end

  defp file_path({path, _content}), do: path
  defp file_path(path) when is_binary(path), do: path

  defp file_sha({_path, content}), do: sha256(content)
  defp file_sha(path) when is_binary(path), do: sha256(path)

  defp sha256(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  end

  defp unique_tmp_dir do
    Path.join([System.tmp_dir!(), "#{@tmp_prefix}-#{System.unique_integer([:positive])}"])
  end
end
