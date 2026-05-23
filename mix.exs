defmodule TrinityCoordinator.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/nshkrdotcom/trinity_coordinator"

  def project do
    [
      app: :trinity_coordinator,
      version: @version,
      elixir: "~> 1.18",
      description: "Compatibility shim for trinity_framework.",
      source_url: @source_url,
      homepage_url: @source_url,
      start_permanent: Mix.env() == :prod,
      package: package(),
      docs: docs(),
      elixirc_options: [ignore_module_conflict: true],
      deps: deps(),
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        credo: :test,
        dialyzer: :test,
        docs: :dev
      ]
    ]
  end

  defp deps do
    [
      {:trinity_framework, path: "../trinity_framework"},
      {:trinity_ops, path: "../trinity_framework/tools/trinity_ops"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: :trinity_coordinator,
      licenses: ["MIT"],
      maintainers: ["nshkrdotcom"],
      links: %{
        "GitHub" => @source_url,
        "Successor repo" => "https://github.com/nshkrdotcom/trinity_framework"
      },
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
