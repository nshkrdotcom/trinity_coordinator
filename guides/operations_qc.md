# Operations And Quality Gates

This guide lists the checks that should be run before changing the parity or
runtime lanes.

## Fast Regression Suite

```bash
XLA_TARGET=cuda12 mix test
```

Current expected result (post Phase 11, 2026-05-20):

```text
1 doctest, 302 tests, 0 failures (24 excluded)
```

The excluded tests include slow Qwen/SVD gates and expensive artifact export
paths.

For the AGENTS.md gate matrix in one command:

```bash
XLA_TARGET=cuda12 mix trinity.gates --include-hex-build --summary-out tmp/gates.json
```

`hex_build_advisory: fail` is expected and non-blocking until Bumblebee
is unpinned; see `docs/bumblebee_unpin_playbook.md`.

For a pre-flight environment check before any other Mix task:

```bash
XLA_TARGET=cuda12 mix trinity.env.check
```

For a structured wrapper around the Python parity comparator:

```bash
XLA_TARGET=cuda12 mix trinity.parity.check \
  --python-report tmp/sakana_parity/python_sample_trace.json \
  --elixir-report tmp/sakana_parity/elixir_sample_trace.json
```

For service-grade budget and trace configuration, see
[Production Deployment Runbook](../docs/production_runbook.md).

## Static Checks

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
```

Python script syntax:

```bash
python3 -m py_compile priv/sakana_trinity/scripts/*.py
```

Docs:

```bash
mix docs
```

Docs should build without undefined-reference warnings.

## Functional Parity Gate

Generate reports:

```bash
python3 priv/sakana_trinity/scripts/debug_sakana_parity_sample.py \
  --model-torch-dtype float32 \
  --out tmp/sakana_parity/python_sample_trace.json \
  --write-components-dir tmp/sakana_parity/python_components
```

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

Run strict functional comparison:

```bash
python3 priv/sakana_trinity/scripts/compare_sakana_parity_reports.py \
  --strict-stage-tolerances \
  tmp/sakana_parity/python_sample_trace.json \
  tmp/sakana_parity/elixir_sample_trace.json
```

This is the required parity gate.

When validating the full selected tensor set, generate Python with
`--all-selected-tensors --svd-weights path/to/svd_weights.pt`, then add
`--all-selected-tensors` to the Elixir command above. Add
`--selected-source-filter 'model.layers.26.'` for the current bounded replay
gate. That mode reads
`trinity_svf_all_selected_stage_debug.safetensors` and fails strict stage
tolerances if any required stage fails for any replayed selected tensor.
Embedding and LM-head tensors require a chunked large-tensor gate before they
should be enforced through Elixir; the monolithic stage replay can otherwise
stall or exhaust GPU memory.

The additional Elixir flags are intentional for commit-loop parity work:

- `--source-from-python-stage` avoids loading Qwen only to fetch the sample
  source tensor.
- `--preferred-layout-only` skips known-wrong V-layout diagnostics.
- `--device-semantic-only` avoids a large host CPU matrix multiply and still
  emits stage checks from the EXLA semantic variant.

## Byte-Match Gate

Use only when intentionally working on exact final bytes:

```bash
python3 priv/sakana_trinity/scripts/compare_sakana_parity_reports.py \
  --strict-current-python \
  tmp/sakana_parity/python_sample_trace.json \
  tmp/sakana_parity/elixir_sample_trace.json
```

This is expected to fail in the current state.

## Expensive Gates

Adapted coordinator smoke against the canonical import from Phase 2:

```bash
XLA_TARGET=cuda12 mix trinity.hitl.adapted \
  --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python
```

This gate must print:

```text
Artifact status: complete
Artifact layout: checkpoint_directory
Selected tensor count: 9
Selected singular value count: 9216
adapted Qwen vector shape: {1, 1024}
adapted route logits shape: {1, 10}
adapted agent logits shape: {7}
adapted role logits shape: {3}
```

It proves the imported artifact can patch Qwen, load the router head, and route
a fixed transcript on CUDA. Pair it with router trace parity when validating
artifact semantics against Python.

Router trace parity:

```bash
uv run --python 3.11 \
  --with torch==2.7.1 \
  --with transformers==4.55.2 \
  --with accelerate==1.6.0 \
  --with safetensors \
  python priv/sakana_trinity/scripts/debug_sakana_router_trace.py \
    --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python \
    --device cpu \
    --model-torch-dtype bfloat16 \
    --out tmp/sakana_parity/python_router_trace_bf16_cpu.json
```

```bash
XLA_TARGET=cuda12 mix trinity.sakana.router_trace \
  --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python \
  --python-report tmp/sakana_parity/python_router_trace_bf16_cpu.json \
  --out tmp/sakana_parity/elixir_router_trace.json
```

The current PyTorch 2.7.1 wheel cannot execute CUDA kernels on the RTX 5060 Ti
`sm_120`, so the Python trace runs on CPU. The required comparison is exact for
transcript, token ids, router-head hash, shapes, and argmax ids; hidden and
logit payloads use declared cosine and relative-L2 alignment thresholds with
max/mean absolute errors retained as diagnostics.

Qwen-focused tests:

```bash
XLA_TARGET=cuda12 mix test --only qwen --trace
```

Slow SVD tests:

```bash
XLA_TARGET=cuda12 mix test test/trinity_coordinator/sakana/svd_test.exs \
  --only slow_qwen_svd --trace
```

Expensive export gate:

```bash
XLA_TARGET=cuda12 mix test test/trinity_coordinator/sakana/svd_test.exs \
  --only expensive_qwen_svd --trace
```

These are not part of every local commit loop.

Adapted runtime mock loop:

```bash
XLA_TARGET=cuda12 mix trinity.hitl.mock_loop \
  --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python \
  --trace-out tmp/trinity_mock_trace.jsonl
```

Expected high-level result:

```text
Mock turn 1: role=:worker agent_id=4
Mock turn 2: role=:verifier agent_id=4
Termination: accepted
PASS
```

Safe route demo:

```bash
XLA_TARGET=cuda12 mix trinity.route.demo \
  --mock-provider \
  --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python \
  --trace-out tmp/trinity_route_demo.jsonl
```

Live provider route demo is credential-gated and should be run only with an
explicit configured provider pool:

```bash
XLA_TARGET=cuda12 mix trinity.route.demo \
  --allow-live \
  --profile qwen_sakana_adapted \
  --provider-pool gemini_cli_asm \
  --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python \
  --trace-out tmp/trinity_route_demo.jsonl
```

Provider errors fail the command; they are not converted into successful smoke
results.

Reviewer examples:

```bash
XLA_TARGET=cuda12 mix run examples/local_coordinator_route.exs -- \
  --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python
```

```bash
XLA_TARGET=cuda12 mix run examples/mock_orchestration_trace.exs -- \
  --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python \
  --trace-out tmp/examples/mock_orchestration_trace.jsonl
```

Both examples should print detailed local coordinator evidence and complete
without live provider credentials.

## Expected XLA Warnings

EXLA/CUDA may print:

```text
ptxas warning : Registers are spilled to local memory
```

This does not mean VRAM overflow. It means a compiled GPU kernel used more
registers than available and some values were placed in CUDA local memory. It is
often a compile/runtime performance concern, not a parity failure by itself.

Use `--semantic-only` during semantic parity work to avoid the slow native Nx
SVD compilation path. For the fastest sample parity loop, pair it with
`--source-from-python-stage --preferred-layout-only --device-semantic-only`.

## Commit Checklist

- [ ] `mix format --check-formatted`
- [ ] `python3 -m py_compile priv/sakana_trinity/scripts/*.py`
- [ ] `XLA_TARGET=cuda12 mix test`
- [ ] `mix credo --strict`
- [ ] `mix dialyzer`
- [ ] `mix docs`
- [ ] `XLA_TARGET=cuda12 mix trinity.hitl.mock_loop --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python --trace-out tmp/trinity_mock_trace.jsonl`
- [ ] `XLA_TARGET=cuda12 mix run examples/local_coordinator_route.exs -- --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python`
- [ ] `XLA_TARGET=cuda12 mix run examples/mock_orchestration_trace.exs -- --artifact-dir tmp/sakana_parity/adapted_artifacts_from_python --trace-out tmp/examples/mock_orchestration_trace.jsonl`
- [ ] parity runtime check when parity code changed:
  `compare_sakana_parity_reports.py --strict-stage-tolerances`
- [ ] README and guides updated when behavior or standards change.
