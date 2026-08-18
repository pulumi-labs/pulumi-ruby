# frozen_string_literal: true

require "spec_helper"

# The generated protobuf bindings are checked in, so a broken regeneration would
# otherwise only surface at deploy time. These assert the tree loads standalone (no
# $LOAD_PATH games) and that the messages the SDK depends on most actually round-trip.
RSpec.describe Pulumirpc do
  it "loads without polluting the global load path" do
    expect($LOAD_PATH.grep(%r{runtime/proto})).to be_empty
  end

  it "round-trips a RegisterResourceRequest" do
    request = Pulumirpc::RegisterResourceRequest.new(
      type: "aws:s3/bucket:Bucket",
      name: "assets",
      custom: true,
      object: Google::Protobuf::Struct.from_hash({ "acl" => "private" }),
      dependencies: ["urn:pulumi:dev::proj::pulumi:pulumi:Stack::proj-dev"]
    )

    decoded = Pulumirpc::RegisterResourceRequest.decode(
      Pulumirpc::RegisterResourceRequest.encode(request)
    )

    expect(decoded.type).to eq("aws:s3/bucket:Bucket")
    expect(decoded.name).to eq("assets")
    expect(decoded.custom).to be(true)
    expect(decoded.object.to_h).to eq({ "acl" => "private" })
    expect(decoded.dependencies.to_a).to eq(
      ["urn:pulumi:dev::proj::pulumi:pulumi:Stack::proj-dev"]
    )
  end

  it "exposes the service stubs the SDK speaks" do
    expect(defined?(Pulumirpc::ResourceMonitor::Stub)).to eq("constant")
    expect(defined?(Pulumirpc::Engine::Stub)).to eq("constant")
  end

  # runtime/proto.rb loads only what the SDK actually talks to, so that every Pulumi
  # program does not pay startup cost for the language host's protocol. This pins that:
  # a service the SDK does not speak should not be loaded just because it was generated.
  it "does not load services the SDK has no use for" do
    expect(defined?(Pulumirpc::LanguageRuntime)).to be_nil
    expect(defined?(Pulumirpc::Callbacks)).to be_nil
  end

  # The engine negotiates capabilities up front via GetDeploymentInfo; if these enum
  # values drift, feature detection silently degrades rather than failing loudly.
  it "carries the resource monitor feature enum" do
    features = Pulumirpc::ResourceMonitorFeature.constants
    expect(features).to include(:RESOURCE_MONITOR_FEATURE_SECRETS)
    expect(features).to include(:RESOURCE_MONITOR_FEATURE_OUTPUT_VALUES)
    expect(features).to include(:RESOURCE_MONITOR_FEATURE_BYTE_STRING)
  end
end
