# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::Runtime::RPC do
  # Signatures come from spec/support so they stay literals independent of lib/.
  let(:wire) { Pulumi::Spec::WireFormat }

  # Serializing produces protobuf objects; comparing them as plain Ruby is far more
  # legible than comparing nested Google::Protobuf::Value trees.
  def serialize(value, **options)
    result = described_class.serialize_value(value, described_class::Options.default(**options))
    [result.value.nil? ? nil : to_ruby(result.value), result.resources]
  end

  def to_ruby(protobuf_value)
    case protobuf_value.kind
    when :null_value then nil
    when :bool_value then protobuf_value.bool_value
    when :number_value then protobuf_value.number_value
    when :string_value then protobuf_value.string_value
    when :list_value then protobuf_value.list_value.values.map { |v| to_ruby(v) }
    when :struct_value
      protobuf_value.struct_value.fields.each_with_object({}) { |(k, v), h| h[k] = to_ruby(v) }
    end
  end

  def unknown_output(secret: false)
    Pulumi::Output.new(
      Concurrent::Promises.fulfilled_future(Pulumi::Output::Data.unknown(secret: secret))
    )
  end

  describe "serializing scalars" do
    it "encodes primitives" do
      expect(serialize("hello").first).to eq("hello")
      expect(serialize(42).first).to eq(42.0)
      expect(serialize(1.5).first).to eq(1.5)
      expect(serialize(true).first).to be(true)
      expect(serialize(nil).first).to be_nil
    end

    it "encodes symbols as strings, since the wire has no symbol type" do
      expect(serialize(:private).first).to eq("private")
    end

    it "encodes arrays and hashes structurally" do
      expect(serialize([1, "two"]).first).to eq([1.0, "two"])
      expect(serialize({ a: 1, "b" => 2 }).first).to eq({ "a" => 1.0, "b" => 2.0 })
    end
  end

  describe "serializing Outputs" do
    it "unwraps a known Output to its plain value" do
      expect(serialize(Pulumi::Output.from("v")).first).to eq("v")
    end

    it "encodes an unknown Output as the sentinel" do
      expect(serialize(unknown_output).first).to eq(wire::UNKNOWN)
    end

    it "wraps a secret Output in the secret signature" do
      expect(serialize(Pulumi::Output.secret("s")).first).to eq(
        wire::SIG_KEY => wire::SECRET, "value" => "s"
      )
    end

    it "sends secrets in the clear when the receiver cannot handle them" do
      expect(serialize(Pulumi::Output.secret("s"), keep_secrets: false).first).to eq("s")
    end

    it "keeps a secret marker on an unknown value" do
      encoded, = serialize(unknown_output(secret: true))
      expect(encoded).to eq(wire::SIG_KEY => wire::SECRET, "value" => wire::UNKNOWN)
    end
  end

  describe "output values" do
    it "carries known values with their signature" do
      encoded, = serialize(Pulumi::Output.from("v"), keep_output_values: true)
      expect(encoded).to eq(wire::SIG_KEY => wire::OUTPUT_VALUE, "value" => "v")
    end

    # Absence of "value" is how the wire format spells unknown. A present null would mean
    # something different -- known, and null.
    it "omits the value entirely when unknown" do
      encoded, = serialize(unknown_output, keep_output_values: true)
      expect(encoded).to eq(wire::SIG_KEY => wire::OUTPUT_VALUE)
      expect(encoded).not_to have_key("value")
    end

    it "marks secrets" do
      encoded, = serialize(Pulumi::Output.secret("s"), keep_output_values: true)
      expect(encoded).to eq(wire::SIG_KEY => wire::OUTPUT_VALUE, "value" => "s", "secret" => true)
    end
  end

  describe "assets and archives" do
    it "encodes each asset flavour by its distinguishing field" do
      expect(serialize(Pulumi::FileAsset.new("./f")).first).to eq(wire::SIG_KEY => wire::ASSET, "path" => "./f")
      expect(serialize(Pulumi::StringAsset.new("hi")).first).to eq(wire::SIG_KEY => wire::ASSET, "text" => "hi")
      expect(serialize(Pulumi::RemoteAsset.new("https://x")).first).to eq(wire::SIG_KEY => wire::ASSET, "uri" => "https://x")
    end

    it "encodes archives, including nested assets" do
      archive = Pulumi::AssetArchive.new("index.html" => Pulumi::StringAsset.new("<p>"))
      expect(serialize(archive).first).to eq(
        wire::SIG_KEY => wire::ARCHIVE,
        "assets" => { "index.html" => { wire::SIG_KEY => wire::ASSET, "text" => "<p>" } }
      )
    end

    it "round-trips an asset archive" do
      archive = Pulumi::AssetArchive.new("a" => Pulumi::FileAsset.new("./a"))
      encoded = described_class.serialize_value(archive).value
      decoded = described_class.deserialize_value(encoded)

      expect(decoded).to be_a(Pulumi::AssetArchive)
      expect(decoded.assets["a"]).to be_a(Pulumi::FileAsset)
      expect(decoded.assets["a"].path).to eq("./a")
    end
  end

  describe "resource references" do
    # A stand-in for a resource: the serializer identifies resources by capability
    # (#urn/#custom?) so that resource.rb can depend on rpc.rb and not the reverse.
    let(:custom_resource) do
      Pulumi::Spec::FakeResource.new(urn: "urn:pulumi:s::p::t::n", id: "id-1")
    end

    let(:component_resource) do
      Pulumi::Spec::FakeResource.new(urn: "urn:pulumi:s::p::c::n", custom: false)
    end

    it "encodes a custom resource with its urn and id" do
      encoded, = serialize(custom_resource)
      expect(encoded).to eq(
        wire::SIG_KEY => wire::RESOURCE_REFERENCE, "urn" => "urn:pulumi:s::p::t::n", "id" => "id-1"
      )
    end

    it "omits the id for a component resource" do
      encoded, = serialize(component_resource)
      expect(encoded).to eq(wire::SIG_KEY => wire::RESOURCE_REFERENCE, "urn" => "urn:pulumi:s::p::c::n")
    end

    it "records the resource as a dependency" do
      _, resources = serialize(custom_resource)
      expect(resources).to eq([custom_resource])
    end

    # Call and Construct pass dependencies through the output value's own dependency
    # list, so counting the reference again would double-report it.
    it "omits the dependency when asked to exclude resource refs" do
      _, resources = serialize(custom_resource, exclude_resource_refs_from_deps: true)
      expect(resources).to be_empty
    end

    it "falls back to a bare id when the receiver has no resource references" do
      encoded, = serialize(custom_resource, keep_resources: false)
      expect(encoded).to eq("id-1")
    end

    it "falls back to a bare urn for components when the receiver has no references" do
      encoded, = serialize(component_resource, keep_resources: false)
      expect(encoded).to eq("urn:pulumi:s::p::c::n")
    end
  end

  describe "byte strings" do
    let(:invalid_utf8) { (+"\xff\xfe binary").force_encoding(Encoding::BINARY) }

    it "encodes non-UTF-8 bytes behind the byte string signature" do
      encoded, = serialize(invalid_utf8, keep_byte_string: true)
      expect(encoded[wire::SIG_KEY]).to eq(wire::BYTE_STRING)
      expect(encoded["value"].unpack1("m")).to eq(invalid_utf8)
    end

    it "refuses rather than corrupting when the receiver cannot accept them" do
      expect { serialize(invalid_utf8, keep_byte_string: false) }
        .to raise_error(Pulumi::Error, /not valid UTF-8/)
    end

    # Ruby's BINARY encoding just means "no encoding declared". Bytes that happen to be
    # valid UTF-8 should travel as an ordinary string rather than being base64'd.
    it "sends BINARY strings that are valid UTF-8 as plain strings" do
      binary = (+"plain ascii").force_encoding(Encoding::BINARY)
      expect(serialize(binary, keep_byte_string: true).first).to eq("plain ascii")
    end

    it "transcodes other encodings rather than reinterpreting their bytes" do
      latin1 = (+"caf\xe9").force_encoding(Encoding::ISO_8859_1)
      expect(serialize(latin1).first).to eq("café")
    end

    it "round-trips through deserialization" do
      encoded = described_class.serialize_value(
        invalid_utf8, described_class::Options.default(keep_byte_string: true)
      ).value
      expect(described_class.deserialize_value(encoded)).to eq(invalid_utf8)
    end
  end

  describe "serialize_properties" do
    let(:resource) { Pulumi::Spec::FakeResource.new(urn: "urn:a", id: "i") }

    it "reports per-property dependencies" do
      struct, deps = described_class.serialize_properties({ ref: resource, plain: 1 })

      expect(struct.fields.keys).to contain_exactly("ref", "plain")
      expect(deps).to eq({ "ref" => [resource] })
    end

    # Providers distinguish "unset" from "explicitly null"; sending null for an omitted
    # property would diff against the absent value the provider already has. A previous
    # version of this test passed no nil at all and so asserted nothing.
    it "omits top-level properties that are nil" do
      struct, = described_class.serialize_properties({ present: 1, absent: nil })
      expect(struct.fields.keys).to eq(["present"])
    end

    # Inside a nested object a nil is part of the value's shape rather than an unset
    # property, so it is sent explicitly. This matches the other SDKs.
    it "keeps nils inside nested objects" do
      struct, = described_class.serialize_properties({ nested: { a: nil, b: 1 } })
      expect(struct.fields["nested"].struct_value.fields.keys).to contain_exactly("a", "b")
    end

    # By contrast a nil inside a list must be preserved: dropping it would change the
    # list's length and shift every later index.
    it "keeps nils inside arrays" do
      struct, = described_class.serialize_properties({ list: [1, nil, 3] })
      expect(to_ruby(struct.fields["list"])).to eq([1.0, nil, 3.0])
    end
  end

  describe "deserializing" do
    def deserialize(ruby_hash)
      described_class.deserialize_value(
        described_class.serialize_value(ruby_hash).value
      )
    end

    it "narrows whole numbers back to Integer" do
      # protobuf carries only doubles, so `count == 3` would otherwise be false.
      expect(deserialize({ "n" => 3 })["n"]).to be_an(Integer).and eq(3)
      expect(deserialize({ "n" => 3.5 })["n"]).to be_a(Float).and eq(3.5)
    end

    it "leaves numbers beyond exact integer precision as floats" do
      big = (2**53) + 2.0
      expect(deserialize({ "n" => big })["n"]).to be_a(Float)
    end

    it "turns the unknown sentinel into a distinct marker, not nil" do
      value = Google::Protobuf::Value.new(string_value: wire::UNKNOWN)
      expect(described_class.deserialize_value(value)).to be(described_class::UNKNOWN_VALUE)
      expect(described_class.deserialize_value(value)).not_to be_nil
    end

    it "detects unknowns nested inside structures" do
      unknown = described_class::UNKNOWN_VALUE
      expect(described_class.contains_unknown?(unknown)).to be(true)
      expect(described_class.contains_unknown?([1, { "a" => unknown }])).to be(true)
      expect(described_class.contains_unknown?([1, { "a" => 2 }])).to be(false)
    end

    # Deserialization yields plain data plus markers, never Outputs. An Output is opaque,
    # so building one here would hide a nested unknown from contains_unknown? -- see the
    # "secret unknowns" group below.
    it "restores a secret as an inspectable marker, not an Output" do
      encoded = described_class.serialize_value(Pulumi::Output.secret("s")).value
      decoded = described_class.deserialize_value(encoded)

      expect(decoded).to be_a(described_class::Secret)
      expect(decoded.value).to eq("s")
      expect(described_class.contains_secret?(decoded)).to be(true)
      expect(described_class.unwrap_secrets(decoded)).to eq("s")
    end

    it "round-trips a secret marker back onto the wire" do
      marker = described_class::Secret.new(value: "s")
      encoded = described_class.serialize_value(marker).value

      expect(described_class.deserialize_value(encoded)).to eq(marker)
    end
  end

  # The engine sends secret(unknown) for a secret property during a preview -- Go builds
  # it as MakeSecret(MakeComputed(...)) in sdk/go/common/resource/plugin/rpc.go. Treating
  # that as known let applies run against the sentinel and bake it into other resources.
  describe "secret unknowns" do
    def secret_of(inner)
      described_class.deserialize_value(
        Google::Protobuf::Value.new(struct_value: Google::Protobuf::Struct.new(fields: {
                                                                                 Pulumi::Spec::WireFormat::SIG_KEY =>
          Google::Protobuf::Value.new(string_value: Pulumi::Spec::WireFormat::SECRET),
                                                                                 "value" => inner
                                                                               }))
      )
    end

    it "sees the unknown through the secret marker" do
      value = secret_of(Google::Protobuf::Value.new(string_value: Pulumi::Spec::WireFormat::UNKNOWN))

      expect(described_class.contains_unknown?(value)).to be(true)
      expect(described_class.contains_secret?(value)).to be(true)
    end

    it "sees an unknown nested inside a secret structure" do
      unknown = Google::Protobuf::Value.new(string_value: Pulumi::Spec::WireFormat::UNKNOWN)
      inner = Google::Protobuf::Value.new(
        struct_value: Google::Protobuf::Struct.new(fields: { "arn" => unknown })
      )

      expect(described_class.contains_unknown?(secret_of(inner))).to be(true)
    end

    it "sees an unknown inside an output value" do
      fields = {
        Pulumi::Spec::WireFormat::SIG_KEY =>
          Google::Protobuf::Value.new(string_value: Pulumi::Spec::WireFormat::OUTPUT_VALUE),
        "secret" => Google::Protobuf::Value.new(bool_value: true)
      }
      value = described_class.deserialize_value(
        Google::Protobuf::Value.new(struct_value: Google::Protobuf::Struct.new(fields: fields))
      )

      expect(described_class.contains_unknown?(value)).to be(true)
      expect(described_class.contains_secret?(value)).to be(true)
    end

    it "rejects an unrecognized signature rather than silently treating it as an object" do
      value = Google::Protobuf::Value.new(
        struct_value: Google::Protobuf::Struct.new(
          fields: { wire::SIG_KEY => Google::Protobuf::Value.new(string_value: "nope") }
        )
      )
      expect { described_class.deserialize_value(value) }
        .to raise_error(Pulumi::Error, /unrecognized signature/)
    end
  end

  # Google::Protobuf::Map looks enough like a Hash to invite `fields.to_h { ... }`, but it
  # discards the block and returns raw protobuf values -- silently producing wrong data.
  # This pins the behaviour so that if google-protobuf ever fixes it, we find out here
  # rather than wondering why map_fields exists.
  describe "protobuf map conversion hazard" do
    let(:fields) do
      Google::Protobuf::Struct.new(
        fields: { "a" => Google::Protobuf::Value.new(string_value: "x") }
      ).fields
    end

    it "still ignores a block passed to #to_h" do
      converted = fields.to_h { |k, _v| [k, "converted"] }
      expect(converted["a"]).not_to eq("converted")
    end

    # It also lacks #key?, which Hash has -- another way the duck-typing breaks down.
    it "responds to has_key? but not key?" do
      expect(fields).to respond_to(:has_key?)
      expect(fields).not_to respond_to(:key?)
    end

    it "deserializes nested structs correctly despite that" do
      nested = described_class.serialize_value({ "outer" => { "inner" => "v" } }).value
      expect(described_class.deserialize_value(nested)).to eq({ "outer" => { "inner" => "v" } })
    end
  end

  describe "error handling" do
    it "surfaces an exception raised inside an apply with its own message" do
      output = Pulumi::Output.from(1).apply { raise "user code blew up" }
      expect { serialize(output) }.to raise_error(RuntimeError, "user code blew up")
    end

    it "refuses to serialize a type it has no encoding for" do
      expect { serialize(Object.new) }.to raise_error(Pulumi::Error, /cannot serialize/)
    end
  end
end
