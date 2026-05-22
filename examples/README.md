# Examples

These examples are reviewer-facing smoke runs for the current safe runtime lane.
They use the adapted local Qwen coordinator and avoid live LLM calls unless a
separate provider-gated command is used.

Prerequisites:

- `XLA_TARGET=cuda12`;
- the canonical imported artifact directory at
  `priv/sakana_trinity/adapted_qwen3_0_6b_layer26`;
- a CUDA device capable of loading Qwen3-0.6B through EXLA.

If the artifact directory is missing, fetch the published bundle first:

```bash
mix trinity.artifact.fetch
```

That downloads the SHA-pinned 624 MB bundle from the project's
HuggingFace dataset repo. Rebuild the bundle yourself only when you want
to validate or modify the export pipeline; that heavier path is documented
in `guides/artifacts_and_export.md`.

The examples use the promoted default artifact path. Pass `--artifact-dir` only
when intentionally checking another artifact bundle.

## Local Coordinator Route

This example proves the adapted local Qwen coordinator can load, tokenize a
prompt, extract the route hidden vector, and produce real router logits.
It performs no provider dispatch.

```bash
XLA_TARGET=cuda12 mix run examples/local_coordinator_route.exs -- \
  --artifact-dir priv/sakana_trinity/adapted_qwen3_0_6b_layer26 \
  --prompt "Select a TRINITY role for this reasoning task."
```

Expected evidence:

- artifact manifest hash and source vector hash;
- formatted transcript and token ids;
- hidden-state shape and selected hidden index;
- route vector backend and hash;
- full route logits, agent logits, role logits;
- selected agent id/name and selected role id/name for the current run.

## Qwen Router Prompt Eval

This example is a small eval-style regression check for the local Qwen router
only. It loads the adapted coordinator once, runs a suite of prompt/transcript
cases, prints the suggested route for each case, and asserts the expected
`agent_id` and `role_id`. It performs no provider dispatch.

```bash
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs
```

Normal output is intentionally human-readable:

- each case prints the exact prompt/transcript sent to the router;
- each case prints the expected route and the route returned by the router;
- agent labels are explained as original Sakana checkpoint slots;
- XLA/CUDA native logs are captured at
  `tmp/examples/qwen_router_prompt_eval.native.log` instead of printed inline.

Useful variants:

```bash
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- --list-cases
```

```bash
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- \
  --case math_direct \
  --case security_review \
  --case final_answer_check
```

```bash
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- \
  --no-assert \
  --verbose
```

```bash
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- \
  --show-logits
```

```bash
XLA_TARGET=cuda12 mix run examples/qwen_router_prompt_eval.exs -- \
  --debug-native-logs
```

Expected evidence:

- one Qwen load for the whole suite;
- exact prompt/transcript for each case;
- expected agent/role and returned agent/role for each case;
- token count for each formatted transcript;
- `PASS qwen_router_prompt_eval` when all expected routes match.

The `google/gemma-3-27b-it` text is not a live provider call. It is agent slot
4 from the original Sakana checkpoint's seven-agent label order. This local
eval only reports which slot the router selected.

## Router Input And Context

The router input is not a chat-completion request to an external LLM. It is a
local hidden-state extraction pass over a formatted transcript:

```elixir
[
  %{role: "user", content: "What should happen next?"},
  %{role: "assistant", content: "Worker answer: ..."}
]
```

The current formatter converts that list into one line per message:

```text
user: What should happen next?
assistant: Worker answer: ...
```

Qwen3-0.6B then runs locally with generation disabled. The route vector is the
penultimate-token hidden state from the formatted transcript, and the imported
Sakana head maps that `{1, 1024}` vector to seven agent logits plus three role
logits.

Qwen3 models are commonly documented with a 32,768-token native pretraining
context. The imported Sakana runtime contract records `max tokens: 4096`, which
is the compatibility budget this project preserves for the coordinator loop.
For routing quality and latency, prefer compact transcripts: current user task,
latest Worker/Thinker/Verifier state, and only the evidence needed to choose the
next role. Very long transcripts can fit only if tokenization, EXLA memory, and
the loaded model permit it, and they make every route decision slower.

## Mock Orchestration Trace

This example proves the adapted coordinator can drive the orchestrator through
role injection, the provider boundary, verifier termination, and JSONL trace
persistence while using deterministic mock responses.

```bash
XLA_TARGET=cuda12 mix run examples/mock_orchestration_trace.exs -- \
  --artifact-dir priv/sakana_trinity/adapted_qwen3_0_6b_layer26 \
  --prompt "Select a TRINITY role for this reasoning task." \
  --trace-out tmp/examples/mock_orchestration_trace.jsonl
```

Expected evidence:

- mock provider calls printed with role and selected agent id;
- trace summary containing `run_started`, `slm_extracted`, `route_selected`,
  `provider_called`, `turn_completed`, and `run_completed`;
- Worker selected before Verifier for the default prompt;
- final result accepted by the mock verifier;
- persisted JSONL trace at the supplied path.

## Live Providers

Live provider calls are not part of these examples. Hosted, GeminiEx, and Agent
Session Manager specs are routed through the shared `:inference` package by
`TrinityCoordinator.AgentPool.Inference`; use the gated route demo only after a
real provider pool is configured:

```bash
XLA_TARGET=cuda12 mix trinity.route.demo \
  --allow-live \
  --profile qwen_sakana_adapted \
  --provider-pool configured \
  --trace-out tmp/trinity_route_demo_live.jsonl
```

Without `--allow-live`, live mode fails before provider dispatch.
