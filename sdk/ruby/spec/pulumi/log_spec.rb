# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::Log do
  # Captures what the SDK would have sent to the engine.
  let(:engine) do
    Class.new do
      attr_reader :messages

      def initialize = @messages = []

      def log(request)
        @messages << { severity: request.severity, message: request.message, urn: request.urn }
        Google::Protobuf::Empty.new
      end
    end.new
  end

  # Runs a block as a program, with the capturing engine installed.
  def with_engine(&block)
    Pulumi::Testing.run do
      Pulumi::Runtime.settings.instance_variable_set(:@engine, engine)
      block.call
    end
  end

  it "sends each severity through to the engine" do
    with_engine do
      described_class.debug("d")
      described_class.info("i")
      described_class.warn("w")
      described_class.error("e")
    end

    expect(engine.messages.map { |m| m[:severity] }).to eq(%i[DEBUG INFO WARNING ERROR])
    expect(engine.messages.map { |m| m[:message] }).to eq(%w[d i w e])
  end

  # Attaching a message to a resource is what makes the CLI show it under the right line.
  it "attaches a message to its resource" do
    with_engine do
      bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", {})
      described_class.warn("that bucket is public", resource: bucket)
    end

    expect(engine.messages.first[:urn]).to eq("urn:pulumi:stack::project::aws:s3/bucket:Bucket::b")
  end

  it "leaves the urn empty when no resource is given" do
    with_engine { described_class.info("general") }
    expect(engine.messages.first[:urn]).to eq("")
  end

  # Logging must never be the thing that breaks a program, so a resource whose URN cannot
  # be resolved degrades to an unattached message.
  it "still logs when the resource's urn cannot be resolved" do
    broken = Object.new
    broken.define_singleton_method(:urn) do
      Pulumi::Output.from(nil).apply { raise "registration failed" }
    end

    with_engine { described_class.error("something went wrong", resource: broken) }

    expect(engine.messages.first[:message]).to eq("something went wrong")
    expect(engine.messages.first[:urn]).to eq("")
  end

  # Outside a deployment there is no engine to talk to; falling back to stderr keeps
  # logging usable in unit tests rather than raising.
  it "falls back to stderr with no runtime configured" do
    Pulumi::Runtime.reset
    expect { described_class.warn("no engine") }.to output(/no engine/).to_stderr
  end
end
