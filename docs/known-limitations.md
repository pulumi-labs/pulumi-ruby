# Known limitations

What the Ruby support does not do yet, and why. Each entry is tracked work rather than a
design decision; the design decisions live in the README.

## SDK generation

`pulumi package gen-sdk --language ruby` produces a gem whose resources are named classes
with declared properties, so a misspelled property raises at the call rather than being
sent to the provider.

It covers resources. Not yet generated:

- **Functions (invokes).** A provider's `getSomething` functions have no bindings, so a
  program needing one falls back to `Pulumi.invoke` with a raw token. This is the largest
  single gap, and the largest group of remaining conformance failures.
- **Enums**, which should become modules of constants.
- **Object types**, which are currently passed as plain hashes rather than typed args.
- **RBS signatures** for generated types.

A resource whose schema is not available still works through its type token:

```ruby
Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "assets", { acl: "private" })
```

## Program generation

`pulumi convert --language ruby` works for the subset of PCL the generator covers.
Component and hook declarations are not translated, nor are several builtins; each gap is
named in `expectedFailures` in `pulumi-language-ruby/language_test.go` alongside the test
it blocks. See [Conformance](../README.md#conformance).

## Not yet implemented in the SDK

- Resource transforms and hooks.
- Provider authoring, so a component written in Ruby can be consumed from another language.
- The Automation API.
- Dynamic providers, which need a way to serialize a Ruby closure into state.

## Platform support

CRuby only, on Ruby 3.3 or later. JRuby and TruffleRuby are unsupported because the `grpc`
gem publishes no build for them.
