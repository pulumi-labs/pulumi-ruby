# frozen_string_literal: true

require "spec_helper"

# A misspelled protobuf field raises only when the message is constructed -- which happens
# on a worker thread, mid-deployment, with a backtrace full of promise internals. That is
# an expensive way to find a typo.
#
# The proto's own field naming is inconsistent (acceptSecrets is camelCase, but the newer
# accepts_byte_string is snake_case), so the names cannot be derived by rule; they have to
# be spelled out and checked. These specs check them against the descriptor at test time.
RSpec.describe Pulumirpc::RegisterResourceRequest do
  # Every field lib/pulumi/runtime/resource.rb sets on a RegisterResourceRequest.
  let(:fields_used) do
    %w[
      type name custom object parent provider providers dependencies propertyDependencies
      acceptSecrets acceptResources accepts_byte_string supportsPartialValues
      supportsResultReporting protect version pluginDownloadURL ignoreChanges
      additionalSecretOutputs replaceOnChanges retainOnDelete importId deletedWith
      deleteBeforeReplace deleteBeforeReplaceDefined customTimeouts
    ]
  end

  it "defines every field the SDK sets" do
    defined_fields = described_class.descriptor.map(&:name)
    expect(defined_fields).to include(*fields_used)
  end

  it "accepts all of them together" do
    expect do
      described_class.new(fields_used.to_h { |field| [field.to_sym, sample_for(field)] })
    end.not_to raise_error
  end

  # Builds a value of the right shape for a field. Repeated message fields are either
  # lists or maps; protobuf models a map as a repeated entry message, so the two are
  # distinguished by whether the entry type carries key/value fields.
  def sample_for(field)
    descriptor = described_class.descriptor.lookup(field)
    return sample_scalar(descriptor) unless descriptor.label == :repeated
    return {} if map_field?(descriptor)

    []
  end

  def sample_scalar(descriptor)
    case descriptor.type
    when :string then "x"
    when :bool then true
    when :message then descriptor.subtype.msgclass.new
    else raise "unhandled field type #{descriptor.type}"
    end
  end

  def map_field?(descriptor)
    return false unless descriptor.type == :message

    entry_fields = descriptor.subtype.map(&:name)
    entry_fields.include?("key") && entry_fields.include?("value")
  end

  describe "the other messages the SDK builds" do
    it "defines the fields register_resource_outputs sets" do
      expect(Pulumirpc::RegisterResourceOutputsRequest.descriptor.map(&:name))
        .to include("urn", "outputs")
    end

    it "defines the fields Log sets" do
      expect(Pulumirpc::LogRequest.descriptor.map(&:name))
        .to include("severity", "message", "urn", "ephemeral")
    end
  end
end
