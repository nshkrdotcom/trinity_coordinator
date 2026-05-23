# Changelog

## 2026-05-23

### Changed

- Retired the repository to a compatibility shim for
  `trinity_framework` / `trinity_ops`.
- Dropped direct runtime/model/provider dependencies from this package.
- Replaced the public facade and `mix trinity.*` task surface with deprecated
  delegators for one deprecation window.
- Refreshed the inherited Nx lane to Hex `nx 0.12.1` / `exla 0.12.0`; the
  temporary post-0.12.0 Nx GitHub pin is no longer required.

## 2026-05-21

### Highlights

This release ships profile-driven backend selection (the foundation for
Apple Silicon / EMLX support), the canonical `mix trinity.artifact.fetch`
onboarding command, and a dep-stack bump that picks up
[Nx PR #1753](https://github.com/elixir-nx/nx/pull/1753) (better memory
footprint for thin SVD; the Apple-side blocker is now fixed upstream).

### Added

- `mix trinity.artifact.fetch` task and `TrinityCoordinator.ArtifactFetch`
  module. Downloads the adapted-Qwen3 bundle from a HuggingFace dataset
  repo with per-file SHA-256 verification. The pin file at
  `priv/sakana_trinity/artifact_pin.json` is committed to the repo so a
  fresh clone knows what to fetch before touching the network.
- `TrinityCoordinator.RuntimeProfile.put_default_backend!/1` — single
  bottleneck through which all backend bootstrapping flows. Profiles
  whose backend module is not loaded raise a single informative error
  naming the missing dep.
- `TrinityCoordinator.RuntimeProfile.accepts_backend_label?/2` — used
  by the exporter's per-tensor validation. Generalises the previous
  CUDA-only check.
- Real `:emlx` runtime profile. `nx_backend == {EMLX.Backend, device: :gpu}`.
  Resolves to a working profile struct; users on Apple Silicon add
  `{:emlx, "~> 0.3"}` to their parent app and pass
  `--runtime-profile emlx` to the relevant Mix tasks / examples.
- `--runtime-profile NAME` flag on `mix trinity.sakana.export_adapted`,
  `mix trinity.sakana.router_trace`, and
  `examples/qwen_router_prompt_eval.exs`. Default `cuda_exla` for
  back-compat.
- New guides: `guides/runtime_profiles.md`, `guides/artifact_distribution.md`.
- Three new troubleshooting sections in `guides/troubleshooting.md`:
  artifact-fetch failure modes, EMLX dep missing, EMLX OOM on the
  embedder SVD (with the two upstream fixes).
- `hf_hub ~> 0.2` dep (already on Hex).

### Changed

- **Dep stack bump.** `nx` and `exla` temporarily pinned to the upstream Nx
  repository after v0.12.0 to carry PR #1753's thin-SVD memory fix.
  `bumblebee` pinned to
  `elixir-nx/bumblebee@d0774e8ab8c4d5ac60ade95ec8dc9e1f0efd7306`
  (post-v0.7.0 main).
- **`xla` 0.10.x** is now the bundled version (was 0.9.x). `cuda13` is
  newly accepted by the XLA preflight; `cuda12` remains the recommended
  default.
- `SLMProfile.qwen_coordinator/0` and `SLMProfile.qwen_sakana_adapted/0`
  `load_options` no longer bake in `backend: {EXLA.Backend, client: :cuda}`.
  They carry only `type: :bf16`; `Coordinator.load/1` injects the
  runtime profile's backend at load time.
- `Sakana.Exporter.ensure_cuda_backend/2` →
  `ensure_export_backend/3`. Threads runtime profile through
  `export_tensor/5` so per-tensor backend validation matches the profile
  under which the export ran.
- `Sakana.Exporter.load_profile/1` → `load_profile/2`. Uses
  `RuntimeProfile.put_default_backend!/1` instead of CUDA-hard-coded
  `Runtime.put_cuda_backend!/0`.
- README `Model And Artifact Setup` rewritten to lead with
  `mix trinity.artifact.fetch` instead of "use a blessed artifact bundle".

### Fixed

- Apple Silicon export OOM on the Qwen3-0.6B embedder
  (151,936 × 1024 → (92 GB U). Upstream fix in Nx PR
  #1753 (now in our pin). Validated end-to-end on Apple by Paulo
  Valente (polvalente, Nx core team) on 2026-05-21: full export +
  37/37 prompt eval pass.

### Notes

- `{:emlx, "~> 0.3"}` is deliberately NOT in `mix.exs`. Marking it
  `optional: true` would still fetch and start it on Linux/CUDA hosts
  where its Metal/MLX NIF cannot load. Apple users add the dep to
  their parent app; the `:emlx` runtime profile resolves the backend
  at runtime via `Code.ensure_loaded?/1`.

## 2026-05-21

### Added
- `XlaTargetValidator` — shared `XLA_TARGET` validator at
  `build_support/xla_target_validator.exs`. Mirrors the bundled
  `xla 0.9.x` acceptance list exactly (`cpu`, `cuda`, `cuda12`,
  `rocm`, `tpu`) and raises a single readable `Mix.Error` for any
  other value, naming `cuda12` as the recommended remediation and
  pointing at `guides/troubleshooting.md`.
- `Mix.Tasks.Compile.XlaEnvPreflight` — Mix compiler that delegates
  to `XlaTargetValidator.validate_root_project!/1`. Registered in `mix.exs`
  via `compilers: [:xla_env_preflight] ++ Mix.compilers()`. The compiler
  uses the same under-`deps/` skip as the eager top-level check, so parent
  projects that consume `trinity_coordinator` as a dependency are not forced
  through this root project's XLA target policy.
- Top-level eager `XlaTargetValidator.validate_root_project!/1` call in
  `mix.exs`, gated by the validator's under-`deps/` check. Catches the
  `XLA_TARGET=cuda13` failure mode for `mix test`,
  `mix deps.compile`, `mix deps.update`, and other tasks that
  evaluate `mix.exs` before touching dependency compilation.
  Without this gate, the `:compilers` list alone would not help
  because the project's compilers run *after* dependency
  compilation, and the EXLA-side `RuntimeError` would still appear
  first.
- 15 tests in `test/build_support/xla_target_validator_test.exs`
  covering: unset, empty, every accepted target, `cuda13`,
  arbitrary garbage, case mismatch, trailing whitespace, helper
  accessors, root-project validation, and the transitive dependency
  skip path.

### Changed
- `guides/troubleshooting.md` — `XLA_TARGET=cuda13` section now
  reflects that the project surfaces this automatically; the
  `mix trinity.env.check` recipe is preserved as a manual
  alternative.

### Bug fix surface
- Replaces the EXLA-side `RuntimeError` stacktrace from
  `deps/exla/mix.exs:116` with a single readable `** (Mix.Error)`
  line that names the bad value, the accepted set, and the
  remediation. Verified against `mix compile`, `mix test`, and
  `mix deps.compile exla --force`, all of which now fail at
  `mix.exs:29` instead of inside the EXLA compile step.

## 2026-05-20 (Phase 11 follow-up)

### Added
- Enforceable `:max_provider_latency_ms` budget. A single dispatch that
  exceeds the limit aborts the loop with
  `{:error, {:budget_exceeded, :provider_latency_ms, %{limit_ms,
  observed_ms, checkpoint, turn}}}` at the `:after_dispatch` checkpoint.
- Enforceable `:max_verifier_revisions` budget. Each Verifier dispatch
  whose status is not `:accepted` increments the counter; the (N+1)th
  rejection aborts at `:after_verifier_revision`.
- Optional `:cost_estimator_fn` orchestrator option. When supplied
  alongside `:max_estimated_cost_usd`, the loop totals the per-dispatch
  cost and aborts at `:after_dispatch` once the cumulative cost exceeds
  the limit. Without the function, setting `:max_estimated_cost_usd`
  emits a one-shot `Logger.warning/1` per `run_loop/4` call.
- `TrinityCoordinator.RouteDecision.to_trace_map/1` — JSON-safe map
  projection of the struct, used to attach a `:route_decision` field to
  every `:turn_completed` trace event.
- `docs/production_runbook.md` — 10-section operator runbook covering
  pre-deploy checks, artifact installation, provider pools, budget
  contract, trace persistence, failure-mode triage, secrets handling,
  in-place artifact updates, observability, and rollback.
- `docs/bumblebee_unpin_playbook.md` — 5-section, 15-minute runbook for
  unpinning `:bumblebee` when a Qwen3-supporting Hex release lands; flips
  the `mix trinity.gates` `hex_build` step from advisory back to
  blocking.
- Default margin floors on `examples/qwen_router_prompt_eval.exs`:
  `--min-agent-margin 0.24`, `--min-role-margin 1.06`. Calibrated to 80%
  of empirical worst-case margins (`agent_margin 0.301` on
  `unicode_emoji`; `role_margin 1.335` on `root_cause`) observed on
  2026-05-20 in the bundled logits fixture. Pass `0.0` to disable.

### Changed
- `:max_provider_calls` semantics tightened to exact: a value of N
  allows exactly N dispatches; the (N+1)th attempt aborts at
  `:before_dispatch` with `observed = N+1`. Same `> limit` change
  applied to `:max_verifier_revisions`.
- `Orchestrator` moduledoc: full budget contract is now in-band; cross
  references `docs/production_runbook.md` for service-grade defaults.
- `mix.exs`: added an inline comment cross-referencing
  `docs/bumblebee_unpin_playbook.md` next to the Bumblebee git pin.
- `README.md`: "Project Files" now links to the production runbook,
  Bumblebee unpin playbook, and agent-slot/provider mapping. The
  "Running The Router" budgets paragraph points operators at the
  runbook for the full contract.
- `guides/operations_qc.md`: expected test count updated to
  `1 doctest, 214 tests, 0 failures (24 excluded)`; added pointers to
  `mix trinity.gates`, `mix trinity.env.check`, `mix trinity.parity.check`,
  and the production runbook §4.
- `guides/onboarding.md`: test count refreshed; added the
  `mix trinity.env.check` pre-flight step.
- `guides/provider_service_hardening.md`: §5 cross-links the production
  runbook §4 for service-operation budgets.
- `guides/troubleshooting.md`: new section "XLA_TARGET=cuda13 is
  rejected at compile time".
- `~/jb/docs/20260519/sakana/appendix/H_post_execution_verification_and_handoff.md`:
  §H.3.1 marked resolved (`HEAD == origin/main`); new §H.7 points at the
  Phase 11 follow-up docset at `~/jb/docs/20260520/sakana/`.

### Internal
- Test count: 205 → 214 (+9 net new tests across budget, RouteDecision,
  and trace-shape coverage).
- All AGENTS.md gates green: format, compile WAE, test, credo --strict,
  dialyzer 0 errors, docs WAE.
- `mix trinity.gates --include-hex-build` exits 0 with the documented
  `hex_build_advisory: fail` (per Appendix G §G.2.6); blocking resumes
  after the unpin playbook lands.
- 37/37 PASS on `examples/qwen_router_prompt_eval.exs` with default
  margin floors AND `--snapshot` AND `--determinism-runs 2`.

See `~/jb/docs/20260520/sakana/06_execution_log.md` for the per-item
phase-11 closure record. See
`~/jb/docs/20260520/sakana/01_phase_11_budget_honesty_and_route_decision.md`
for the original Phase 11 checklist.

## 2026-05-20

### Added
- `mix trinity.env.check` — pre-flight Mix task that validates `XLA_TARGET`
  against the bundled `xla` dependency's accepted values (and optionally that
  `--artifact-dir` exists with a `manifest.json`). Fails fast with a single
  readable `Mix.raise/1` line before EXLA loads.
- `mix trinity.gates` — one-command runner for the AGENTS.md quality gate
  matrix (format, compile WAE, test, credo --strict, dialyzer, docs WAE).
  Optional `--include-parity-check`, `--include-hex-build` (advisory),
  `--skip-dialyzer`, `--skip-docs`, `--fast`, `--summary-out PATH`. Writes a
  schema_version 1 JSON summary.
- `mix trinity.parity.check` — first-class wrapper around the Python parity
  comparator. Validates input files exist before shelling out, captures a
  structured JSON summary.
- `TrinityCoordinator.MixHelpers` — shared `load_coordinator!/1` and
  `runtime_profile_atom!/1` helpers. All Mix tasks that load the coordinator
  now surface failures as readable `** (Mix)` messages instead of
  `MatchError` stacktraces.
- `TrinityCoordinator.RuntimeProfile` — declarative struct that names the
  backend lane (`:cuda_exla`, `:host_exla`, `:binary`, `:mock_tiny`, `:emlx`,
  plus `{:custom, backend, opts}` and struct passthrough). `Coordinator.load/1`
  now accepts `:runtime_profile`; legacy `:backend` and `:require_cuda`
  options continue to work and override the profile when supplied.
- `TrinityCoordinator.Sakana.Head.assert_shape_invariants!/2` — load-time
  guard that compares the manifest's `router_head_shape` (today `[10, 1024]`)
  against the dimensions parsed from the loaded weights. The next checkpoint
  refresh with a different agent count, role count, or hidden size now fails
  loud at load time.
- `TrinityCoordinator.RouteDecision` struct + `from_route/3` — public,
  structured representation of one router decision with computed top-2
  margins, selection modes, and an optional artifact identity. Backward
  compatible with the informal route map.
- Orchestrator cost/time budgets:
  `:max_wall_time_ms`, `:max_provider_calls`, `:max_verifier_revisions`,
  `:max_estimated_cost_usd`, `:max_provider_latency_ms` (recorded; not yet
  enforced). All default to `nil` (no budget). Budget-exceeded returns
  `{:error, {:budget_exceeded, kind, details}}` and emits a trace
  `run_failed` event.
- Tiny synthetic Sakana artifact fixture at `test/fixtures/sakana_tiny_artifact/`
  (1.4 KB). Exercises the canonical manifest + router-head + routing-state
  + shape-invariant code path on CPU without Bumblebee or Qwen. Refreshable
  via `TrinityCoordinator.Test.SakanaTinyArtifactFactory.refresh!/0`.
- 37-case prompt eval fixture at `examples/fixtures/qwen_router_prompt_eval_cases.json`
  (up from 12 hardcoded cases). Decision-stable per-case snapshot at
  `examples/fixtures/qwen_router_prompt_eval_logits.json` (`agent_id`,
  `role_id`, `token_count`, `transcript_hash`, `route_hash`, plus diagnostic
  raw logits and top-2 margins).
- `--snapshot PATH`, `--snapshot-out PATH`, `--determinism-runs N`,
  `--min-agent-margin`, `--min-role-margin` flags on the prompt eval script.
- `--mock-provider` alias on `mix trinity.route.demo` (preserving `--mock`
  as a compatibility alias). Live-gate failure message mentions both
  spellings.
- `--runtime-profile NAME` flag on `mix trinity.route.demo`,
  `trinity.hitl.adapted`, `trinity.hitl.mock_loop`, and
  `trinity.sakana.router_trace`. Accepts the built-in profile names; safely
  rejects unknown names via an allowlist helper (no dynamic atom creation).
- `docs/agent_slot_provider_mapping.md` — canonical reference for the
  Sakana-label-vs-provider-pool boundary. Cross-linked from README.
- Five `:default` / `:mock` / `:gemini_cli_asm` provider-pool safety
  assertions in `test/trinity_coordinator/provider_pool_test.exs`. In
  particular, the `:default` pool's slot 0 is asserted to NOT bind to
  `gpt-5`, preventing accidental Sakana-label → live-model coupling.
- `.github/workflows/ci.yml` — CPU CI (`mix trinity.gates --skip-dialyzer`).
- `.github/workflows/cuda.yml` — manual `workflow_dispatch` for the
  maintainer's self-hosted CUDA runner; runs the full 37-case eval +
  full gates + advisory hex.build.

### Changed
- `priv/sakana_trinity/adapted_qwen3_0_6b_layer26/manifest.json`:
  `python_manifest_path` and `reference_manifest_path` are now repo-relative
  (durable fix via `TrinityCoordinator.Sakana.PythonImporter.provenance_path/2`).
  Router head sha256 unchanged.
- `mix.exs`: adds `elixirc_paths/1` so `test/support/` is only compiled in
  `:test`.
- README "Fresh Clone Setup": clarifies the sibling-repo list is advisory
  for multi-repo development; `mix deps.get` works without them via the
  GitHub fallback in `build_support/dependency_sources.config.exs`.
- README "Live provider pool": clarifies that Sakana checkpoint labels are
  training metadata, not provider bindings. Links to
  `docs/agent_slot_provider_mapping.md`.
- Native CUDA error message in `TrinityCoordinator.Runtime.require_cuda!/0`
  now explains that `XLA_TARGET` is build-time, not just runtime-time, and
  prints the exact rebuild incantation.

### Internal
- Test count: 140 → 205 (+65 net new tests across 10 new test files).
- `mix trinity.gates` matrix verified green on CUDA host; `hex_build_advisory`
  fails per `appendix/G_post_checklist_review_and_amendments.md` §G.2.6
  (Bumblebee git pin); becomes blocking again once Bumblebee is unpinned.
- 37/37 PASS on `examples/qwen_router_prompt_eval.exs` with both
  `--snapshot` and `--determinism-runs 2` on the canonical CUDA artifact.

See `~/jb/docs/20260519/sakana/` for the full analysis docset, doc 21 for
the 10-phase execution checklist, and `tmp/phase_closure/final_milestone.md`
for the per-phase merge log.

## 2026-04-28

- Reframed the public documentation around the active Qwen/Sakana parity and
  service-foundation direction.
- Added the `guides/` documentation set covering onboarding, direction,
  architecture, Python parity reconstruction, stage tolerances, artifacts,
  service buildout, operations, and troubleshooting.
- Updated ExDoc configuration so README, guides, reference notes, changelog, and
  license render as a structured HexDocs menu.
- Clarified that the old experiment-reproduction lane is shelved and planned
  for later removal or archival after the parity/service path is stable.
- Kept final Python byte matching as an aspirational target while documenting
  `--strict-stage-tolerances` as the required functional correctness gate.
- Added a faster Sakana sample parity loop with Python stage-source reuse,
  preferred-layout-only replay, and device-only semantic reconstruction.
- Guarded all-selected Python component debug export so it requires
  `svd_weights.pt` unless full recomputation is explicitly requested.
- Added Elixir stage checks for `stage.u_scaled` and
  `stage.matmul_pre_norm`, preserving the functional tolerance gate while
  continuing to report final `bf16` byte mismatches separately.
- Normalized runtime role metadata to imported checkpoint order:
  raw Python `solver` is public `Worker`, then `Thinker`, then `Verifier`.
- Added the shared `:inference` dependency and routed hosted, GeminiEx, and
  Agent Session Manager provider specs through a generic
  `TrinityCoordinator.AgentPool.Inference` consumer adapter.

## 2026-04-21

- P1: Added a repo-local Gemma server helper and optional SSoT JSON schema for
  local OpenAI-compatible experiments; Codex/Gemini remains the evidence path.
- P2: Made `distance: embedding` fail loudly on backend errors, retained
  degraded semantic-descriptor status in traces, and exposed centroid IDs under
  `run.centroids`.
- P3: Hardened SSoT anti-collapse coverage with boundary tests for chunk
  thresholds and monotonic verified mapping coverage.
- P4: Centralized the evidence gate in `AntiAgents.Statistics.evidence_hypothesis/3`
  so benchmark and calibration both require positive CI, sign-test support, and
  non-saturated calibration status.
- P5: Added `mix anti_agents.ablate` for offline descriptor ablation against
  reference traces with `provider_calls: 0`.
- P6: Ran the allowed one-field live smoke with Codex inference and
  `gemini_ex` embeddings; recorded explicit Gemini auth and descriptor
  provenance.
- P7: Prepared and dry-run validated the 156-call live calibration command;
  deferred execution to the human operator under the live-run budget policy.
- P8: Dry-run validated the evidence profile at 756 planned LLM calls and
  `<= 756` expected single-view embedding calls; documented human-run evidence
  and ablation commands.
- P9: Updated README, validation, and architecture docs to distinguish pilot,
  diagnostic smoke, deferred evidence, and descriptor-ablation claims.

## 2026-04-20

- W1: Added matched-budget hypothesis testing, bootstrap confidence intervals,
  12-field benchmark fixture, and `mix anti_agents.benchmark`.
- W2: Added archive-feedback rounds with per-round summaries and stagnation
  reporting.
- W3: Added pluggable distance backends for Jaccard, embedding, and judge paths;
  descriptor cells now include `semantic_cluster`.
- W4: Reframed public documentation around semantic-space frontier search and
  removed unsupported latent-space claims.
- W5: Added baseline artifact retry, permanent-loss accounting, and adjusted
  novelty reporting.
- W7: Added verification fixtures, trace schema, scoring-weight invariant tests,
  `mix verify`, and contributor verification docs.
- C1: Replaced the semantic-cluster stub with embedding-backed centroid
  assignment and traceable centroid IDs.
- C2: Changed the benchmark headline statistic to per-field mean-delta
  bootstrap plus one-sided sign test; retained pooled cells as diagnostics.
- C3: Added `--diagnostic` and blocked low-budget benchmark runs from being
  reported as evidence.
- C4: Added frontier temperature sweeps, matched-baseline temperature parity,
  and ignored seed/assembly heat warnings.
- C5: Added `priv/profiles/evidence.json` and benchmark `--profile` loading
  with recorded overrides.
- C6: Split matched-baseline retry/loss accounting from reachable-baseline
  accounting.
- C7: Changed archive feedback to positively target underfilled descriptor
  cells.
- C8: Added descriptor saturation metrics and benchmark calibration status.
- C9: Added `mix anti_agents.calibrate --stubbed` as the QC positive control.
- C10: Reserved README evidence reporting until an embedding-backed,
  expensive-gated evidence run is deliberately executed.
- C11: Added `gemini_ex` 0.13.0 as the production embedding provider for
  evidence runs, using `gemini-embedding-001` batch embeddings through the
  existing embedding-client seam.
