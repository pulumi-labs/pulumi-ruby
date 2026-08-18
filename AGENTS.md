# Agent Instructions

## What this repo is

Ruby support for Pulumi: a Ruby gem (`sdk/ruby`) and a Go language host plugin
(`pulumi-language-ruby`) that the Pulumi CLI launches to run Ruby programs.

Experimental, in Pulumi Labs. Nothing is published yet.

## Repo structure

- `sdk/ruby/` — the `pulumi` gem. `lib/pulumi/` is the user-facing API; `lib/pulumi/runtime/`
  is the engine-facing half (gRPC, serialization, resource registration). `sig/` holds RBS.
- `pulumi-language-ruby/` — the Go language host. Implements `pulumirpc.LanguageRuntime`.
  Conformance lives here too, in `language_test.go` with `testdata/`.
- `templates/ruby/` — what a new Ruby project starts from.
- `proto/` — synced from pulumi/pulumi; the generated Ruby is checked in, the `.proto`
  sources are not.

## Command canon

All commands assume the repo root. Prefix with `mise exec --` if mise is not activated.

- **Build:** `make build`
- **Fast tests (run before pushing):** `make test_fast`
- **Everything:** `make test_all`
- **One conformance test:** `make test_conformance TEST_FILTER=l1-empty`
- **Regenerate conformance snapshots:** `make accept`
- **Lint:** `make lint` — **Format:** `make format`
- **Changelog fragment:** `make changelog`

## Key invariants

- **Never read ambient runtime state from inside an async continuation.** Resource
  registration runs on a worker thread long after the program body finished and
  `Runtime.settings` was torn down. Anything a continuation needs — the parent, the dry-run
  flag — is captured at construction. This bug has been introduced twice.
- **Deserialization produces plain data plus markers, never `Output`s.** An `Output` is
  opaque, so wrapping early hides a nested unknown from `contains_unknown?` and makes the
  engine's preview-time `secret(unknown)` look known. `Resource#derived_output` is the only
  place an `Output` is built.
- **`Output` must never answer Ruby's implicit conversion protocol** (`to_str`, `to_ary`,
  `to_hash`, `to_proc`, `to_int`). Answering them turns a clear `TypeError` into a baffling
  one.
- **`Google::Protobuf::Map` is not a `Hash`.** It silently ignores a block passed to
  `#to_h` and has no `#key?`. Every walk over a protobuf map goes through `RPC.map_fields`.
- **When a bug escapes the unit tests, suspect the mock first.** `Testing::MockMonitor` has
  twice been gentler than the engine — resolving values a preview cannot, and omitting a
  secret wrapper. Make the mock faithful, watch the existing spec fail, then fix the SDK.
- Copyright headers on new files use the current year.

## Escalate if

- A change alters the wire format or the `LanguageRuntime` surface.
- A change touches the public gem API (anything under `sdk/ruby/lib/pulumi/` not in
  `runtime/`).
- Conformance snapshots change in a way you cannot explain.
