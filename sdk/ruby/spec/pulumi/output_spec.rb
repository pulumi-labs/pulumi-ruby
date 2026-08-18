# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::Output do
  # Resolving an Output is a runtime-internal operation deliberately not exposed on the
  # public API, so specs reach through data_future.
  def resolve(output)
    output.data_future.value!(5)
  end

  def unknown_output(secret: false)
    described_class.new(
      Concurrent::Promises.fulfilled_future(described_class::Data.unknown(secret: secret))
    )
  end

  describe ".from" do
    it "wraps a plain value as known and not secret" do
      data = resolve(described_class.from(42))

      expect(data.value).to eq(42)
      expect(data.known).to be(true)
      expect(data.secret).to be(false)
    end

    it "returns an Output unchanged" do
      output = described_class.from(1)
      expect(described_class.from(output)).to be(output)
    end

    it "lifts Outputs nested inside arrays" do
      expect(resolve(described_class.from([1, described_class.from(2)])).value).to eq([1, 2])
    end

    it "lifts Outputs nested inside hashes" do
      lifted = described_class.from({ a: 1, b: described_class.from(2) })
      expect(resolve(lifted).value).to eq({ a: 1, b: 2 })
    end

    it "propagates unknown-ness out of a nested structure" do
      expect(resolve(described_class.from([1, unknown_output])).known).to be(false)
    end

    it "propagates secretness out of a nested structure" do
      lifted = described_class.from({ password: described_class.secret("hunter2") })
      expect(resolve(lifted).secret).to be(true)
    end
  end

  describe "#apply" do
    it "transforms a known value" do
      expect(resolve(described_class.from(2).apply { |v| v * 3 }).value).to eq(6)
    end

    # This is the property that makes `pulumi preview` possible: rather than invent a
    # value for something that doesn't exist yet, the whole chain stays unknown.
    it "does not invoke the block when the value is unknown" do
      invoked = false
      result = unknown_output.apply { invoked = true }

      data = resolve(result)
      expect(invoked).to be(false)
      expect(data.known).to be(false)
      expect(data.value).to be_nil
    end

    it "keeps secretness across an apply" do
      expect(resolve(described_class.secret("s").apply(&:upcase)).secret).to be(true)
    end

    it "keeps secretness even when the value is unknown" do
      expect(resolve(unknown_output(secret: true).apply { "x" }).secret).to be(true)
    end

    it "flattens an Output returned by the block" do
      result = described_class.from(1).apply { |v| described_class.from(v + 1) }
      expect(resolve(result).value).to eq(2)
    end

    it "inherits secretness from an Output returned by the block" do
      result = described_class.from(1).apply { described_class.secret("inner") }
      data = resolve(result)

      expect(data.value).to eq("inner")
      expect(data.secret).to be(true)
    end

    it "becomes unknown when the block returns an unknown Output" do
      result = described_class.from(1).apply { unknown_output }
      expect(resolve(result).known).to be(false)
    end

    it "propagates exceptions raised inside the block" do
      result = described_class.from(1).apply { raise "boom" }
      expect { resolve(result) }.to raise_error(RuntimeError, "boom")
    end

    it "requires a block" do
      expect { described_class.from(1).apply }.to raise_error(ArgumentError, /requires a block/)
    end
  end

  describe "#rescue_apply" do
    it "recovers from an error raised upstream" do
      result = described_class.from(1).apply { raise "boom" }.rescue_apply { |e| "caught: #{e.message}" }
      expect(resolve(result).value).to eq("caught: boom")
    end

    it "passes a successful value through untouched" do
      result = described_class.from("fine").rescue_apply { "recovered" }
      expect(resolve(result).value).to eq("fine")
    end
  end

  describe ".all" do
    it "combines positional Outputs into an array" do
      combined = described_class.all(described_class.from(1), 2, described_class.from(3))
      expect(resolve(combined).value).to eq([1, 2, 3])
    end

    it "combines keyword Outputs into a hash" do
      combined = described_class.all(host: described_class.from("h"), port: 80)
      expect(resolve(combined).value).to eq({ host: "h", port: 80 })
    end

    it "is unknown when any input is unknown" do
      expect(resolve(described_class.all(described_class.from(1), unknown_output)).known).to be(false)
    end

    it "is secret when any input is secret" do
      expect(resolve(described_class.all(1, described_class.secret(2))).secret).to be(true)
    end

    it "handles the empty case" do
      expect(resolve(described_class.all).value).to eq([])
    end

    it "rejects mixing positional and keyword arguments" do
      expect { described_class.all(1, a: 2) }.to raise_error(ArgumentError, /not both/)
    end
  end

  describe ".secret and .unsecret" do
    it "marks a plain value secret" do
      expect(resolve(described_class.secret("x")).secret).to be(true)
    end

    it "removes the marker" do
      expect(resolve(described_class.unsecret(described_class.secret("x"))).secret).to be(false)
    end

    it "keeps the value intact" do
      expect(resolve(described_class.secret("x")).value).to eq("x")
    end
  end

  describe ".format" do
    it "interpolates positional Outputs" do
      formatted = described_class.format("https://%s/%s", described_class.from("host"), "path")
      expect(resolve(formatted).value).to eq("https://host/path")
    end

    it "interpolates named Outputs" do
      formatted = described_class.format("%<scheme>s://%<host>s", scheme: "https",
                                                                  host: described_class.from("example.com"))
      expect(resolve(formatted).value).to eq("https://example.com")
    end

    it "stays unknown when an argument is unknown" do
      expect(resolve(described_class.format("%s", unknown_output)).known).to be(false)
    end

    it "stays secret when an argument is secret" do
      expect(resolve(described_class.format("%s", described_class.secret("s"))).secret).to be(true)
    end
  end

  describe ".concat" do
    it "joins string parts" do
      joined = described_class.concat("a", described_class.from("b"), "c")
      expect(resolve(joined).value).to eq("abc")
    end
  end

  describe ".json_dump and .json_parse" do
    it "serializes a structure containing Outputs" do
      dumped = described_class.json_dump({ "id" => described_class.from(7) })
      expect(resolve(dumped).value).to eq('{"id":7}')
    end

    it "parses a JSON Output" do
      parsed = described_class.json_parse(described_class.from('{"id":7}'))
      expect(resolve(parsed).value).to eq({ "id" => 7 })
    end

    it "keeps a secret input secret through a round trip" do
      dumped = described_class.json_dump({ "k" => described_class.secret("v") })
      expect(resolve(dumped).secret).to be(true)
    end
  end

  describe "string conversion" do
    around do |example|
      original = ENV.fetch("PULUMI_ERROR_OUTPUT_STRING", nil)
      example.run
      ENV["PULUMI_ERROR_OUTPUT_STRING"] = original
    end

    it "warns and returns an explanatory message by default" do
      ENV.delete("PULUMI_ERROR_OUTPUT_STRING")
      output = described_class.from("x")

      result = nil
      expect { result = output.to_s }.to output(/not supported/).to_stderr
      expect(result).to include("Output.format")
    end

    it "raises when PULUMI_ERROR_OUTPUT_STRING is set" do
      ENV["PULUMI_ERROR_OUTPUT_STRING"] = "1"
      expect { described_class.from("x").to_s }.to raise_error(Pulumi::OutputToStringError)
    end

    it "has a terse inspect so backtraces stay readable" do
      expect(described_class.from("x").inspect).to eq("#<Pulumi::Output>")
    end
  end

  # Answering Ruby's implicit conversion protocol is what produces errors like
  # "can't convert Output to String (Output#to_str gives Output)". Leaving these
  # undefined is a deliberate design decision, so it gets a test.
  describe "implicit conversion protocol" do
    %i[to_str to_ary to_hash to_proc to_int].each do |method|
      it "does not respond to ##{method}" do
        expect(described_class.from("x")).not_to respond_to(method)
      end
    end

    it "produces Ruby's clear TypeError when used as a String" do
      # Deliberately testing String#+, so interpolation would defeat the point.
      expect { "prefix" + described_class.from("x") } # rubocop:disable Style/StringConcatenation
        .to raise_error(TypeError, /no implicit conversion of Pulumi::Output into String/)
    end

    it "does not silently splat as an array" do
      expect(Array(described_class.from("x")).length).to eq(1)
    end
  end
end
