# trinity_coordinator

This repo is now a compatibility shim for
[trinity_framework](https://github.com/nshkrdotcom/trinity_framework). New work
goes there. This package will be retired after the next minor.

## Current Use

Existing consumers can keep the `:trinity_coordinator` dependency while moving
imports to `Trinity`, `Trinity.SingleNode`, and `mix trinity.*` tasks provided by
`trinity_framework` / `trinity_ops`.

The shim keeps:

- `TrinityCoordinator` facade delegates for the public framework entry points.
- Legacy metadata helpers used by older tests and docs.
- Deprecated `mix trinity.*` task modules that dispatch to `Trinity.Ops.Tasks`.

New integrations should depend on `:trinity_framework` directly.
