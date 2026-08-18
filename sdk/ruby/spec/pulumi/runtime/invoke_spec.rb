# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::Runtime, "#invoke" do
  # Answers invokes by echoing the token and arguments back, so the specs can see exactly
  # what crossed the boundary.
  let(:mocks) do
    Class.new(Pulumi::Testing::Mocks) do
      def invoke(args)
        { "token" => args.token, "received" => args.args }
      end
    end.new
  end

  def unknown_output
    Pulumi::Output.new(
      Concurrent::Promises.fulfilled_future(Pulumi::Output::Data.unknown)
    )
  end

  it "returns the provider's result as an Output" do
    result = Pulumi::Testing.run(mocks) do
      Pulumi.export "region", Pulumi.invoke("aws:index/getRegion:getRegion", { name: "us-west-2" })
    end

    expect(Pulumi::Testing.value(result.exports["region"])).to eq(
      { "token" => "aws:index/getRegion:getRegion", "received" => { "name" => "us-west-2" } }
    )
  end

  it "resolves Output arguments before calling the provider" do
    result = Pulumi::Testing.run(Pulumi::Spec::EchoMocks.new) do
      bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", {})
      Pulumi.export "looked_up", Pulumi.invoke("aws:index/getThing:getThing",
                                               { id: bucket.output("arn") })
    end

    # EchoMocks does not override invoke, so the default returns {}; what matters is that
    # the call happened at all rather than being skipped as unknown.
    expect(Pulumi::Testing.known?(result.exports["looked_up"])).to be(true)
  end

  # A provider cannot answer a question about something that does not exist yet. Calling it
  # with the unknown sentinel would produce a preview that disagrees with the update.
  it "reports unknown rather than calling the provider with an unknown argument" do
    called = false
    counting = Class.new(Pulumi::Testing::Mocks) do
      define_method(:invoke) { |_args| called = true and {} }
    end.new

    result = Pulumi::Testing.run(counting) do
      Pulumi.export "looked_up", Pulumi.invoke("pkg:index:get", { id: unknown_output })
    end

    expect(Pulumi::Testing.known?(result.exports["looked_up"])).to be(false)
    expect(called).to be(false)
  end

  it "keeps a secret result secret" do
    secret_mocks = Class.new(Pulumi::Testing::Mocks) do
      def invoke(_args) = { "password" => Pulumi::Output.secret("hunter2") }
    end.new

    result = Pulumi::Testing.run(secret_mocks) do
      Pulumi.export "looked_up", Pulumi.invoke("pkg:index:get", {})
    end

    expect(Pulumi::Testing.secret?(result.exports["looked_up"])).to be(true)
    expect(Pulumi::Testing.value(result.exports["looked_up"])).to eq({ "password" => "hunter2" })
  end
end
