# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::Args do
  # Stands in for what codegen will emit for a resource's inputs.
  let(:bucket_args) do
    Class.new(described_class) do
      def self.name = "BucketArgs"

      property :acl
      property :versioning
      property :tags

      # A property whose name collides with a method every Object has. Real schemas
      # contain these (S3 objects have `hash`), and they are the reason DSLProxy has to be
      # a blank slate rather than an ordinary Object subclass.
      property :hash
      property :method
    end
  end

  describe "keyword arguments" do
    it "collects properties" do
      args = bucket_args.build(acl: "private", versioning: { enabled: true })
      expect(args.to_h).to eq({ acl: "private", versioning: { enabled: true } })
    end

    # The strongest available answer to "Ruby has no type checking": a declared property
    # list means a misspelling is caught at the call, not silently ignored.
    it "rejects an undeclared property" do
      expect { bucket_args.build(acll: "private") }
        .to raise_error(ArgumentError, /unknown property :acll for BucketArgs/)
    end
  end

  describe "a block with an explicit receiver" do
    it "collects properties assigned through the parameter" do
      args = bucket_args.build { |b| b.acl = "private" }
      expect(args.to_h).to eq({ acl: "private" })
    end

    it "sees locals, instance variables and methods from the calling scope" do
      caller = Class.new do
        def initialize = @env = "prod"
        def suffix = "-suffix"

        def build(klass)
          local = "local"
          klass.build { |b| b.tags = { env: @env, from: suffix, local: local } }
        end
      end

      args = caller.new.build(bucket_args)
      expect(args.to_h[:tags]).to eq({ env: "prod", from: "-suffix", local: "local" })
    end
  end

  describe "a block without a receiver" do
    it "collects properties written as bare calls" do
      args = bucket_args.build do
        acl "private"
        versioning enabled: true
      end

      expect(args.to_h).to eq({ acl: "private", versioning: { enabled: true } })
    end

    # A bare instance_eval breaks all three of these. This is the whole reason DSLProxy
    # exists, so it is the thing most worth pinning down.
    it "still sees locals, instance variables and methods from the calling scope" do
      caller = Class.new do
        def initialize = @env = "prod"
        def suffix = "-suffix"

        def build(klass)
          local = "local"
          klass.build { tags({ env: @env, from: suffix, local: local }) }
        end
      end

      args = caller.new.build(bucket_args)
      expect(args.to_h[:tags]).to eq({ env: "prod", from: "-suffix", local: "local" })
    end

    it "handles properties whose names collide with Object's own methods" do
      args = bucket_args.build do
        hash "abc123"
        method "GET"
      end

      expect(args.to_h).to eq({ hash: "abc123", method: "GET" })
    end

    it "raises for an undeclared property rather than swallowing it" do
      expect { bucket_args.build { nonexistent "x" } }.to raise_error(NoMethodError)
    end

    it "propagates an error raised in the caller's own method" do
      caller = Class.new do
        def boom = raise("from caller")
        def build(klass) = klass.build { acl boom }
      end

      expect { caller.new.build(bucket_args) }.to raise_error(RuntimeError, "from caller")
    end
  end

  describe "all three forms" do
    it "produce the same result" do
      env = "prod"

      kwargs = bucket_args.build(acl: "private", tags: { "Env" => env })
      receiver = bucket_args.build do |b|
        b.acl = "private"
        b.tags = { "Env" => env }
      end
      bare = bucket_args.build do
        acl "private"
        tags({ "Env" => env })
      end

      expect(receiver.to_h).to eq(kwargs.to_h)
      expect(bare.to_h).to eq(kwargs.to_h)
    end
  end

  describe "reading back" do
    it "returns a property when called with no arguments" do
      args = bucket_args.build(acl: "private")
      expect(args.acl).to eq("private")
    end
  end

  describe Pulumi::OpenArgs do
    # Without a generated SDK there is no schema saying which properties exist, so a raw
    # type token has to accept anything. This is the documented trade: the untyped path
    # gives up typo detection.
    it "accepts undeclared properties" do
      args = described_class.build(anything: 1) { whatever "2" }
      expect(args.to_h).to eq({ anything: 1, whatever: "2" })
    end

    it "supports the assignment form too" do
      args = described_class.build { |a| a.thing = "value" }
      expect(args.to_h).to eq({ thing: "value" })
    end

    # Regression: an open bag answers respond_to? for every name, so dispatching on
    # respond_to? sent the caller's own method calls into the bag, where they came back
    # as unset properties -- silently nil, with no error anywhere. The proxy now
    # dispatches on whether a method is actually defined.
    it "still reaches the caller's methods, despite accepting any property name" do
      caller = Class.new do
        def initialize = @env = "prod"
        def tag_prefix = "acme"

        def build(klass)
          klass.build { tags({ env: @env, prefix: tag_prefix }) }
        end
      end

      args = caller.new.build(described_class)
      expect(args.to_h[:tags]).to eq({ env: "prod", prefix: "acme" })
    end
  end
end
