# Known limitations

What the Ruby support does not do yet, and why. Each entry is tracked work rather than a
design decision; the design decisions live in the README.

## SDK generation

`pulumi package gen-sdk --language ruby` is not implemented. Providers are reached through
their type token instead:

```ruby
Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "assets", { acl: "private" })
```

This works against any provider, but gives up the two things a generated SDK buys: named
classes with declared properties (so a misspelled property raises rather than being sent to
the provider), and RBS signatures for those properties.

## Program generation

`pulumi convert --language ruby` is not implemented, so an existing program in another
language cannot be converted to Ruby.

The same gap limits the conformance suite: without generated programs there is nothing for
most tests to run, so they are skipped rather than failed. The tests that do run use
hand-written programs under `pulumi-language-ruby/testdata/overrides`. See
[Conformance](../README.md#conformance).

## Not yet implemented in the SDK

- Resource transforms and hooks.
- Provider authoring, so a component written in Ruby can be consumed from another language.
- The Automation API.
- Dynamic providers, which need a way to serialize a Ruby closure into state.

## Platform support

CRuby only, on Ruby 3.3 or later. JRuby and TruffleRuby are unsupported because the `grpc`
gem publishes no build for them.
