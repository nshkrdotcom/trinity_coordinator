# Runtime Profiles

`trinity_coordinator` ships with a small set of named **runtime
profiles** that bundle a backend choice, a default coordinator SLM,
and a set of validation expectations into one keyword. Profiles are
defined in `TrinityCoordinator.RuntimeProfile` and resolved by name
or struct.

A profile answers three questions in one place:

1. **Which Nx backend?** (`:nx_backend` — e.g. `{EXLA.Backend, client: :cuda}`,
   `{EMLX.Backend, device: :gpu}`, `Nx.BinaryBackend`.)
2. **Is CUDA required?** (`:require_cuda?` — gates `Runtime.put_cuda_backend!/0`
   so callers can opt out cleanly.)
3. **What is the default SLM coordinator profile?** (`:default_slm_profile`.)

Plus metadata for downstream callers (`:export_svd?`, `:large_svd?`,
`:qwen_runtime?`, `:artifact_runtime?`) and operator-facing
`:notes` / `:warnings`.

## The Built-In Profiles

### `:cuda_exla` (default)

Linux/CUDA happy path. Used for everything the project does today.

- `nx_backend: {EXLA.Backend, client: :cuda}`
- `require_cuda?: true`
- `default_slm_profile: :qwen_coordinator`

Requires `XLA_TARGET=cuda12` and a working EXLA CUDA stack.

### `:rocm_exla`

Support for AMD environments.  Build is touch, but it can work.

- `nx_backend: {EXLA.Backend, client: rocm}`
- `require_cuda?: false`
- `default_slm_profile: :qwen_coordinator`

Requires `XLA_TARGET=rocm` and a working ROCm build environment.

### `:emlx`

Apple Silicon (MLX-backed) lane. Brings up `EMLX.Backend, device: :gpu`
when the optional `:emlx` dep is present.

- `nx_backend: {EMLX.Backend, device: :gpu}`
- `require_cuda?: false`
- `default_slm_profile: :qwen_coordinator`

EMLX is an optional dependency. To use this profile, add it to your
parent application's `mix.exs`:

```elixir
{:emlx, "~> 0.3"}
```

Then:

```bash
mix deps.get
mix run examples/qwen_router_prompt_eval.exs --runtime-profile emlx \
  --snapshot examples/fixtures/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

#### EMLX-specific Caveats

- **Thin SVD memory footprint.** Nx main as of commit `6424c89` (Paulo
  Valente, [PR #1753](https://github.com/elixir-nx/nx/pull/1753))
  refactored `Nx.LinAlg.svd/2` with `full_matrices?: false` so it does
  not materialise the full `m × m` U on the Qwen3-0.6B embedder
  (where `m = 151_936`, i.e. (92 GB of U under the old path).
  This fix is in the Nx version that `trinity_coordinator` pins to.
  Both EMLX and EXLA benefit from this change.
- **`--svd-compute-type f32`.** Recommended on Apple. The thin-SVD
  path uses an `eigh` decomposition under the hood; doing that work
  in f32 keeps the small-σ tail precise.
- **Backend label.** When the exporter validates per-tensor backend
  during the SVD reconstruction step, it accepts the
  `"EMLX.Backend"` label as well as `"EXLA.Backend<cuda:"`. No code
  changes needed for the user.
- **Bumblebee Qwen3 support.** Bumblebee is git-pinned to a Qwen3-
  supporting commit (post-v0.7.0 main). EMLXAxon
  ([github.com/elixir-nx/emlx](https://github.com/elixir-nx/emlx)) has
  independently validated Qwen3-0.6B loading through the EMLX backend.
  Paulo Valente confirmed on 2026-05-21 that running with the bare
  EMLX backend (no `EMLXAxon.rewrite/1`) successfully exports and
  passes 37/37 on the prompt eval.
- **bf16 round-trip.** The bundle is bf16 safetensors. EMLX accepts
  bf16 natively (`{:bf, 16}` ↔ MLX `bfloat16`). No quantisation or
  type cast required.

### `:emily`

Apple Silicon (MLX-backed) **research/validation** lane via the
[Emily](https://hex.pm/packages/emily) backend. Same Apple-shaped flags
as `:emlx` but routes to `Emily.Backend` and ships
`ausimian`'s empirically-derived per-profile margin floors
(`agent: 0.33`, `role: 0.82`) so a clean Emily run does **not** mark
the `escalate_to_human` case as a near-miss against the canonical CUDA
role floor of `1.06`.

- `nx_backend: {Emily.Backend, []}`
- `require_cuda?: false`
- `default_slm_profile: :qwen_coordinator`
- `default_min_agent_margin: 0.33`
- `default_min_role_margin: 0.82`

Emily is an optional dependency. To use this profile, add it to your
**parent** application's `mix.exs` — do NOT add it to
`trinity_coordinator`'s own `mix.exs`:

```elixir
{:emily, "~> 0.4", only: [:dev, :test]}
```

Then:

```bash
mix deps.get

XLA_TARGET=cuda12 mix trinity.sakana.export_adapted \
  --force \
  --svd-compute-type f32 \
  --runtime-profile emily \
  --out tmp/emily_adapted_qwen3_0_6b_layer26

mix run examples/qwen_router_prompt_eval.exs \
  --runtime-profile emily \
  --artifact-dir tmp/emily_adapted_qwen3_0_6b_layer26 \
  --determinism-runs 2
```

Note: the `--min-agent-margin` / `--min-role-margin` flags are no
longer required — the `:emily` profile seeds its own floors via
`RuntimeProfile.default_margins/1` (see "Per-Profile Snapshot Fixtures
And Margin Floors" below). Pass them explicitly only if you want to
override the seeded values for a one-off run.

The canonical Apple lane for production-shaped workloads remains
`:emlx`; `:emily` is the research/validation lane. They are both
Apple-shaped and they both pass the prompt eval — pick `:emily` when
you want Paulo Valente's thin-SVD path under MLX, and `:emlx` when you
want the EMLX runtime that EMLXAxon was built against.

#### Why two Apple profiles?

`:emlx` and `:emily` are both Apple-Silicon (MLX-family) but differ at
the Nx-backend layer:

- `:emlx` → `EMLX.Backend, device: :gpu`. Canonical Apple lane;
  EMLXAxon has independently validated Qwen3-0.6B through it.
- `:emily` → `Emily.Backend`. Research/validation backend; ships the
  `Gram`-matrix thin-SVD path that adapted on top of Nx PR #1753
  ("better memory footprint for thin SVD") and was the lane on which
  the Apple-side end-to-end run was first proven (ausimian, 2026-05-21,
  37/37 decisions match CUDA; one role-margin near-miss absorbed by
  the per-profile floor seeded above).

Both lanes pass the same prompt-eval suite and are decision-stable
against the CUDA snapshot. `route_hash` will drift on every case for
both lanes — that's expected on a different kernel stack and is exactly
what the per-profile snapshot fixture lane below is designed for.

### `:binary`

Pure-Elixir CPU fallback. Useful for unit tests and for quick
sanity-checks on machines without any GPU.

- `nx_backend: Nx.BinaryBackend`
- `require_cuda?: false`
- `default_slm_profile: :qwen_coordinator`

Expect order-of-magnitude slower latencies than CUDA or EMLX. Not
intended for production use.

### `:tiny_gpt2`

Synthetic profile used in tests; not for real workloads. Skip unless
you're writing tests.

### `{:custom, BackendMod, opts}`

Tuple-shaped profile for anyone wiring up a backend that does not have
a built-in name. The runtime calls `Nx.global_default_backend({BackendMod, opts})`
when this profile is selected.

## Which Mix Tasks Accept `--runtime-profile`?

After the Phase D refactor:

- `mix trinity.sakana.export_adapted --runtime-profile <name>` — pick
  the backend used to run the SVD/SVF pipeline.
- `mix trinity.sakana.router_trace --runtime-profile <name>` — trace a
  routing call with the selected backend.
- `mix trinity.sakana.large_tensor_chunks --runtime-profile <name>` —
  chunked tensor work (default: CUDA for back-compat).
- `mix trinity.sakana.parity_sample --runtime-profile <name>` —
  parity sampling.
- `mix trinity.hitl.adapted --runtime-profile <name>`, also
  `trinity.hitl.base_qwen`, `trinity.hitl.gpu`, `trinity.hitl.head_route`.
- `mix run examples/qwen_router_prompt_eval.exs --runtime-profile <name>`.
- `mix run examples/local_coordinator_route.exs --runtime-profile <name>`.
- `mix run examples/mock_orchestration_trace.exs --runtime-profile <name>`.

`--runtime-profile cuda_exla` is the default for every task, so no
existing CUDA workflow needs a flag.

## Backend Selection In Library Code

`TrinityCoordinator.Sakana.Coordinator.load/1` accepts:

```elixir
TrinityCoordinator.Sakana.Coordinator.load(
  runtime_profile: :emlx,
  artifact_dir: "priv/sakana_trinity/adapted_qwen3_0_6b_layer26"
)
```

For finer-grained overrides — for example, picking a non-named backend
without writing a `{:custom, ...}` profile — you can pass the
backend tuple directly:

```elixir
TrinityCoordinator.Sakana.Coordinator.load(
  runtime_profile: :emlx,                  # for require_cuda? = false
  backend: {EMLX.Backend, device: :cpu}    # but use CPU device
)
```

The `:backend` and `:require_cuda` keys are compatibility overrides
that pre-date the profile system; they remain supported.

## Choosing A Profile

| You have… | Use |
|---|---|
| NVIDIA GPU + CUDA-12 toolchain + Linux | `:cuda_exla` (default) |
| Apple Silicon (M-series), production-shaped | `:emlx` + add `{:emlx, "~> 0.3"}` to your deps |
| Apple Silicon (M-series), research / Emily MLX | `:emily` + add `{:emily, "~> 0.4"}` to your deps |
| No GPU; want to run unit tests / quick sanity checks | `:binary` |
| Some other backend (e.g. Torchx, custom NIF) | `{:custom, BackendMod, opts}` |

## Verifying A Profile

```bash
mix trinity.env.check
```

reports the current `XLA_TARGET` and any artifact-directory issues
without loading EXLA. For richer per-profile validation, the
`RuntimeProfile.compatibility_probe/1` family of functions returns a
structured report indicating whether the profile's expected backend is
loadable in this process, whether the artifact path exists, and so on.

## Per-Profile Snapshot Fixtures And Margin Floors

`examples/qwen_router_prompt_eval.exs` supports a per-profile snapshot
fixture lane and per-profile margin defaults so a non-CUDA backend can
land its own empirical floors without rewriting or lowering the
canonical CUDA snapshot.

Resolution order for the `--snapshot` flag (Phase 5):

1. **Explicit `--snapshot path`** — wins unconditionally; existing CI
   flows pinning the canonical CUDA fixture keep working without
   reinterpretation.
2. **`examples/fixtures/runtime_profiles/<profile>/qwen_router_prompt_eval_logits.json`**
   — picked up automatically when the per-profile file is present.
3. **`nil`** — no snapshot drift check (the same default behaviour as
   before Phase 5). To pin against the CUDA snapshot, pass
   `--snapshot examples/fixtures/qwen_router_prompt_eval_logits.json`
   explicitly. We deliberately do **not** fall through to the legacy
   fixture path automatically: that would silently enable a strict
   6dp logits byte-equivalence check for operators who did not opt in.

Margin floor resolution (`--min-agent-margin` / `--min-role-margin`):

1. **Explicit CLI flag** — wins.
2. **`RuntimeProfile.default_margins(profile)`** — every built-in
   profile inherits the canonical CUDA defaults (`agent: 0.24`,
   `role: 1.06`) unless overridden via
   `RuntimeProfile.override_default_margins/2` (e.g. for a future
   `:emily` profile that wants `agent: 0.33`, `role: 0.82`).
3. **Module-level defaults** (legacy fallback in the eval script).

## Validating With Emily (Apple Silicon, MLX, Research)

Emily is a first-class profile — see the [`:emily`](#emily) section
above for the full recipe. The short version:

1. Add `{:emily, "~> 0.4", only: [:dev, :test]}` to your **parent**
   application's `mix.exs`. Do NOT add it to `trinity_coordinator`'s
   own `mix.exs`.
2. `mix deps.get`.
3. Pass `--runtime-profile emily` to `mix trinity.sakana.export_adapted`
   and `mix run examples/qwen_router_prompt_eval.exs`.

The profile's `default_min_agent_margin` / `default_min_role_margin`
fields are pre-seeded with the empirical Emily floors (`0.33` / `0.82`)
from ausimian's 2026-05-21 validation pass, so a clean run does not
require any explicit `--min-*-margin` overrides.

If you would rather keep your run shaped exactly like the prior
`{:custom, Emily.Backend, []}` recipe — for example to pin a different
backend module — the custom-tuple form still works:

```elixir
profile =
  TrinityCoordinator.RuntimeProfile.resolve({:custom, Emily.Backend, []})
  |> TrinityCoordinator.RuntimeProfile.override_default_margins(
       agent: 0.33,
       role: 0.82
     )
```

### Background — what ausimian's pass measured

- 0/37 drift on the decision-stable fields (`agent_id`, `role_id`,
  `token_count`, `transcript_hash`).
- 37/37 differ on `route_hash` (6dp logit drift — expected on a
  different kernel stack).
- Empirical worst margins were `agent: 0.417` (`two_assistant_turns`)
  and `role: 1.029` (`escalate_to_human`); the 80% floors are
  therefore `0.33` / `0.82`. These are exactly the values the
  built-in `:emily` profile now ships.
- Phase 1 (lazy-backend timing sync) makes `decompose_elapsed_ms`
  report real GPU wall time on Emily / EMLX instead of the host-side
  dispatch cost of an unmaterialised future.

### Per-profile snapshot fixture for Emily

`route_hash` drifts on every case under Emily because float aggregation
order differs from CUDA. To pin Emily-stable snapshots, drop a
`examples/fixtures/runtime_profiles/emily/qwen_router_prompt_eval_logits.json`
file next to the legacy CUDA fixture; the eval entry point's
`SnapshotResolver` will pick it up automatically when
`--runtime-profile emily` is passed without `--snapshot`. See "Per-Profile
Snapshot Fixtures And Margin Floors" above for the resolution order.

The seed snapshot can be generated by running the eval once with
`--snapshot-out examples/fixtures/runtime_profiles/emily/qwen_router_prompt_eval_logits.json`
on Apple Silicon.

## AMD ROCm Build Instructions

These instructions should be sufficient build a working version of EXLA with
ROCm support.

They are only known to work on Linux.  I would be fairly surprised if they
worked on Windows.

### Prerequisites

Building a working AMD ROCm environment is beyond the scope of this document.
If you don't have one of these, the ROCm Core SDK install page is a good place
to start.  You can find it [here](https://rocm.docs.amd.com/en/latest/install/rocm.html).

Running `rocm-smi` is a good smoke test to determine if you have a working
environment, though it won't detect if you don't have the necessary headers for
compilation.

You'll also need a version of Bazel.  If you use `mise` or some other tool to
manage your build tools, you can add `bazel 7.7.1` to the `.tool-versions`
file.

### Variables

Before compiling, you need to set and export the following variables:

```sh
export EXLA_TARGET=rocm
export XLA_TARGET=rocm
export XLA_BUILD=true

export ROCM_PATH=/opt/rocm
export BUILD_FLAGS="--action_env=TF_ROCM_AMDGPU_TARGETS=gfx1100"
```

The EXLA and XLA variables ensure that XLA is build from scratch and that it
knows that it needs to build for a ROCm environment.

`ROCM_PATH` should point to the ROCm installation you want to use to build.

Note that some environments have packages from their own distribution that may
conflict with the packages the installer uses.  If you get weird build failures
that mention header files outside of your ROCm installation, you probably need
to remove some system packages.

The `BUILD_FLAGS` variable is used by Bazel to tell it which ROCm hardware to
support.  Note the hardware revision code at the end of the line.  It is a list
of the identifiers used by ROCm to specify which version to use.  You can find
these in on the install page if you use the drop-downs to select your hardware

If you want to specify more than one, put commas in
between them (i.e. `gfx950,gfx1100`).

### Compiling
At this point you can basically follow the instructions in the Quickstart.  If
you've previously build or downloaded the `xla` code, you may need to clean it
out.  You can do this by running:

```sh
mix deps.clean xla
mix deps.get
```

This should get you a clean copy of the dependency which will build.  You may
also need to remove `~/.cache/xla` and `~/.cache/xla_build` to get a completely
fresh build.

Building `xla` for ROCm can take quite a while to run.

### Runtime

When running the code, you may need to set some additional variables.

If your hardware isn't detected, sometimes you can set the following to
indicate which hardware it should try to use.  Sometimes here you will specify
a compatible version (e.g. `11.0.0`) instead of the actual version (e.g.
`11.5.1` for `gfx1151`).

```sh
export HSA_OVERRIDE_GFX_VERSION=11.0.0
```

When running, the auto-tuning system may complain about missing reference
output.  The specific message I saw was:

> No reference output found even though buffer checking was requested while autotuning

You can generate this reference data by setting the following variable the
first time you run.

```sh
export XLA_FLAGS=--xla_gpu_dump_autotune_results_to="${HOME}/.cache/xla_autotune.textproto"
```

If it works, you will see a bunch of log lines like this:

> Autotune results serialized to file: `/home/your_user/.cache/xla/autotune.textproto`

Subsequent runs can be made to use this file by setting the following flag instead:

```sh
export XLA_FLAGS=--xla_gpu_load_autotune_results_from="${HOME}/.cache/xla_autotune.textproto"
```

There is nothing special about that path or filename.  You can put it wherever
you want and name it whatever you want.

## References

- `TrinityCoordinator.RuntimeProfile` — the module that defines and
  resolves profiles.
- `TrinityCoordinator.Sakana.Coordinator.load/1` — the canonical load
  entry point.
- [Artifact Distribution](artifact_distribution.md) — how to fetch /
  publish the bundle.
- [Troubleshooting](troubleshooting.md) — common failure modes by
  symptom.
