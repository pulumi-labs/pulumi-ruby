# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::StackReference do
  let(:stack_outputs) do
    { "acme/network/prod" => { "subnetId" => "subnet-123", "dbPassword" => "s3cret" } }
  end

  def run(&block)
    Pulumi::Testing.run(Pulumi::Spec::EchoMocks.new,
                        stack_outputs: stack_outputs,
                        secret_stack_outputs: ["dbPassword"], &block)
  end

  it "reads an output of the referenced stack" do
    result = run do
      network = described_class.new("acme/network/prod")
      Pulumi.export "subnet", network.output("subnetId")
    end

    expect(Pulumi::Testing.value(result.exports["subnet"])).to eq("subnet-123")
  end

  it "exposes the whole output map" do
    result = run do
      Pulumi.export "all", described_class.new("acme/network/prod").outputs
    end

    expect(Pulumi::Testing.value(result.exports["all"]))
      .to eq({ "subnetId" => "subnet-123", "dbPassword" => "s3cret" })
  end

  # Regression: the outputs map arrives secret as a whole, because one member is. Deriving
  # a single key from it marked *every* key secret, including plainly public ones.
  it "leaves a plain output plain even when a sibling is secret" do
    result = run do
      Pulumi.export "subnet", described_class.new("acme/network/prod").output("subnetId")
    end

    expect(Pulumi::Testing.secret?(result.exports["subnet"])).to be(false)
    expect(Pulumi::Testing.value(result.exports["subnet"])).to eq("subnet-123")
  end

  # Reading a value the other stack marked secret must not launder it into plaintext just
  # because it crossed a stack boundary.
  it "keeps an output the other stack marked secret" do
    result = run do
      Pulumi.export "pw", described_class.new("acme/network/prod").output("dbPassword")
    end

    expect(Pulumi::Testing.secret?(result.exports["pw"])).to be(true)
    expect(Pulumi::Testing.value(result.exports["pw"])).to eq("s3cret")
  end

  it "returns nil for an output the other stack does not export" do
    result = run do
      Pulumi.export "missing", described_class.new("acme/network/prod").output("nope")
    end

    expect(Pulumi::Testing.value(result.exports["missing"])).to be_nil
  end

  it "names the stack when a required output is missing" do
    expect do
      run do
        Pulumi.export "missing", described_class.new("acme/network/prod").require_output("nope")
      end
    end.to raise_error(Pulumi::Error, %r{acme/network/prod.*does not have an output named 'nope'})
  end

  it "reads a different stack when one is named explicitly" do
    result = run do
      reference = described_class.new("net", stack_name: "acme/network/prod")
      Pulumi.export "subnet", reference.output("subnetId")
    end

    expect(Pulumi::Testing.value(result.exports["subnet"])).to eq("subnet-123")
  end
end
