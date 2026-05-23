# Production Qwen SLM Profile

This guide describes how to add and validate a production SLM profile for a
Qwen-class coordinator model in `trinity_coordinator`.

The repository keeps `hf-internal-testing/tiny-random-gpt2` as the fast baseline
because it is small and cheap to run. The production Qwen path now uses
`Qwen/Qwen3-0.6B` through `Bumblebee.Text.Qwen3` on CUDA-backed EXLA. The tiny
profile remains useful for quick regression checks; the Qwen profile proves the
paper-scale hidden width and target model family.

An artifact-adapted profile is also available:
`SLMProfile.qwen_sakana_adapted/0` loads `qwen_coordinator` and applies
generated Sakana artifacts (`adapted_tensors.safetensors` and `router_head.safetensors`)
at profile load time. It requires the same CUDA runtime and requires a completed manifest
in `priv/sakana_trinity/adapted_qwen3_0_6b_layer26`.

1. Load tokenizer and model with `Bumblebee`.
2. Run a real `Axon.predict/3` SLM forward pass.
3. Extract the final hidden-state tensor.
4. Slice the second-to-last token vector.
5. Route with a real Axon coordination head.
6. Train the head with real extracted vectors.
7. Verify tensors land on `EXLA.Backend<cuda:0>`.

A production profile replaces only the tiny SLM profile. It must not change the
router contract.

## Implementation Discipline

Use TDD/RGR throughout this work:

1. Red: write the smallest failing test or executable probe for the next
   requirement.
2. Green: implement only enough to pass that test.
3. Refactor: simplify the design while keeping the test green.

Maintain a live implementation checklist in the PR or working tree. Revise it
when new constraints are discovered, when dependency behavior changes, or when a
milestone is split. If context compaction occurs, recontextualize by reading
this guide, reading the active checklist, running `git status --short`, and
rerunning the smallest relevant test before editing.

Every milestone must end with the quality gates named in that milestone. Before
merge, run the final quality gate, commit only QA-passing changes, and push
every repo touched by the work.

## Target Contract

A production Qwen profile is ready when the project can run this shape of code:

```elixir
TrinityCoordinator.Runtime.put_cuda_backend!()

{:ok, {model_info, tokenizer}} =
  TrinityCoordinator.Extractor.load_slm_model(
    {:hf, "Qwen/<chosen-qwen-repo>"},
    Bumblebee.Text.<QwenCompatibleModule>,
    :base
  )

{:ok, metadata} =
  TrinityCoordinator.Extractor.extract_penultimate_hidden_state_with_metadata(
    model_info,
    tokenizer,
    [%{role: "user", content: "Plan a solution to this task."}]
  )

metadata.vector_shape
#=> {1, hidden_size}

TrinityCoordinator.Runtime.tensor_backend(metadata.vector)
#=> "EXLA.Backend<cuda:0, ...>"
```

For the paper-scale target, `hidden_size` is expected to be 1024 for the
Qwen-class coordinator cited in the TRINITY notes. Do not hard-code that number
into the extractor. Build the coordination head from the observed vector width:

```elixir
hidden_size = Nx.axis_size(metadata.vector, 1)
model = TrinityCoordinator.CoordinationHead.build_model(hidden_size, num_agents, 3)
```

## Current Qwen Runtime Lane

The checked-in dependency lane is:

- `nx ~> 0.12`, resolved from Hex as `0.12.1`.
- `exla ~> 0.12`, resolved from Hex as `0.12.0`.
- `axon ~> 0.7`
- `bumblebee` pinned to upstream `elixir-nx/bumblebee`
  `d0774e8ab8c4d5ac60ade95ec8dc9e1f0efd7306` (post-v0.7.0 main).

On this host, that lane is verified with `XLA_TARGET=cuda12`. Bumblebee
v0.7.0 ships Qwen3 via Hex; the post-main pin picks up minor fixes
landed after the release.

### `qwen_cuda_ready` outcome

Current resolved versions used for this outcome:

- `nx 0.12.0` (GitHub commit above)
- `exla 0.12.0` (GitHub commit above)
- `axon 0.7.0`
- `bumblebee` git ref `d0774e8ab8c4d5ac60ade95ec8dc9e1f0efd7306`

Outcome: `qwen_cuda_ready` is active for base Qwen hidden-state extraction.
`SLMProfile.qwen_coordinator/0` uses:

- repo: `{:hf, "Qwen/Qwen3-0.6B"}`
- module: `Bumblebee.Text.Qwen3`
- architecture: `:for_causal_language_modeling`
- load options: `type: :bf16` (the backend is injected at load time
  by `Coordinator.load/1` based on the active `RuntimeProfile`;
  see `guides/runtime_profiles.md`).
- expected hidden size: `1024`

Hidden states are enabled at prediction time with Axon's global layer option
`global_layer_options: [output_hidden_states: true]`. Do not pass
`output_hidden_states` as a Qwen3 `spec_overrides` value; Qwen3 does not accept
that field as a config attribute.

Do not count a CPU-only run as passing this profile. The test must prove the
result tensor backend contains `EXLA.Backend<cuda:`.

Current local probe status:

- `test/trinity_coordinator/slm_profile_test.exs` includes an `@tag :qwen`
  profile compatibility and model-load probe.
- `test/trinity_coordinator/extractor_test.exs` includes an `@tag :qwen`
  hidden-state probe that extracts a real `{1, 1024}` Qwen vector on CUDA.
- Run both with `XLA_TARGET=cuda12 mix test --only qwen --trace`.

Canonical adapted-profile smoke check:

```bash
XLA_TARGET=cuda12 mix test --only qwen_sakana_adapted --trace
```

Suggested implementation order after this baseline:

1. Run the adapted export command to materialize artifacts:

   ```bash
   XLA_TARGET=cuda12 mix trinity.sakana.export_adapted
   ```

2. Validate runtime loading with:

   ```bash
   XLA_TARGET=cuda12 mix test test/trinity_coordinator/sakana/svd_test.exs --only qwen_sakana_adapted --trace
   ```

### Adapted profile runtime and recovery

The adapted profile load path is `qwen_sakana_adapted` and it applies artifacts from
`priv/sakana_trinity/adapted_qwen3_0_6b_layer26` during `SLMProfile.load_profile/1`.

- `Artifact.patch_model_info!/2` validates manifest identity/shape before patching.
- It fails fast if:
  - manifest status is not `complete`,
  - `export_complete != true`,
  - or any selected tensor is not ready.
- Set `allow_incomplete: true` only in intentionally explicit smoke checks.

Canonical artifact build for this profile:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted
```

If the canonical export is interrupted, resume with:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted --resume
```

Use `--force` to intentionally discard state and rebuild:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted --force
```

If resume fails, first check:

- `manifest.json` for `status`, `error`, and `selected_tensors[].status`,
- `export.log.jsonl` for the last events (`manifest_partial`, `tensor_export_failed`,
  `artifact_merge_failed`, etc.),
- `source_vector_sha256` against the current source artifact.

## Model Selection Checklist

Maintain and update this checklist as the profile work progresses. Before adding
the profile, select a single canonical repository and record:

- Hugging Face repository id.
- Model family and exact version.
- Hidden size.
- Number of layers.
- Context length.
- Parameter count.
- Precision available in safetensors.
- Whether `tokenizer.json` is present.
- Whether the config declares a Bumblebee-supported architecture.
- Expected local VRAM footprint for a single forward pass.
- License and redistribution constraints.

Prefer a small instruct/base checkpoint that matches the paper goal of a compact
coordinator. The coordinator is not used to generate text in this project; it is
used as a hidden-state encoder.

## Dependency Upgrade Procedure

1. Create a dependency branch.

   ```bash
   git switch -c qwen-slm-profile
   ```

2. Check current resolved versions.

   ```bash
   mix deps
   mix hex.outdated
   ```

3. Upgrade only the minimum dependency set needed for Qwen support.

   ```bash
   mix deps.update bumblebee axon nx exla xla tokenizers
   ```

4. Re-resolve and compile on the CUDA lane required by the resolved EXLA/XLA
   versions.

   ```bash
   XLA_TARGET=cuda12 mix deps.compile
   ```

   If the resolved `xla`/`exla` stack requires CUDA13, switch the command to:

   ```bash
   XLA_TARGET=cuda13 mix deps.compile
   ```

5. Confirm supported platforms.

   ```bash
   XLA_TARGET=<cuda-target> mix run -e 'IO.inspect(EXLA.Client.get_supported_platforms())'
   ```

   Required result:

   ```elixir
   %{host: _, cuda: _}
   ```

6. Run the existing real-router baseline before adding Qwen.

   ```bash
   XLA_TARGET=<cuda-target> mix test
   XLA_TARGET=<cuda-target> mix test --only integration
   XLA_TARGET=<cuda-target> mix trinity.demo
   ```

The baseline must stay green before a Qwen profile is introduced.

## Repository Compatibility Probe

After choosing a Qwen repository, add a temporary local probe. Do not commit this
probe until it has been converted into a proper test or Mix task.

```elixir
repo = {:hf, "Qwen/<chosen-qwen-repo>"}

IO.inspect(Bumblebee.load_tokenizer(repo), label: "tokenizer")
IO.inspect(Bumblebee.load_spec(repo), label: "spec")
IO.inspect(Bumblebee.load_model(repo), label: "model")
```

If `Bumblebee.load_spec/2` cannot infer the model, inspect the repository
`config.json` and identify:

- `"architectures"`
- `"model_type"`
- `"hidden_size"`
- `"num_hidden_layers"`
- tokenizer files, especially `tokenizer.json`

Then map the result to one of:

- first-class Bumblebee Qwen module,
- confirmed compatible existing module,
- unsupported.

Unsupported means the profile is not ready.

## Profile API Shape

When support is available, introduce a small profile module rather than
spreading repository ids through tests and Mix tasks.

Suggested module:

```elixir
defmodule TrinityCoordinator.SLMProfile do
  @moduledoc """
  Named SLM profiles for coordinator hidden-state extraction.
  """

  @type profile :: %{
          required(:name) => atom(),
          required(:repo) => term(),
          required(:module) => module(),
          required(:architecture) => atom(),
          optional(:expected_hidden_size) => pos_integer(),
          optional(:xla_target) => String.t()
        }

  def tiny_gpt2 do
    %{
      name: :tiny_gpt2,
      repo: {:hf, "hf-internal-testing/tiny-random-gpt2"},
      module: Bumblebee.Text.Gpt2,
      architecture: :base,
      expected_hidden_size: 32,
      xla_target: "cuda12"
    }
  end

  def qwen_coordinator do
    %{
      name: :qwen_coordinator,
      repo: {:hf, "Qwen/<chosen-qwen-repo>"},
      module: Bumblebee.Text.<QwenCompatibleModule>,
      architecture: :base,
      expected_hidden_size: 1024,
      xla_target: "<cuda-target>"
    }
  end
end
```

Then add:

```elixir
def load_profile(profile) do
  Extractor.load_slm_model(profile.repo, profile.module, profile.architecture)
end
```

Keep `tiny_gpt2` as the fast, cheap verification profile. Add Qwen as an
explicit production profile.

## TDD/RGR Checklist

Maintain this checklist in the implementation PR or working tree and revise it
as dependency support, model choice, or profile API details change.

- [x] Red: add a metadata test for the current tiny profile.
- [x] Green: introduce `SLMProfile.tiny_gpt2/0` without changing behavior.
- [x] Red: add a metadata test for the Qwen profile.
- [x] Green: add `SLMProfile.qwen_coordinator/0` with repository, module,
      architecture, hidden-size, and CUDA-target metadata.
- [x] Red: add a loader test for profile-based model loading using tiny GPT-2.
- [x] Green: implement `SLMProfile.load_profile/1`.
- [x] Red: add Qwen compatibility probe or `@tag :qwen` model-load test.
- [x] Green: resolve dependency/module support without breaking tiny-profile
      integration tests.
- [x] Red: add Qwen hidden-state extraction test requiring CUDA backend.
- [x] Green: extract the Qwen second-to-last token vector.
- [x] Red: add Qwen routing test using `CoordinationHead.route/5`.
- [x] Green: route from the Qwen vector with real Axon logits.
- [ ] Red: add demo profile option test or command-level smoke check.
- [ ] Green: implement `mix trinity.demo --profile qwen`.
- [x] Update README, this guide, and HexDocs extras for the eventual demo
      command.

## Required Tests

Add tests in this order.

Keep these as checklist items in the implementation PR and revise them if the
resolved Bumblebee/Qwen API changes.

### 1. Profile metadata test

Fast, no network:

```elixir
test "qwen profile declares production metadata" do
  profile = TrinityCoordinator.SLMProfile.qwen_coordinator()

  assert profile.name == :qwen_coordinator
  assert match?({:hf, _}, profile.repo)
  assert is_atom(profile.module)
  assert profile.architecture == :base
  assert profile.expected_hidden_size == 1024
end
```

### 2. Model load integration test

Networked and GPU-backed:

```elixir
@tag :integration
@tag :qwen
test "loads the production Qwen coordinator profile" do
  Runtime.put_cuda_backend!()
  profile = SLMProfile.qwen_coordinator()

  assert {:ok, {model_info, tokenizer}} = SLMProfile.load_profile(profile)
  assert is_map(model_info)
  assert tokenizer != nil
end
```

### 3. Hidden-state extraction integration test

```elixir
@tag :integration
@tag :qwen
test "extracts Qwen second-to-last token vector on CUDA" do
  Runtime.put_cuda_backend!()
  profile = SLMProfile.qwen_coordinator()
  {:ok, {model_info, tokenizer}} = SLMProfile.load_profile(profile)

  assert {:ok, metadata} =
           Extractor.extract_penultimate_hidden_state_with_metadata(
             model_info,
             tokenizer,
             [%{role: "user", content: "Solve this problem carefully."}]
           )

  assert metadata.vector_shape == {1, profile.expected_hidden_size}
  assert Runtime.tensor_backend(metadata.vector) =~ "EXLA.Backend<cuda:"
end
```

### 4. Routing integration test

```elixir
@tag :integration
@tag :qwen
test "routes from a real Qwen hidden state" do
  Runtime.put_cuda_backend!()
  profile = SLMProfile.qwen_coordinator()
  {:ok, {model_info, tokenizer}} = SLMProfile.load_profile(profile)
  {:ok, metadata} = Extractor.extract_penultimate_hidden_state_with_metadata(...)

  model = CoordinationHead.build_model(profile.expected_hidden_size, 7, 3)
  {init_fn, _predict_fn} = Axon.build(model)
  params =
    init_fn.(
      Nx.template({1, profile.expected_hidden_size}, :f32),
      Axon.ModelState.empty()
    )

  route = CoordinationHead.route(model, params, metadata.vector, 7, 3)

  assert route.agent_id in 0..6
  assert route.role_id in 0..2
  assert Runtime.tensor_backend(route.logits) =~ "EXLA.Backend<cuda:"
end
```

### 5. Adapted runtime smoke test

```elixir
@tag :qwen_sakana_adapted
test "loads the adapted Qwen profile using persisted Sakana artifacts" do
  Runtime.put_cuda_backend!()

  assert {:ok, {model_info, _tokenizer}} = SLMProfile.load_profile(:qwen_sakana_adapted)
  assert is_map(model_info)
  assert model_info.spec.hidden_size == 1024
end
```

Run Qwen tests separately from normal integration tests:

```bash
XLA_TARGET=<cuda-target> mix test --only qwen
```

Do not put Qwen tests in the default integration set until runtime, download
size, and VRAM usage are acceptable for routine local verification.

## Required Demo Update

Add an option to the demo task rather than replacing the current tiny profile:

```bash
XLA_TARGET=<cuda-target> mix trinity.demo --profile qwen
```

Expected output must include:

- selected profile name,
- repository id,
- expected hidden size,
- observed vector shape,
- vector backend,
- feature backend,
- logits backend,
- route selection.

The demo must fail early with a clear message if:

- `XLA_TARGET` is not the profile's required target,
- CUDA is not visible,
- the tokenizer cannot load,
- the model cannot load,
- the observed hidden size differs from the profile metadata.

## Memory And Runtime Validation

Run these checks before merging:

```bash
nvidia-smi
XLA_TARGET=<cuda-target> mix run -e 'TrinityCoordinator.Runtime.put_cuda_backend!(); IO.inspect(EXLA.Client.get_supported_platforms())'
XLA_TARGET=<cuda-target> mix test --only qwen --trace
XLA_TARGET=<cuda-target> mix trinity.demo --profile qwen
nvidia-smi
```

Record in the PR:

- GPU model.
- Driver version.
- CUDA target.
- Peak VRAM observed during model load.
- Peak VRAM observed during extraction.
- First-run compile time.
- Warm-run extraction time.
- Observed hidden-state shape.
- Observed second-to-last vector shape.

## Compaction Handoff

If context compaction occurs during Qwen profile work:

1. Re-read this guide.
2. Read the active profile checklist.
3. Run `git status --short`.
4. Inspect changed dependency, profile, extractor, demo, and test files.
5. Confirm the intended `XLA_TARGET`.
6. Run the smallest relevant profile or integration test.
7. Continue from the next unchecked checklist item.

Do not restart from the old tiny-profile baseline unless the checklist says the
current Qwen branch is invalid.

## Acceptance Criteria

Do not mark the roadmap item complete until all of the following are true:

- The selected Qwen repository loads from Bumblebee without local patches or
  undocumented monkey-patching.
- Tokenizer loading works through `Bumblebee.load_tokenizer/1`.
- Real extraction returns `{1, 1024}` or the documented expected hidden size.
- Extracted vector reports `EXLA.Backend<cuda:0>`.
- Coordination head builds from the observed hidden size.
- Routing logits report `EXLA.Backend<cuda:0>`.
- Existing tiny-profile tests still pass.
- Qwen tests pass when explicitly selected.
- `mix credo --strict`, `mix dialyzer`, and `mix docs` pass.
- README and HexDocs explain the profile, required `XLA_TARGET`, model id, and
  expected hardware footprint.

## Final Quality Gate

Run the full non-provider gate before merge:

```bash
XLA_TARGET=<cuda-target> mix format --check-formatted
XLA_TARGET=<cuda-target> mix test
XLA_TARGET=<cuda-target> mix test --only integration
XLA_TARGET=<cuda-target> mix credo --strict
XLA_TARGET=<cuda-target> mix dialyzer
XLA_TARGET=<cuda-target> mix docs
```

Run the Qwen-specific gate before marking the profile ready:

```bash
XLA_TARGET=<cuda-target> mix test --only qwen --trace
XLA_TARGET=<cuda-target> mix trinity.demo --profile qwen
```

Commit and push only after the relevant gates pass. If dependency work touches
dotfiles or host setup repos, QA and push those repos too.

## Non-Goals

Do not combine this work with:

- sep-CMA-ES training,
- provider-pool redesign,
- Qwen text generation,
- full paper reproduction,
- benchmark score claims.

The production profile is only the SLM encoder lane. It must prove reliable
hidden-state extraction and router compatibility first.

## Rollback Plan

If the Qwen lane breaks default development:

1. Keep `tiny_gpt2` as the default profile.
2. Move Qwen tests behind `@tag :qwen`.
3. Keep Qwen docs but mark the profile experimental.
4. Revert dependency upgrades if they destabilize the existing CUDA12 lane.
5. Open a follow-up branch for Qwen implementation support rather than carrying
   a partially working profile on `main`.
