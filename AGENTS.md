# Repository Guidelines

## Project Structure
- `lib/` contains Trinity coordinator runtime modules and Mix tasks.
- `test/` contains ExUnit coverage; process-env mutation belongs only in tests.
- `examples/`, `guides/`, `docs/`, and `README.md` must stay aligned with task options and dependency-source behavior.
- `docs/priv/` is local/private/generated material and is not packaged.

## Dependency Sources
- Committed dependency tuples remain ordinary Hex requirements so standalone
  clones and published consumers work without workspace tooling. Managed
  development loads the MWO bootstrap and gets eligible source coordinates
  from Portfolio Registry; operator preferences stay outside this repository.
- MWO's process-scoped bootstrap pointer is the only dependency-management
  environment input read by `mix.exs`; publish mode remains Hex-only.
- Keep internal dependency declarations in `mix.exs`; do not add one-off
  path/Git resolver logic.

## Runtime Env
- Runtime application code under `lib/**` must not call direct OS env APIs such as `System.get_env`, `System.fetch_env`, `System.put_env`, or `System.delete_env`.
- Runtime/deployment env reads belong in `config/runtime.exs` or a `Config.Provider`.
- Mix tasks must accept explicit flags for provider gates and credentials instead of reading process env directly.
- Library APIs receive explicit options, config structs, application config materialized by the top-level app, or caller-supplied env maps.
- Tests may manipulate env only for config-boundary, live-gate, or compatibility checks.

## Gates
- Run `mix format`.
- Run `mix compile --warnings-as-errors`.
- Run `mix test`.
- Run `mix credo --strict`.
- Run `mix dialyzer`.
- Run `mix docs --warnings-as-errors`.
- Run `mix hex.build --unpack` when package files change, then remove the unpacked directory.
