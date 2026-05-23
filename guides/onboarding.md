# Onboarding

This guide is the starting point for working on `trinity_coordinator`.

The current project direction is not paper-training reproduction. The active
goal is to recreate the Python Sakana/Qwen artifact application process in
Elixir, prove it against stage-level parity checks, and then use that validated
small local model as the coordinator for real LLM provider calls.

## What This Repository Is For

`trinity_coordinator` is an Elixir/Nx implementation of a TRINITY-style routing
coordinator:

1. A compact local language model reads the current conversation.
2. The runtime extracts the penultimate-token hidden state.
3. A small routing head maps that hidden state to agent and role logits.
4. The selected role is injected into the prompt.
5. A provider boundary dispatches the selected work to an LLM.

The production-intent compact model is `Qwen/Qwen3-0.6B` loaded through
`Bumblebee.Text.Qwen3` on EXLA CUDA. The Sakana artifacts adapt selected Qwen
tensors using singular-value fine tuning and provide the router head weights.

## Current Status In One Page

Working today:

- Elixir loads Qwen3-0.6B through Bumblebee on CUDA.
- The router vector artifact is available as safetensors.
- The router vector split is understood:
  - `9216` SVF scale offsets.
  - `10240` router-head values reshaped to `{10, 1024}`.
- The Elixir SVD/SVF implementation can reconstruct adapted tensors.
- The Python parity script can generate current Python baselines, component
  safetensors, and stage tensors.
- The Elixir parity task can consume those Python components and compare
  stage-by-stage against Python.
- The recommended semantic debug loop now avoids repeated Qwen profile loading
  by reading Python's `stage.source_f32`, checks only the preferred `torch_v`
  layout, and runs the reconstruction through EXLA rather than a slow host CPU
  matmul.
- Hosted, GeminiEx, and Agent Session Manager provider specs now enter the
  shared `:inference` package through `TrinityCoordinator.AgentPool.Inference`.
- `--strict-stage-tolerances` is the required functional correctness gate.

Not complete yet:

- Final `bf16` byte hash equality with Python remains aspirational.
- Live provider smokes are still credential-gated and not part of default tests.
- The old experiment-reproduction lane has been removed from active code.
- The supplemental Python submission has been audited for runtime semantics.
  Its checkpoint metadata is the source of truth for agent order, role order,
  selected SVF layer, turn budget, and router hidden extraction mode.

## Required Local Environment

The current development lane assumes:

- Elixir `~> 1.18`.
- NVIDIA driver visible to `nvidia-smi`.
- CUDA-capable EXLA through `XLA_TARGET=cuda12`.
- Internet access for first-time Hugging Face model downloads.
- Python with PyTorch, Transformers, and safetensors for the parity scripts.

The resolved Elixir dependency lane currently uses:

- `nx 0.12.1` from Hex
- `exla 0.12.0` from Hex
- `axon 0.8.1`
- `bumblebee` pinned to `elixir-nx/bumblebee` commit
  `d0774e8ab8c4d5ac60ade95ec8dc9e1f0efd7306` (post-v0.7.0 main)

## First Commands

Fetch dependencies and run the fast suite:

```bash
mix deps.get
XLA_TARGET=cuda12 mix test
```

Expected current result:

```text
1 doctest, 302 tests, 0 failures (24 excluded)
```

Run the pre-flight environment validator before any other Mix task:

```bash
XLA_TARGET=cuda12 mix trinity.env.check
```

A single readable failure line is the success signal that this catches
the `XLA_TARGET` and artifact-dir misconfigurations early.

### Fetch the adapted artifact bundle

A fresh clone does not contain the 624 MB adapted artifact bundle (it is
generated output, gitignored). Fetch it in one command:

```bash
mix trinity.artifact.fetch
```

This downloads the bundle from the project's HuggingFace dataset
repository, verifies each file against the pinned SHA-256 manifest at
`priv/sakana_trinity/artifact_pin.json`, and writes the files into
`priv/sakana_trinity/adapted_qwen3_0_6b_layer26/`. See
[Artifact Distribution](artifact_distribution.md) for offline,
custom-destination, and publisher workflows.

If you intend to **rebuild** the bundle on your own hardware (e.g. for
EMLX validation on Apple Silicon), skip the fetch and follow
[Sakana Artifacts And Export](artifacts_and_export.md) instead. The
fetch and the rebuild are equivalent endpoints; pick whichever fits
your situation.

### Choose a runtime profile (default is fine on CUDA)

The router and exporter both accept a `--runtime-profile` flag. The
default `:cuda_exla` profile works for the existing Linux/CUDA path.
For Apple Silicon, add `{:emlx, "~> 0.3"}` to your parent app and use
`--runtime-profile emlx`. For CPU-only sanity checks, use
`--runtime-profile binary`. See [Runtime Profiles](runtime_profiles.md)
for the full menu.

Run the static quality gates:

```bash
mix credo --strict
mix dialyzer
```

Build docs:

```bash
mix docs
```

## Confirm CUDA

```bash
XLA_TARGET=cuda12 mix run -e 'IO.inspect(EXLA.Client.get_supported_platforms())'
```

Expected shape:

```elixir
%{host: _, cuda: _}
```

## Run The Current Parity Loop

First emit Python's current baseline, Python component bundle, and Python stage
bundle:

```bash
python3 priv/sakana_trinity/scripts/debug_sakana_parity_sample.py \
  --model-torch-dtype float32 \
  --out tmp/sakana_parity/python_sample_trace.json \
  --write-components-dir tmp/sakana_parity/python_components
```

Then emit Elixir's semantic parity report without native Nx SVD diagnostics:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.parity_sample \
  --semantic-only \
  --device-semantic-only \
  --preferred-layout-only \
  --source-from-python-stage \
  --components-dir tmp/sakana_parity/python_components \
  --python-report tmp/sakana_parity/python_sample_trace.json \
  --stage-dir tmp/sakana_parity/elixir_stages \
  --out tmp/sakana_parity/elixir_sample_trace.json
```

Compare with the required functional gate:

```bash
python3 priv/sakana_trinity/scripts/compare_sakana_parity_reports.py \
  --strict-stage-tolerances \
  tmp/sakana_parity/python_sample_trace.json \
  tmp/sakana_parity/elixir_sample_trace.json
```

Do not use final hash equality as the main correctness gate while the stage
checks are still the active engineering standard. Use `--strict-current-python`
only when intentionally pursuing byte-for-byte equality.

## What To Read Next

- `guides/current_direction.md`: why the project is focused on parity and
  service buildout, not experiment reproduction.
- `guides/system_architecture.md`: runtime modules and data flow.
- `guides/python_parity_reconstruction.md`: how the Python process is recreated.
- `guides/stage_checks_and_tolerances.md`: the correctness standard.
- `guides/service_buildout.md`: what remains before the coordinator can run in
  service.
- `docs/priv/20260428/`: private implementation-ready source audit,
  semantics contract, milestone checklist, and quality-gate runbook.
