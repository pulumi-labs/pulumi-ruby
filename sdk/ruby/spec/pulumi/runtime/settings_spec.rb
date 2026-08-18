# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::Runtime::Settings do
  let(:monitor) { Pulumi::Spec::CountingMonitor.new(Pulumi::Testing::Mocks.new, project: "p", stack: "s") }
  let(:settings) { described_class.new(project: "p", stack: "s", monitor: monitor) }

  describe "feature negotiation" do
    it "reports what the engine supports" do
      expect(settings.supports?(:secrets)).to be(true)
      expect(settings.supports?(:byte_string)).to be(true)
    end

    # Every resource registration asks about features, and registrations run concurrently.
    # Without a guard this made one round trip per resource.
    it "negotiates exactly once, even under concurrent readers" do
      20.times.map { Thread.new { settings.supports?(:secrets) } }.each(&:join)

      expect(monitor.deployment_info_calls.value).to eq(1)
    end

    it "does not talk to the engine again on later reads" do
      settings.supports?(:secrets)
      settings.supports?(:output_values)
      settings.supports?(:transforms)

      expect(monitor.deployment_info_calls.value).to eq(1)
    end

    # An engine predating GetDeploymentInfo answers Unimplemented; the SDK must fall back
    # to probing rather than concluding that nothing is supported.
    it "falls back to per-feature probes on an older engine" do
      allow(monitor).to receive(:get_deployment_info).and_raise(GRPC::Unimplemented.new)

      expect(settings.supports?(:secrets)).to be(true)
      expect(monitor.supports_feature_calls.value).to be > 0
    end
  end

  describe "#rpc_options" do
    it "derives serialization options from what the engine supports" do
      options = settings.rpc_options

      expect(options.keep_secrets).to be(true)
      expect(options.keep_resources).to be(true)
      expect(options.keep_byte_string).to be(true)
      expect(options.keep_output_values).to be(false)
    end

    it "allows callers to override individual options" do
      expect(settings.rpc_options(keep_output_values: true).keep_output_values).to be(true)
    end
  end

  describe "ambient configuration" do
    it "is read-only once installed" do
      # Config is deliberately frozen: Chef's globally mutable `node` made "where did this
      # value come from?" unanswerable, and there is nothing here to write to.
      expect(settings.config).to be_frozen
    end
  end

  describe "when no program is running" do
    it "explains why the runtime is unavailable rather than raising NoMethodError" do
      Pulumi::Runtime.reset
      expect { Pulumi::Runtime.settings }
        .to raise_error(Pulumi::Error, /must run inside a Pulumi program/)
    end
  end
end
