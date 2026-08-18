# Contributing

## Getting set up

```console
$ mise install          # Ruby, Go, golangci-lint, changie, protoc
$ make build            # installs the gem's dependencies, builds the language host
```

`mise` is optional; without it, install the versions pinned in `.mise.toml` yourself.

## The test suites

| Command | What it covers | Needs |
|---|---|---|
| `make test_sdk` | RSpec unit tests for the gem | Ruby |
| `make test_types` | RBS validation and a Steep check of a sample program | Ruby |
| `make test_language_host` | Go unit tests for the host | Go |
| `make test_fast` | All three of the above | Ruby, Go |
| `make test_conformance` | Pulumi's cross-language conformance suite | Ruby, Go, network |

`make test_fast` is the set to run before pushing: no network, no provider plugins, a few
seconds. `make test_all` adds conformance.

To run one conformance test:

```console
$ make test_conformance TEST_FILTER=l1-empty
```

Conformance snapshots generated output. After a change to codegen, regenerate them with
`make accept` and review the diff — an unexplained change there is a bug, not a formality.

## Linting

```console
$ make lint             # golangci-lint + go vet + RuboCop
$ make format           # applies what can be applied automatically
```

The Go host and the Ruby SDK are linted by different tools: `.golangci.yml` only ever sees
`./pulumi-language-ruby`, and RuboCop only ever sees `./sdk/ruby`.

## Changelog

Every user-visible change needs a fragment:

```console
$ make changelog
```

This writes a YAML file under `.changes/unreleased`. Release batches them into
`CHANGELOG.md`.

## Regenerating the gRPC bindings

The generated Ruby protobuf code is checked in so that consumers of the gem never need
`protoc`. To regenerate it against a newer pulumi/pulumi:

```console
$ scripts/sync-protos.sh v3.256.0
$ USE_SIBLING=1 scripts/sync-protos.sh     # or, from a sibling checkout
```
