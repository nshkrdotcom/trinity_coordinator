# TrinityCoordinator

<p align="center">
  <img src="assets/trinity_coordinator.svg" alt="TRINITY Coordinator" width="200" />
</p>

<p align="center">
  <a href="https://opensource.org/licenses/MIT">
    <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-0f172a?style=for-the-badge" />
  </a>
  <a href="https://github.com/nshkrdotcom/trinity_coordinator">
    <img alt="GitHub" src="https://img.shields.io/badge/github-nshkrdotcom%2Ftrinity__coordinator-111827?style=for-the-badge&logo=github" />
  </a>
  <a href="https://huggingface.co/datasets/nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b">
    <img alt="HuggingFace Dataset" src="https://img.shields.io/badge/🤗%20dataset-trinity--coordinator--adapted--qwen3--0.6b-ffd21e?style=for-the-badge" />
  </a>
</p>

`trinity_coordinator` is an Elixir/Nx implementation of a TRINITY-style
local small-model router. A compact `Qwen/Qwen3-0.6B` model (adapted via
Sakana AI's singular-value fine-tuning) reads a transcript, the
runtime extracts a hidden-state vector, a small router head maps it to
agent and role logits, and a configurable provider boundary dispatches
the selected work to a live LLM provider.

This repository contains the Elixir runtime, the parity tooling used to
validate it against the original Python pipeline, and the Mix tasks
needed to onboard a fresh contributor from a clean GitHub clone.

The project is in **active development**. The runtime path
(adapted-Qwen router → role injection → provider boundary → traced
turns) is operational end-to-end with deterministic mock providers and
behind explicit live-provider gates. The eval suite passes 37/37 on
CUDA. See [Current Status](#current-status) for the full picture.

---

## Table Of Contents

- [Quickstart (Standalone Clone)](#quickstart-standalone-clone)
- [Running The Evals](#running-the-evals)
- [How To Get The HuggingFace Bundle](#how-to-get-the-huggingface-bundle)
- [Reproducing The Bundle Yourself](#reproducing-the-bundle-yourself)
- [Current Status](#current-status)
- [Project Direction](#project-direction)
- [System Architecture](#system-architecture)
- [Runtime Profiles (CUDA, Apple Silicon, CPU)](#runtime-profiles)
- [Mix Command Reference](#mix-command-reference)
- [Quality Gates](#quality-gates)
- [Fresh Clone Setup For Sibling-Repo Development](#fresh-clone-setup-for-sibling-repo-development)
- [Project Files](#project-files)
- [Requirements](#requirements)
- [Attribution](#attribution)
- [License](#license)

---

## Quickstart (Standalone Clone)

**This repository is fully standalone.** A clean clone resolves every
sibling dependency through GitHub automatically — no other repositories
need to be cloned next to it. (If you want the local-sibling
multi-repo developer layout, that path is still supported; see
[Fresh Clone Setup For Sibling-Repo Development](#fresh-clone-setup-for-sibling-repo-development).)

```bash
# 1. Clone (HTTPS shown; SSH works too).
git clone https://github.com/nshkrdotcom/trinity_coordinator.git
cd trinity_coordinator

# 2. Fetch deps. The first run pulls Nx, EXLA, Bumblebee, and the three
#    nshkrdotcom sibling repos (agent_session_manager, gemini_cli_sdk,
#    inference) from GitHub. No local checkouts required.
mix deps.get

# 3. Pre-flight: validate XLA_TARGET before anything heavy compiles.
XLA_TARGET=cuda12 mix trinity.env.check
# expect: trinity.env.check: ok / xla_target=cuda12

# 4. Run the fast suite. This is the standing "is everything wired?"
#    check; it excludes live-provider and large-SVD gates by tag.
XLA_TARGET=cuda12 mix test
# expect: 1 doctest, 302 tests, 0 failures (24 excluded)

# 5. Fetch the adapted-Qwen3 bundle (~624 MB, SHA-verified).
#    The bundle is gitignored; this command downloads it from
#    https://huggingface.co/datasets/nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b
#    and writes priv/sakana_trinity/adapted_qwen3_0_6b_layer26/.
mix trinity.artifact.fetch

# 6. Smoke the router end-to-end with a deterministic mock provider.
XLA_TARGET=cuda12 mix trinity.route.demo \
  --mock-provider \
  --trace-out tmp/trinity_route_demo.jsonl
# expect: TRINITY ROUTE DEMO: PASS
```

You are now running the adapted Qwen3 coordinator end-to-end without
spending any provider budget.

> ### XLA_TARGET note
> `XLA_TARGET=cuda12` is the supported CUDA target. The repository's
> XLA preflight rejects unknown targets (notably `cuda13`) before EXLA
> compiles and fails its build with a long stack trace. Set the env
> var inline on each command, or `export` it in your shell. CPU-only
> and Apple Silicon paths do not need this variable — see
> [Runtime Profiles](#runtime-profiles).

---

## Running The Evals

There are five reviewer-facing eval/diagnostic surfaces. All five
run locally against the adapted bundle and make **no external LLM
calls**.

### 1. Prompt eval suite (the main "is the router correct?" check)

The Qwen router prompt eval loads the adapted coordinator once, runs a
suite of fixed prompt/transcript cases, prints the suggested route for
each case, and asserts the expected `agent_id` and `role_id`. It also
enforces per-profile margin floors and (optionally) a snapshot-drift
check against a recorded logits fixture.

```bash
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs
```

```bash
# Strict snapshot + determinism mode (recommended for CI):
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- \
  --snapshot examples/fixtures/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

Expected on CUDA: **37/37 PASS**, no margin-floor violations, no
snapshot drift on any decision-stable field (`agent_id`, `role_id`,
`token_count`, `transcript_hash`).

Useful variants:

```bash
# List the eval cases without running them
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- --list-cases

# Run only a focused subset
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- \
  --case math_direct \
  --case security_review \
  --case final_answer_check

# Diagnostic: print router logits per case
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- --show-logits

# Diagnostic: surface XLA/CUDA native logs inline
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- --debug-native-logs
```

The eval honors `--runtime-profile NAME`. See
[Runtime Profiles](#runtime-profiles) for the menu.

### 2. End-to-end route demo (router + provider boundary + trace)

This proves the orchestrator can drive the adapted router through role
injection, the provider boundary, verifier termination, and JSONL
trace persistence:

```bash
XLA_TARGET=cuda12 mix trinity.route.demo \
  --mock-provider \
  --trace-out tmp/trinity_route_demo.jsonl
```

Expected: a `TRINITY ROUTE DEMO: PASS` line plus a JSONL trace at the
supplied path. The mock-provider lane dispatches Worker first, Verifier
second, and terminates on verifier `ACCEPT`.

`mix trinity.demo --mock-provider` is preserved as a compatibility
alias; new docs and scripts should use `mix trinity.route.demo`.

### 3. Local router inspection (no provider boundary)

The barest path: load the adapted coordinator, format and tokenize a
transcript, and print the route the router would have chosen.

```bash
XLA_TARGET=cuda12 mix run examples/local_coordinator_route.exs -- \
  --prompt "Select a TRINITY role for this reasoning task."
```

Prints the artifact identity, token ids, hidden-vector shape, route
logits, selected agent id, and selected role name.

### 4. Mock orchestration trace (reviewer-friendly readable form)

```bash
XLA_TARGET=cuda12 mix run examples/mock_orchestration_trace.exs -- \
  --prompt "Select a TRINITY role for this reasoning task." \
  --trace-out tmp/examples/mock_orchestration_trace.jsonl
```

Prints mock provider turns with the selected agent id, a trace summary
containing `run_started`, `slm_extracted`, `route_selected`,
`provider_called`, `turn_completed`, `run_completed`, and persists the
JSONL trace.

### 5. Direct adapted-coordinator shape smoke

```bash
XLA_TARGET=cuda12 mix trinity.hitl.adapted
```

Proves the runtime shape contract:

```text
adapted Qwen vector shape: {1, 1024}
adapted route logits shape: {1, 10}
adapted agent logits shape: {7}
adapted role logits shape: {3}
```

The full operator-facing command surface is in
[Mix Command Reference](#mix-command-reference).

---

## How To Get The HuggingFace Bundle

The Sakana-adapted runtime artifact (the 624 MB safetensors bundle the
router needs) lives at:

**<https://huggingface.co/datasets/nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b>**

It is generated output, gitignored, and **not** present in a fresh
clone. The canonical way to install it:

```bash
mix trinity.artifact.fetch
```

This reads `priv/sakana_trinity/artifact_pin.json` (committed) for the
source repo, revision, and per-file SHA-256 manifest, downloads each
file via `hf_hub`, verifies the checksum, and writes the files into
`priv/sakana_trinity/adapted_qwen3_0_6b_layer26/`. Files already
present with the correct SHA-256 are skipped, so repeat invocations
are cheap; the standard HuggingFace cache at `~/.cache/huggingface/`
is honored across clones.

### Options

```bash
# Air-gapped CI (use the local HuggingFace cache only):
HF_HUB_OFFLINE=1 mix trinity.artifact.fetch --offline

# Custom destination (forks, multi-version side-by-side):
mix trinity.artifact.fetch --dest priv/sakana_trinity/my_alt_bundle

# Custom pin file (forks that distribute their own bundle):
mix trinity.artifact.fetch --pin priv/forks/my_pin.json

# Help:
mix trinity.artifact.fetch --help
```

The pin file at `priv/sakana_trinity/artifact_pin.json` records the
HuggingFace `repo_id`, the `revision` tag (currently `v1.0.0`), and a
SHA-256 per file. The fetch task refuses to overwrite a destination
file whose checksum does not match the pin.

For the publisher flow (uploading your own bundle to HuggingFace,
the GitHub-Release fallback for air-gapped environments, and the
versioning conventions) see
[guides/artifact_distribution.md](guides/artifact_distribution.md).

---

## Reproducing The Bundle Yourself

You only need to reproduce the bundle yourself if you intend to (a)
validate the export pipeline end-to-end, (b) run on a non-CUDA
backend such as EMLX on Apple Silicon, or (c) fork the project and
publish your own bundle. For ordinary use, `mix trinity.artifact.fetch`
is faster and gives bit-identical output (the bundle is SHA-pinned).

The export rebuilds the adapted-Qwen3 bundle locally:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted \
  --force \
  --out priv/sakana_trinity/adapted_qwen3_0_6b_layer26
```

On Apple Silicon, choose either `--runtime-profile emlx` (the
canonical Apple lane; requires `{:emlx, "~> 0.3"}` in your parent
app) or `--runtime-profile emily` (the research/validation lane;
requires `{:emily, "~> 0.4", only: [:dev, :test]}`). In both cases,
use `--svd-compute-type f32`:

```bash
mix trinity.sakana.export_adapted \
  --force \
  --runtime-profile emily \
  --svd-compute-type f32 \
  --out tmp/emily_adapted_qwen3_0_6b_layer26
```

This loads Qwen3-0.6B and performs the SVD/SVF work in-process; it is
heavier than the fetch flow but proves the full pipeline. The
underlying details (Python parity reports, stage tolerances,
component bundles, the `:strict-stage-tolerances` gate, large-tensor
chunked replay) live in:

- [guides/artifacts_and_export.md](guides/artifacts_and_export.md) —
  the recommended export/import workflow.
- [guides/svd_generation_runbook.md](guides/svd_generation_runbook.md) —
  step-by-step SVD generation.
- [guides/python_parity_reconstruction.md](guides/python_parity_reconstruction.md) —
  recreating the Python parity process.
- [guides/stage_checks_and_tolerances.md](guides/stage_checks_and_tolerances.md) —
  the correctness standard.

For publishing your own bundle to HuggingFace (including the
`HfHub.Repo.create` → `HfHub.Commit.upload_folder` → tree-verify →
`HfHub.Git.create_tag` flow used to publish the upstream `v1.0.0`
bundle), see
[guides/artifact_distribution.md](guides/artifact_distribution.md) §2.

---

## Current Status

The project is in **active development**. This section is intentionally
verbose; it tells you what is wired, what is verified, and what is
still aspirational.

### Working end-to-end today

- Qwen3-0.6B loads through Bumblebee on EXLA CUDA, EMLX (Apple), or
  the Emily backend (Apple research lane).
- The Sakana router vector is converted to safetensors with a fully
  understood split: first 9216 values are SVF scale offsets; final
  10240 values reshape to a `{10, 1024}` router head.
- The Elixir SVD/SVF code reconstructs adapted tensors.
- Python and Elixir parity scripts emit detailed JSON reports and
  stage tensor bundles.
- Python emits source-oriented stage data for every selected tensor.
- The fast semantic loop reuses Python's `stage.source_f32`, skips
  wrong layouts, and runs the required reconstruction check through
  EXLA without reloading Qwen for every debug run.
- `--strict-stage-tolerances` is the required functional correctness
  gate (and passes today).
- The full Python semantic export imports into canonical
  checkpoint-directory Elixir artifacts with 9 target-verified
  tensors, 9216 singular offsets, and router head shape `{10, 1024}`.
- The adapted coordinator routes a fixed transcript on CUDA with
  hidden `{1, 1024}`, logits `{1, 10}`, agent logits `{7}`, and role
  logits `{3}`.
- Fixed-transcript router trace parity passes for exact transcript
  hash, token ids, router-head hash, and argmax agent/role ids.
  Hidden and logit vectors are compared with declared alignment
  thresholds because the Python reference is run on CPU while Elixir
  runs Qwen through EXLA CUDA.
- The adapted runtime loop routes through fake providers with
  persisted JSONL traces; the safe smoke dispatches Worker first,
  Verifier second, and terminates on verifier `ACCEPT`.
- Thinker suggestions, verifier-before-worker failure, max-turn
  latest-worker termination, and provider failure tracing are
  covered by focused tests.
- `mix trinity.artifact.fetch` downloads the published HuggingFace
  bundle with per-file SHA-256 verification and is the canonical
  fresh-clone onboarding step.
- The prompt-eval suite passes 37/37 on CUDA with the default margin
  floors (`agent: 0.24`, `role: 1.06`) and matches the recorded
  logits snapshot in `examples/fixtures/qwen_router_prompt_eval_logits.json`.

### Parity result snapshot

- Original-submission `svd_weights.pt` regeneration produces the
  current Python safetensors readback hash
  `b4cab13f8a82ccaf49603356e658bc9b77f65b08a69678a7d053a2e4b3197c43`.
- The historical stored hash
  `600be6ab0f5a34325b9857182ccb5fce5971549a0ce8588cdacc992eda54014c`
  is not reproducible from the regenerated `.pt`.
- The bounded layer-26 all-selected replay checks 7 tensors, 70
  stages, and 63 required stages with `failed_required=0`.
- Source tensors, offsets, scaled singular values, and `u_scaled`
  byte-match Python; required f32 reconstruction stages pass explicit
  tolerances.
- Final `bf16` byte equality with Python remains **aspirational** and
  is reported separately, not used as a gate.
- Canonical import validation: `status=complete`,
  `artifact_layout=checkpoint_directory`, `selected_tensor_count=9`,
  `selected_singular_value_count=9216`, `loaded_tensor_count=9`,
  `target_verified_count=9`.
- Adapted coordinator validation: representative fixed-route smoke
  selected `agent_id=4`, `role_id=0`, public role `Worker`.
- Router trace parity passes with exact token ids and head hash,
  exact `agent_id=4` / `role_id=0`, hidden cosine `0.99449`, logits
  cosine `0.99743`.
- Apple Silicon: Emily backend export + 37/37 prompt eval
  independently validated by Paulo Valente (Nx core team) on
  2026-05-21 after merging [Nx PR #1753](https://github.com/elixir-nx/nx/pull/1753)
  (Gram-matrix thin SVD, which our `mix.exs` pins).

Recent non-matching Elixir final hashes have included
`bf089ea0607c93ae69f92bf7b9fcf71dc2a2b53d231cfe307b8cd6f4ef6a85ae`
and `74dc61d765c95e80ca7298b6e97f29a4fd76e2ae4bfb348b2abbffcbc5e0dff8`.
The stage report, not the final Elixir hash alone, is the correctness
verdict.

### Not complete yet

- Final bf16 byte equality with Python (aspirational diagnostic only).
- Live provider smokes remain credential-gated and excluded from the
  default test suite.
- The experiment-reproduction lane (sep-CMA-ES training, benchmark
  harness) has been removed from the active mainline; the project
  consumes the existing Sakana artifacts rather than re-training.

---

## Project Direction

The active lane is:

1. Load the same base `Qwen/Qwen3-0.6B` model used by the Python
   process.
2. Consume the Sakana router vector and SVD/SVF components.
3. Reconstruct adapted Qwen tensors in Elixir/Nx.
4. Prove the Elixir path against Python with stage-level checks and
   explicit tolerances.
5. Materialize reusable adapted artifacts (the bundle on HuggingFace).
6. Run the adapted small local coordinator in front of real
   provider-backed LLM calls.

The earlier experiment-reproduction lane — sep-CMA-ES training,
terminal-reward machinery, benchmark scaffolding — has been removed
from the active codebase. The remaining mainline is the parity-first
artifact path plus the service path on top of it.

The supplemental Python submission has been audited as the executable
specification for runtime semantics. It confirms: imported checkpoint
is `Qwen/Qwen3-0.6B`, layer 26 SVF, seven agents, five coordination
turns, biasless linear `{10, 1024}` head, no-generation router hidden
extraction, role order `solver` / `thinker` / `verifier` (the paper's
`Worker` role maps to the Python code's `solver`).

See [guides/current_direction.md](guides/current_direction.md) for the
detailed milestone breakdown.

---

## System Architecture

```text
transcript -> Extractor.format -> Bumblebee.Text.Qwen3 (EXLA/EMLX/Emily)
            -> hidden state @ position -2
            -> CoordinationHead (imported Sakana router head)
            -> {agent_logits :: {7}, role_logits :: {3}}
            -> RoleInjector
            -> AgentPool.dispatch -> :inference boundary
            -> Trace
```

The intended service path:

1. Format and tokenize the transcript.
2. Run the adapted local Qwen coordinator on the selected backend.
3. Extract the penultimate-token hidden state.
4. Route through the imported Sakana head.
5. Select agent and TRINITY role.
6. Inject the selected role prompt.
7. Dispatch to a configured LLM provider through the shared
   `:inference` boundary (`TrinityCoordinator.AgentPool.Inference`).
8. Persist trace metadata for audit and debugging.

Live provider calls are still **explicitly gated** by `--allow-live`
or by a governed-authority packet. Tests verify routing and
provider-boundary behavior without pretending external LLM calls
happened. See [guides/system_architecture.md](guides/system_architecture.md)
for the per-module breakdown.

---

## Runtime Profiles

`trinity_coordinator` ships six built-in runtime profiles that bundle
backend choice, default coordinator SLM, and validation expectations
into a single keyword. Pass `--runtime-profile NAME` to any
router/demo Mix task or example.

| Profile | Backend | When to use |
| --- | --- | --- |
| `:cuda_exla` *(default)* | `{EXLA.Backend, client: :cuda}` | NVIDIA GPU + CUDA-12 toolchain + Linux. |
| `:host_exla` | `{EXLA.Backend, client: :host}` | EXLA on host CPU (CI sanity checks). |
| `:binary` | `Nx.BinaryBackend` | Pure-Elixir CPU fallback (slow; for unit tests and quick sanity checks). |
| `:emlx` | `{EMLX.Backend, device: :gpu}` | Apple Silicon (production-shaped); add `{:emlx, "~> 0.3"}` to your parent app. |
| `:emily` | `{Emily.Backend, []}` | Apple Silicon (research/validation); add `{:emily, "~> 0.4", only: [:dev, :test]}` to your parent app. Ships empirical margin floors. |
| `:mock_tiny` | tiny synthetic | Tests only; not for real workloads. |
| `{:custom, Mod, opts}` | caller-provided | Any backend without a built-in name. |

Apple-Silicon notes:

- **EMLX is intentionally not listed in `trinity_coordinator`'s
  `mix.exs`.** Marking it `optional: true` would still cause Mix to
  fetch and start EMLX on Linux/CUDA hosts where its Metal/MLX NIF
  cannot load. Apple users add the dep to their own parent
  application's `mix.exs`; the `:emlx` / `:emily` runtime profiles
  resolve the backend at runtime via `Code.ensure_loaded?/1`.
- **Thin SVD memory.** The project pins Nx to a post-v0.12.0 commit
  containing [PR #1753](https://github.com/elixir-nx/nx/pull/1753)
  (Paulo Valente's Gram-matrix thin SVD). This avoids materialising
  the full `m × m` U on the Qwen3-0.6B embedder
  (`m = 151_936`, i.e. ~92 GB U under the old path). Both EMLX and
  EXLA benefit.

See [guides/runtime_profiles.md](guides/runtime_profiles.md) for the
full per-profile reference, including per-profile snapshot fixtures
and margin floors.

---

## Mix Command Reference

### Operator commands

| Command | Use |
| --- | --- |
| `mix trinity.env.check` | Pre-flight validator. Use this first when a new contributor hits CUDA / EXLA build errors. Fails fast with one readable line before EXLA loads. |
| `mix trinity.artifact.fetch` | Download + SHA-verify the adapted-Qwen3 bundle from HuggingFace. Canonical fresh-clone step. |
| `mix trinity.route.demo --mock-provider` | Primary safe runtime demo (router + provider boundary + verifier termination + JSONL trace). `--mock` is an alias. |
| `mix trinity.route.demo --allow-live --provider-pool ...` | Gated live-provider runtime demo. |
| `mix trinity.demo --mock-provider` | Compatibility wrapper around `mix trinity.route.demo --mock-provider`. |
| `mix trinity.hitl.mock_loop` | Terse mock orchestrator loop, pass/fail output. |
| `mix trinity.hitl.adapted` | Adapted Qwen coordinator shape/logit check. |
| `mix trinity.hitl.gpu` | CUDA/EXLA visibility check. |
| `mix trinity.hitl.base_qwen` | Base Qwen CUDA hidden-state check. |
| `mix trinity.hitl.head_route` | Live hidden-state → Sakana-head routing check. |
| `mix trinity.hitl.vector` | Sakana router-vector split check. |
| `mix trinity.gates` | Runs the AGENTS.md quality gate matrix in order. Optional `--include-parity-check`, `--include-hex-build` (advisory), `--summary-out PATH`. |
| `mix trinity.parity.check --python-report ... --elixir-report ...` | Structured wrapper around the Python parity comparator. |

### Artifact and parity commands

| Command | Use |
| --- | --- |
| `mix trinity.sakana.import_python` | Import Python semantic Sakana artifacts into the canonical Elixir layout. |
| `mix trinity.sakana.export_adapted` | Export Sakana-adapted Qwen tensors and router head. |
| `mix trinity.sakana.parity_sample` | Emit Elixir SVD/SVF parity diagnostics. |
| `mix trinity.sakana.router_trace` | Emit and compare fixed-transcript router traces. |
| `mix trinity.sakana.large_tensor_chunks` | Replay embedding and LM-head Sakana stages in row chunks. |

### Examples (runnable, no provider calls)

| Script | Purpose |
| --- | --- |
| `mix run examples/qwen_router_prompt_eval.exs` | Eval-style prompt suite that asserts expected Qwen router agent/role choices (37 cases). |
| `mix run examples/local_coordinator_route.exs --` | Inspect tokenization, hidden vector, logits, selected agent, and selected role. |
| `mix run examples/mock_orchestration_trace.exs --` | Reviewer-friendly orchestration trace with printed mock turns. |

All router/demo commands and all three examples accept
`--runtime-profile NAME` (default `cuda_exla`). All router/demo
commands and all three examples default to the promoted artifact
directory `priv/sakana_trinity/adapted_qwen3_0_6b_layer26`; use
`--artifact-dir ...` only when testing a non-default bundle.

The orchestrator additionally accepts five enforceable budgets
(`:max_wall_time_ms`, `:max_provider_calls`,
`:max_provider_latency_ms`, `:max_verifier_revisions`,
`:max_estimated_cost_usd`). All default to `nil` (unbounded). See
[Production Deployment Runbook §4](docs/production_runbook.md) for the
full contract, error tuple shape, and recommended starting values.

### Live providers

The built-in default live provider pool maps all seven agent ids to
OpenAI `gpt-4o-mini` specs. **The Sakana checkpoint slot labels
(`gpt-5`, `gemini-2.5-pro`, ...) are training metadata, not provider
bindings**; see [docs/agent_slot_provider_mapping.md](docs/agent_slot_provider_mapping.md)
for the full mapping contract.

To use the default pool:

```bash
XLA_TARGET=cuda12 mix trinity.route.demo \
  --allow-live \
  --openai-api-key "$OPENAI_API_KEY" \
  --profile qwen_sakana_adapted \
  --provider-pool default \
  --max-turns 3 \
  --trace-out tmp/trinity_route_demo_openai.jsonl
```

The built-in `gemini_cli_asm` pool routes all seven TRINITY agents
through `Inference.Adapters.ASM`, ASM's SDK lane, and
`gemini_cli_sdk` using `gemini-3.1-flash-lite-preview`. The Gemini
CLI must be installed (or reachable through the SDK's `npx` fallback)
and authenticated in the runtime environment.

Governed runs do **not** read normal provider env as authority. They
must supply an explicit authority packet or the matching governed
route-demo flags:

```bash
XLA_TARGET=cuda12 mix trinity.route.demo \
  --profile qwen_sakana_adapted \
  --governed-authority-ref auth-trinity-1 \
  --governed-workflow-ref workflow-trinity-1 \
  --governed-runtime-ref runtime-trinity-1 \
  --governed-provider-pool-ref pool-trinity-1 \
  --governed-credential-ref cred-trinity-1 \
  --governed-api-key "$TRINITY_DISPOSABLE_PROVIDER_KEY" \
  --governed-provider openai \
  --governed-model gpt-4o-mini \
  --trace-out tmp/trinity_route_demo_governed.jsonl
```

The governed path rejects direct provider-pool and credential options
beside the authority packet. Trace output records provider/model
labels, opaque refs, hashes, and fixed redaction markers — not
materialised secret values.

Without `--mock-provider` (alias `--mock`) or `--allow-live`, live
provider demo mode fails before dispatch.

---

## Quality Gates

The AGENTS.md gate matrix in one command:

```bash
XLA_TARGET=cuda12 mix trinity.gates --summary-out tmp/gates.json
```

Or step-by-step:

```bash
mix format --check-formatted
XLA_TARGET=cuda12 mix compile --warnings-as-errors
XLA_TARGET=cuda12 mix test                              # 1 doctest, 302 tests, 0 failures (24 excluded)
mix credo --strict
mix dialyzer
mix docs --warnings-as-errors
```

`mix hex.build --unpack` is expected to fail today because Nx, EXLA,
and Bumblebee are git-pinned; see
[docs/bumblebee_unpin_playbook.md](docs/bumblebee_unpin_playbook.md)
for the unpin plan.

When parity code changes, also run:

```bash
python3 priv/sakana_trinity/scripts/compare_sakana_parity_reports.py \
  --strict-stage-tolerances \
  tmp/sakana_parity/python_sample_trace.json \
  tmp/sakana_parity/elixir_sample_trace.json
```

For the current parity workflow (Python report + components + Elixir
semantic report + comparator), see
[guides/python_parity_reconstruction.md](guides/python_parity_reconstruction.md)
and [guides/stage_checks_and_tolerances.md](guides/stage_checks_and_tolerances.md).

For service-grade budgets and trace configuration, see
[docs/production_runbook.md](docs/production_runbook.md).

---

## Fresh Clone Setup For Sibling-Repo Development

The standalone clone path is the recommended onboarding shape. **You
do not need this section to use `trinity_coordinator`.**

Read this only if you intend to develop on the upstream sibling repos
(`agent_session_manager`, `gemini_cli_sdk`, `inference`) alongside
`trinity_coordinator` and want Mix to resolve them from your local
checkouts instead of GitHub.

Create the sibling layout:

```text
workspace/
  trinity_coordinator/
  agent_session_manager/
  gemini_cli_sdk/
  cli_subprocess_core/
  execution_plane/
  inference/
```

Clone the repos:

```bash
mkdir trinity-workspace
cd trinity-workspace

git clone git@github.com:nshkrdotcom/trinity_coordinator.git
git clone git@github.com:nshkrdotcom/agent_session_manager.git
git clone git@github.com:nshkrdotcom/gemini_cli_sdk.git
git clone git@github.com:nshkrdotcom/cli_subprocess_core.git
git clone git@github.com:nshkrdotcom/execution_plane.git
git clone git@github.com:nshkrdotcom/inference.git

cd trinity_coordinator
mix deps.get
```

The committed internal dependency tuples are ordinary Hex requirements. Plain
Mix therefore sees normal package declarations and no repository-local source
policy. For multi-repository development, run Mix through Mix Workspace Ops;
MWO loads a process-scoped bootstrap, derives eligible local/Git/Hex
coordinates from Portfolio Registry, and applies operator source preferences
outside this repository.

How the sibling repos depend on each other:

- Under a managed MWO run, `trinity_coordinator` can consume the checked-out
  `agent_session_manager`, `gemini_cli_sdk`, and `inference` projects.
- `agent_session_manager` and `gemini_cli_sdk` consume
  `../cli_subprocess_core` when it is present.
- `cli_subprocess_core` consumes packages inside `../execution_plane`
  when that workspace is present.

Standalone runs use the committed package requirements. Until every internal
package is published, the checked-out stack should be run through MWO.

---

## Project Files

- [License](LICENSE)
- [Changelog](CHANGELOG.md)
- [Onboarding](guides/onboarding.md)
- [Current Direction](guides/current_direction.md)
- [System Architecture](guides/system_architecture.md)
- [Recreating The Python Parity Process](guides/python_parity_reconstruction.md)
- [Stage Checks And Tolerances](guides/stage_checks_and_tolerances.md)
- [Sakana Artifacts And Export](guides/artifacts_and_export.md)
- [SVD Generation Runbook](guides/svd_generation_runbook.md)
- [Runtime Profiles](guides/runtime_profiles.md)
- [Artifact Distribution](guides/artifact_distribution.md)
- [Service Buildout Plan](guides/service_buildout.md)
- [Provider Service Hardening](guides/provider_service_hardening.md)
- [Operations And Quality Gates](guides/operations_qc.md)
- [Troubleshooting](guides/troubleshooting.md)
- [Production Deployment Runbook](docs/production_runbook.md)
- [Bumblebee Unpin Playbook](docs/bumblebee_unpin_playbook.md)
- [Agent Slot ↔ Provider Mapping](docs/agent_slot_provider_mapping.md)
- [Examples](examples/README.md)

Additional technical reference notes are included in HexDocs under
**Reference Notes**.

Private implementation notes may exist under `docs/priv/` in internal
workspaces, but they are not required for fresh-clone onboarding.

---

## Requirements

- Elixir `~> 1.18`.
- One of: NVIDIA driver visible to `nvidia-smi` with
  `XLA_TARGET=cuda12` (canonical lane), an Apple Silicon machine with
  `{:emlx, "~> 0.3"}` in the parent app's `mix.exs` (canonical Apple
  lane), or a CPU-only host (for `:binary` / `:host_exla` profile
  sanity checks; expect order-of-magnitude slower routing).
- Internet access for the first Hugging Face download of
  `Qwen/Qwen3-0.6B` (Bumblebee caches it under `~/.cache/huggingface/`)
  and for `mix trinity.artifact.fetch`.
- The generated adapted artifact directory at
  `priv/sakana_trinity/adapted_qwen3_0_6b_layer26/` (installed via
  `mix trinity.artifact.fetch` on first use).
- Python with PyTorch, Transformers, and safetensors **only** when
  rebuilding artifacts or running parity scripts.
- Gemini CLI authentication **only** when running live
  `gemini_cli_asm` provider demos.

Resolved core dependency lane:

- `nx 0.12.0` (git-pinned to `elixir-nx/nx@6424c89` for
  [PR #1753 thin SVD memory fix](https://github.com/elixir-nx/nx/pull/1753))
- `exla 0.12.0` (git-pinned to the same commit)
- `axon 0.7.0` (Hex)
- `bumblebee` (git-pinned to `elixir-nx/bumblebee@d0774e8a`,
  post-v0.7.0 main; see
  [docs/bumblebee_unpin_playbook.md](docs/bumblebee_unpin_playbook.md))
- `hf_hub ~> 0.3` (Hex)
- `req ~> 0.5` (Hex)

---

## Attribution

This repository is a research implementation inspired by *TRINITY: An
Evolved LLM Coordinator*.[1] The paper motivates the hidden-state
router, the Thinker/Worker/Verifier role split, the lightweight
coordination head, and the preference for compact local coordination.

The Apple Silicon path was independently validated by
[ausimian (Emily backend, PR #85)](https://github.com/ausimian/emily/pull/85)
and end-to-end by Paulo Valente (Nx core team) on 2026-05-21 after his
[Nx PR #1753](https://github.com/elixir-nx/nx/pull/1753) (better
memory footprint for thin SVD) landed. Both are pinned in this
project's dependency lane.

This package does not claim to reproduce the paper's reported scores.
The active focus is a robust, inspectable Elixir implementation of the
Qwen/Sakana coordinator path.

## References

[1] Jinglue Xu, Qi Sun, Peter Schwendeman, Stefan Nielsen, Edoardo
Cetin, and Yujin Tang. *TRINITY: An Evolved LLM Coordinator*.
arXiv:2512.04695, 2026. <https://arxiv.org/abs/2512.04695>

## License

This project is released under the MIT License.
