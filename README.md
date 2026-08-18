# Pulumi for Ruby

Infrastructure as code in real Ruby. Define cloud resources with ordinary classes,
methods and blocks; deploy them with the Pulumi CLI.

> **Experimental.** This lives in Pulumi Labs: no promises of maintenance, stability or
> security, but community involvement is welcome, and projects with enough interest can
> graduate to full support.
>
> The core SDK, the language host, and both generators work end to end — you can
> `pulumi up` a Ruby program against real providers today, generate an SDK for one with
> `pulumi package gen-sdk --language ruby`, and convert a program with
> `pulumi convert --language ruby`. Both generators cover a subset of the schema and PCL
> surface; see [known limitations](docs/known-limitations.md) and the
> [roadmap](#roadmap).

Ruby is the most-requested language in
[pulumi/pulumi#132](https://github.com/pulumi/pulumi/issues/132) by a wide margin. Much of
that demand comes from people who learned to describe infrastructure in Ruby with Chef and
never got a successor. Chef lost ground for reasons that had little to do with Ruby —
agent-and-server topology against Ansible's agentless SSH, imperative convergence against
Terraform's plan/apply over real state — and Ruby was collateral damage.

So this SDK is not a Chef DSL port. It aims to keep what made Chef pleasant and drop what
made it painful, which turns out to be mostly a matter of *not* rebuilding things Pulumi's
architecture makes unnecessary.

## Hello, world

```ruby
# main.rb
require "pulumi"

config = Pulumi.config
size = config.get_integer("length") || 3

pet = Pulumi::CustomResource.new(
  "random:index/randomPet:RandomPet", "pet", { length: size }
)

Pulumi.export "name", pet.output("id")
Pulumi.export "greeting", pet.output("id").apply { |name| "hello, #{name}!" }
```

```yaml
# Pulumi.yaml
name: hello-ruby
runtime: ruby
```

```ruby
# Gemfile
source "https://rubygems.org"

# Nothing is published yet, so point at your checkout.
gem "pulumi", path: "../pulumi-ruby/sdk/ruby"
```

Nothing is published, so build the language host and put it on `PATH` first:

```console
$ git clone https://github.com/pulumi-labs/pulumi-ruby
$ (cd pulumi-ruby && make build_language_host)
$ export PATH="$PWD/pulumi-ruby/pulumi-language-ruby:$PATH"

$ cp -r pulumi-ruby/templates/ruby my-demo && cd my-demo
```

Fill in `${PROJECT}` and `${DESCRIPTION}` in `Pulumi.yaml`, then:

```console
$ pulumi stack init dev
$ pulumi install
$ pulumi up
Outputs:
    greeting: "hello, wrongly-amusing-cub!"
    name    : "wrongly-amusing-cub"
```

## Three ways to declare a resource

All three produce the same call. Which you use is a matter of taste; the first is what the
docs and generated code use.

```ruby
# 1. Keyword-style arguments.
Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "assets",
  { acl: "private", versioning: { enabled: true } })

# 2. A block with an explicit receiver -- Ruby's `yield self` idiom.
Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "assets") do |b|
  b.acl = "private"
  b.versioning = { enabled: true }
end

# 3. A block without one, for those coming from Chef.
Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "assets") do
  acl "private"
  versioning enabled: true
end
```

Form 3 looks like `instance_eval`, but isn't quite. A bare `instance_eval` replaces `self`
inside the block, so instance variables silently resolve to `nil` and calls to the caller's
own methods raise `NameError` — two of the sharper edges in real cookbooks. Here the block
runs against a proxy that forwards anything the resource doesn't answer back to the scope
the block was written in, so this works:

```ruby
class Stack
  def initialize = @env = "prod"
  def tag_prefix = "acme"

  def bucket
    region = "us-west-2"
    Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "assets") do
      acl "private"
      tags({ env: @env, prefix: tag_prefix, region: region })   # all three resolve
    end
  end
end
```

The proxy is a blank slate rather than a plain object, because properties are allowed to be
named `hash`, `method` or `class`, and inherited methods would otherwise swallow them.

**The honest cost:** `ruby-lsp` cannot complete inside form 3, because `self` is
unknowable there. Forms 1 and 2 complete and type-check normally. Once generated SDKs land,
form 1 also catches typos for free — `ArgumentError: unknown property :verisoning` — because
each resource declares its properties.

## Outputs

Values a provider computes don't exist while your program runs. They're represented as
`Pulumi::Output`, and you reach inside one with `apply`:

```ruby
bucket.output("website_endpoint").apply { |endpoint| "https://#{endpoint}" }

Pulumi::Output.all(bucket.id, key).apply { |(id, k)| "#{id}/#{k}" }
Pulumi::Output.format("https://%s/%s", bucket.output("endpoint"), key)
Pulumi::Output.secret(token)
Pulumi::Output.json_dump({ "arn" => role.output("arn") })
```

During a `pulumi preview` these values are *unknown*: the block does not run, and the
result stays unknown. That's what lets a preview complete without inventing values.

One syntax note: with `Pulumi.export`, braces bind the block to `apply` as intended, but
`do...end` would bind it to `export` instead. That mistake fails loudly rather than
silently — `apply` requires a block — but parenthesizing avoids the question:

```ruby
Pulumi.export("url", bucket.output("arn").apply { |arn| "https://#{arn}" })
```

There is deliberately no way to read an Output synchronously, and `"#{output}"` will warn
loudly rather than interpolate — use `Output.format`. `Output` also deliberately does not
implement Ruby's implicit conversion protocol (`to_str`, `to_ary`, `to_hash`, `to_proc`,
`to_int`), so misuse produces Ruby's own clear message:

```
TypeError: no implicit conversion of Pulumi::Output into String
```

rather than the baffling one you get if a type answers `to_str` with something that isn't a
String.

## Components

Subclass `ComponentResource` to package infrastructure. This is the shape Chef's custom
resources had — a reusable unit with inputs and outputs — with plain Ruby instead of a
`provides`/`action` DSL:

```ruby
class VpcWithSubnets < Pulumi::ComponentResource
  attr_reader :vpc_id, :subnet_ids

  def initialize(name, cidr:, azs:, opts: nil)
    super("myorg:net:VpcWithSubnets", name, {}, opts)
    child = Pulumi::ResourceOptions.new(parent: self)

    vpc = Pulumi::CustomResource.new(
      "aws:ec2/vpc:Vpc", "#{name}-vpc", { cidr_block: cidr }, child)

    @vpc_id = vpc.id
    @subnet_ids = azs.each_with_index.map do |az, i|
      Pulumi::CustomResource.new(
        "aws:ec2/subnet:Subnet", "#{name}-subnet-#{i}",
        { vpc_id: vpc.id, availability_zone: az }, child).id
    end

    register_outputs(vpc_id: @vpc_id, subnet_ids: @subnet_ids)
  end
end
```

## Testing

Unit tests run your program against a fake engine, through the real serialization path:

```ruby
require "pulumi"

class MyMocks < Pulumi::Testing::Mocks
  def new_resource(args)
    ["#{args.name}-id", args.inputs.merge("arn" => "arn:fake:#{args.name}")]
  end
end

RSpec.describe "my infrastructure" do
  it "makes the bucket private" do
    result = Pulumi::Testing.run(MyMocks.new) do
      Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "assets", { acl: "private" })
    end

    expect(result.resource("assets").inputs).to eq({ "acl" => "private" })
  end

  it "derives the URL from the endpoint" do
    result = Pulumi::Testing.run(MyMocks.new) do
      bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "assets", {})
      Pulumi.export "url", bucket.output("arn").apply { |a| "https://#{a}" }
    end

    expect(Pulumi::Testing.value(result.exports["url"])).to eq("https://arn:fake:assets")
  end
end
```

Only the provider is faked. Everything else — property serialization, unknowns, secrets,
dependency tracking, component parenting — is the same code a real deployment runs.
ChefSpec, by contrast, executed recipes "with all the resource actions disabled", which is
why the community called it *intention testing*: a green test told you what the code meant
to do, not whether it worked. Set `dry_run: true` to simulate a preview and assert that
values are correctly unknown.

## What this deliberately does not have

Each of these was a well-documented problem in Chef, and each is unnecessary here rather
than merely omitted.

| Not here | Why |
|---|---|
| A compile/converge split, `lazy {}`, `ruby_block` | Pulumi has one phase. A program runs top to bottom exactly once, and deferral is expressed by the dependency graph Outputs describe. `lazy` existed only to paper over a phase boundary that doesn't exist here. |
| Attribute precedence levels | Chef's docs admit to "up to 15 different competing values". Config here has one source — what `pulumi config set` recorded for the stack — and is read-only. |
| A global mutable `node` | Ambient state is write-once, installed before the program runs. "Where did this value come from?" stays answerable. |
| `set_or_return` dual-purpose accessors | Properties are generated from a declaration, so the read and write spellings cannot drift apart. Chef migrated away from hand-written ones itself. |
| Monkey-patching core classes | No `String#to_output`. Ruby infrastructure code usually lives next to Rails; the SDK must coexist with ActiveSupport and never walk host-application objects. |
| Refinements | Lexically scoped, poorly supported by tooling. |

## Requirements

- **Ruby 3.3+** (CRuby). The `grpc` gem ships precompiled binaries for Linux, macOS and
  Windows, so no compiler is needed. JRuby is not supported — `grpc` has no JRuby build.
- **Bundler**, if your project has a `Gemfile` (recommended).
- **Pulumi CLI** 3.x.

## Repository layout

```
sdk/ruby/                 the `pulumi` gem
  lib/pulumi/             Output, Resource, Config, Args, ...
  lib/pulumi/runtime/     the engine-facing half: rpc, settings, stack
  exe/                    pulumi-language-ruby-exec, the program entry point
  sig/                    RBS signatures
  spec/
pulumi-language-ruby/     the language host plugin (Go), and the conformance suite
templates/ruby/           what a new Ruby project starts from
examples/                 runnable programs
docs/                     known limitations
scripts/sync-protos.sh    regenerates the gRPC bindings from pulumi/pulumi
```

## Development

```console
$ mise install       # Ruby, Go, golangci-lint, changie, protoc
$ make build         # gem dependencies, plus the language host binary
$ make test_fast     # specs, types, host unit tests -- no network
$ make test_all      # the above plus conformance
$ make lint          # golangci-lint, go vet, RuboCop
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the rest, including how to run a single
conformance test and how to regenerate its snapshots.

## Roadmap

Done:

- The language host (all 17 `LanguageRuntime` RPCs; code generation reports
  `Unimplemented`)
- `Output` with unknowns, secrets and dependency tracking
- Property serialization, including assets, archives, resource references, output values
  and non-UTF-8 byte strings
- Resource registration, components, config, logging, stack outputs
- Resource options: parent, `depends_on` (expanded through components), aliases, protect,
  ignore_changes, custom timeouts, import
- Unit-testing mocks, including a `dry_run: true` mode that reproduces the engine's
  preview semantics rather than resolving values a real preview could not
- Provider function invokes (`Pulumi.invoke`) and stack references
- RBS signatures in `sig/`, with a sample program type-checked by Steep in CI
- Program generation: `pulumi convert --language ruby`, and generated programs for the
  conformance suite
- SDK generation: `pulumi package gen-sdk --language ruby`, producing a gem whose resources
  are named classes with declared properties

Next:

- **Invokes** — provider functions, the largest group of remaining conformance failures.
- Enums, object types and RBS signatures in generated SDKs.
- Components and hooks in programgen; the rest of the gaps named in `expectedFailures`.
- Resource transforms and hooks.
- Provider authoring, so a component written in Ruby can be consumed from another language.
- Automation API.

## Conformance

Pulumi has a cross-language conformance suite: the same programs, the same test providers,
and the same assertions about resulting state, run against every language runtime. It is
the specification a runtime is held to, and it runs against the real engine — packing the
SDK, installing it, and performing actual deployments.

```console
$ make test_conformance
$ make test_conformance TEST_FILTER=l1-empty   # just one
$ make accept                                  # regenerate snapshots after a codegen change
```

**29 of 179 tests pass today**, against SDKs and programs this repository generates.
Nothing is skipped by category: every remaining test is named in `expectedFailures` in
`pulumi-language-ruby/language_test.go` with the construct that blocks it, so the size of
that map is exactly the remaining work.

The largest group of the 150 outstanding is invokes — provider functions, which need
sdkgen to emit their bindings — followed by component and hook declarations in programgen.

## License## License

Apache 2.0. See [LICENSE](LICENSE).
