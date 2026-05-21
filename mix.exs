unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("build_support/dependency_sources.exs", __DIR__)
end

unless Code.ensure_loaded?(XlaTargetValidator) do
  Code.require_file("build_support/xla_target_validator.exs", __DIR__)
end

# Load the XlaEnvPreflight Mix compiler eagerly so Mix can find it before
# the project's own `lib/` tree compiles. Compilers referenced from a
# project's `:compilers` list must be loadable before `mix compile`
# starts; placing the module under `lib/` would create a chicken-and-egg
# bootstrap problem (Mix would look for the compiler module before it
# has had a chance to compile `lib/`).
unless Code.ensure_loaded?(Mix.Tasks.Compile.XlaEnvPreflight) do
  Code.require_file("build_support/mix_tasks_compile_xla_env_preflight.exs", __DIR__)
end

# Eager XLA_TARGET preflight: a project's :compilers list runs AFTER
# dependency compilation, so the in-project preflight compiler alone
# would not catch the EXLA-side failure mode. Calling the validator
# here, at mix.exs top level, catches mix test, mix compile,
# mix deps.compile, and mix deps.update -- all of which evaluate
# mix.exs before touching deps.
#
# When this mix.exs is being evaluated as a transitive dependency
# (our directory sits inside some parent project's deps/), defer
# entirely to that parent project's build configuration.
XlaTargetValidator.validate_root_project!(__DIR__)

defmodule TrinityCoordinator.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :trinity_coordinator,
      version: @version,
      elixir: "~> 1.18",
      description:
        "An Elixir implementation of the TRINITY multi-agent orchestration router for routing language-model calls through a compact hidden-state router.",
      source_url: "https://github.com/nshkrdotcom/trinity_coordinator",
      homepage_url: "https://github.com/nshkrdotcom/trinity_coordinator",
      start_permanent: Mix.env() == :prod,
      package: package(),
      docs: docs(),
      compilers: [:xla_env_preflight] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [
      preferred_envs: [
        dialyzer: :dev,
        credo: :dev
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      # Nx is pinned to GitHub main to pick up
      # https://github.com/elixir-nx/nx/pull/1753 (refactor: better memory
      # footprint for thin svd, polvalente, 2026-05). The thin-SVD path
      # avoids materialising the full m×m U matrix on the Qwen3-0.6B
      # embedder (m = 151,936) regardless of backend, which is what
      # makes the Apple/EMLX export viable without OOM. CUDA also
      # benefits (smaller working set during the embedder factorisation).
      # Pin moves to {:nx, "~> 0.13"} once Nx 0.13 is on Hex.
      {:nx,
       github: "elixir-nx/nx",
       sparse: "nx",
       ref: "6424c8902380380cd7a8c282b0557d653aead018",
       override: true},
      # EXLA pulled from the same Nx repo so the in-tree :nx version
      # matches what EXLA expects (both at 0.12 + thin-SVD PR).
      {:exla,
       github: "elixir-nx/nx",
       sparse: "exla",
       ref: "6424c8902380380cd7a8c282b0557d653aead018",
       override: true},
      {:axon, "~> 0.7"},
      # Bumblebee main (post-v0.7.0). Qwen3 is on Hex via v0.7.0 but
      # main has additional fixes; once Hex 0.8 lands, switch to
      # {:bumblebee, "~> 0.8"} per docs/bumblebee_unpin_playbook.md.
      {:bumblebee,
       github: "elixir-nx/bumblebee",
       ref: "d0774e8ab8c4d5ac60ade95ec8dc9e1f0efd7306",
       override: true},
      # NOTE: EMLX is deliberately NOT listed here. Marking it
      # optional: true would still cause Mix to fetch and start EMLX on
      # any host (incl. Linux/CUDA), whose Metal/MLX NIF cannot load.
      # Apple Silicon users add {:emlx, "~> 0.3"} to their own
      # application's deps; the :emlx runtime profile then resolves to
      # the EMLX.Backend at runtime via Code.ensure_loaded?/1. See
      # guides/runtime_profiles.md.
      # VALIDATION ONLY: Emily 0.4.0 pulled in via the feature branch so
      # this BEAM can run the export + prompt eval on Apple Silicon.
      # Same optional/load-only pattern as EMLX above; do NOT carry this
      # line back to main.
      {:emily, "~> 0.4", only: [:dev, :test]},
      DependencySources.dep(:inference, __DIR__),
      DependencySources.dep(:agent_session_manager, __DIR__),
      DependencySources.dep(:gemini_cli_sdk, __DIR__),
      {:req, "~> 0.5"},
      {:hf_hub, "~> 0.2"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: :trinity_coordinator,
      licenses: ["MIT"],
      maintainers: ["nshkrdotcom"],
      links: %{
        GitHub: "https://github.com/nshkrdotcom/trinity_coordinator"
      },
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "AGENTS.md",
        "assets",
        "build_support",
        "examples",
        "guides",
        "docs/*.md"
      ]
    ]
  end

  defp docs do
    [
      main: "overview",
      source_ref: "v#{@version}",
      source_url: "https://github.com/nshkrdotcom/trinity_coordinator",
      extras: [
        {"README.md", [filename: "overview", title: "Overview"]},
        {"examples/README.md", [filename: "examples", title: "Examples"]},
        "guides/onboarding.md",
        "guides/current_direction.md",
        "guides/system_architecture.md",
        "guides/python_parity_reconstruction.md",
        "guides/stage_checks_and_tolerances.md",
        "guides/artifacts_and_export.md",
        "guides/svd_generation_runbook.md",
        "guides/service_buildout.md",
        "guides/provider_service_hardening.md",
        "guides/operations_qc.md",
        "guides/troubleshooting.md",
        "guides/runtime_profiles.md",
        "guides/artifact_distribution.md",
        "docs/sakana_svd_byte_match_rigor_plan.md",
        "docs/sakana_svd_parity_debug_checklist.md",
        "docs/elixir_svd_decomposition.md",
        "docs/production_qwen_slm_profile.md",
        "docs/coordination_head_variants.md",
        "docs/trace_persistence.md",
        "docs/configurable_provider_pools.md",
        "docs/agent_slot_provider_mapping.md",
        "docs/production_runbook.md",
        "docs/bumblebee_unpin_playbook.md",
        "docs/provider_smoke_tests.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Project: ["README.md", "CHANGELOG.md", "LICENSE"],
        Examples: ["examples/README.md"],
        "Start Here": [
          "guides/onboarding.md",
          "guides/current_direction.md",
          "guides/system_architecture.md"
        ],
        "Parity Guides": [
          "guides/python_parity_reconstruction.md",
          "guides/stage_checks_and_tolerances.md",
          "guides/artifacts_and_export.md",
          "guides/svd_generation_runbook.md"
        ],
        "Service Buildout": [
          "guides/service_buildout.md",
          "guides/provider_service_hardening.md",
          "guides/operations_qc.md",
          "guides/troubleshooting.md",
          "guides/runtime_profiles.md",
          "guides/artifact_distribution.md"
        ],
        "Operator Runbooks": [
          "docs/agent_slot_provider_mapping.md",
          "docs/production_runbook.md",
          "docs/bumblebee_unpin_playbook.md"
        ],
        "Reference Notes": [
          "docs/sakana_svd_byte_match_rigor_plan.md",
          "docs/sakana_svd_parity_debug_checklist.md",
          "docs/elixir_svd_decomposition.md",
          "docs/production_qwen_slm_profile.md",
          "docs/coordination_head_variants.md",
          "docs/trace_persistence.md",
          "docs/configurable_provider_pools.md",
          "docs/provider_smoke_tests.md"
        ]
      ],
      groups_for_modules: [
        Core: [
          TrinityCoordinator,
          TrinityCoordinator.Extractor,
          TrinityCoordinator.CoordinationHead,
          TrinityCoordinator.Orchestrator
        ],
        Runtime: [
          TrinityCoordinator.Runtime,
          TrinityCoordinator.StateManager,
          TrinityCoordinator.RoleInjector,
          TrinityCoordinator.Thinker,
          TrinityCoordinator.Verifier,
          TrinityCoordinator.AgentPool,
          TrinityCoordinator.AgentPool.Adapter,
          TrinityCoordinator.AgentPool.Inference,
          TrinityCoordinator.AgentPool.OpenAI
        ]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
