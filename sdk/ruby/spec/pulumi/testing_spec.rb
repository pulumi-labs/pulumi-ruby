# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::Testing do
  describe "a minimal program" do
    let(:result) do
      described_class.run(Pulumi::Spec::EchoMocks.new) do
        bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", { acl: "private" })
        Pulumi.export "arn", bucket.output("arn")
        Pulumi.export "id", bucket.id
      end
    end

    it "registers the resource with its inputs" do
      bucket = result.resource("b")

      expect(bucket.type).to eq("aws:s3/bucket:Bucket")
      expect(bucket.inputs).to eq({ "acl" => "private" })
    end

    it "resolves outputs the provider computed" do
      expect(described_class.value(result.exports["arn"])).to eq("arn:fake:b")
    end

    it "resolves the provider-assigned id" do
      expect(described_class.value(result.exports["id"])).to eq("b-id")
    end
  end

  describe "parenting" do
    # Regression: the parent used to be read from ambient state inside the *asynchronous*
    # registration. A program that finished before its registrations ran would have that
    # state already cleared, silently producing top-level resources. The parent is now
    # captured when the resource is constructed.
    it "parents top-level resources to the stack" do
      result = described_class.run(Pulumi::Spec::EchoMocks.new, project: "proj", stack: "dev") do
        Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", {})
      end

      expect(result.resource("b").parent).to eq("urn:pulumi:dev::proj::pulumi:pulumi:Stack::proj-dev")
    end

    it "parents children to their component" do
      result = described_class.run(Pulumi::Spec::EchoMocks.new, project: "proj", stack: "dev") do
        component = Pulumi::ComponentResource.new("demo:index:Group", "g")
        Pulumi::CustomResource.new(
          "aws:s3/bucket:Bucket", "child", {},
          Pulumi::ResourceOptions.new(parent: component)
        )
      end

      expect(result.resource("child").parent).to eq("urn:pulumi:dev::proj::demo:index:Group::g")
    end

    it "gives the root stack no parent" do
      result = described_class.run(Pulumi::Spec::EchoMocks.new, project: "proj", stack: "dev") { nil }
      stack = result.resources.find { |r| r.type == "pulumi:pulumi:Stack" }

      expect(stack.parent).to eq("")
    end
  end

  describe "previews" do
    # Regression: an absent value used to resolve to nil, so applies ran against a
    # placeholder and a preview could report a value that the following update changed.
    it "leaves provider-computed values unknown, and skips applies over them" do
      applied = false

      result = described_class.run(described_class::Mocks.new, dry_run: true) do
        bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", {})
        Pulumi.export("derived", bucket.output("arn").apply { |v| applied = true and "got #{v}" })
      end

      expect(described_class.known?(result.exports["derived"])).to be(false)
      expect(applied).to be(false)
    end

    # Regression: the engine sends secret(unknown) for a secret property during a preview.
    # Deserializing that into an Output made it look *known*, so the apply ran and got the
    # unknown sentinel -- which could then be baked into another resource's inputs.
    it "leaves a secret value unknown too, and still marks it secret" do
      applied = false

      result = described_class.run(Pulumi::Spec::SecretMocks.new, dry_run: true) do
        db = Pulumi::CustomResource.new("aws:rds/instance:Instance", "db", {})
        Pulumi.export("password", db.output("password").apply { applied = true })
      end

      expect(described_class.known?(result.exports["password"])).to be(false)
      expect(described_class.secret?(result.exports["password"])).to be(true)
      expect(applied).to be(false)
    end

    # Regression: `unresolved` read Runtime.settings from inside the registration
    # continuation, which runs on a worker thread after the runtime may be torn down.
    it "resolves outputs even when read after the run has finished" do
      result = described_class.run(described_class::Mocks.new, dry_run: true) do
        bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", {})
        Pulumi.export "late", bucket.output("never_returned")
      end

      # Runtime.settings is gone by now; reading the Output must still work.
      expect(described_class.known?(result.exports["late"])).to be(false)
    end

    it "still resolves values that do not depend on a provider" do
      result = described_class.run(described_class::Mocks.new, dry_run: true) do
        Pulumi.export "plain", Pulumi::Output.from("known")
      end

      expect(described_class.value(result.exports["plain"])).to eq("known")
    end
  end

  describe "dependencies" do
    it "records a property's dependency on another resource" do
      result = described_class.run(Pulumi::Spec::EchoMocks.new) do
        first = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "first", {})
        Pulumi::CustomResource.new("aws:s3/bucketObject:BucketObject", "second",
                                   { bucket: first.output("arn") })
      end

      expect(result.resource("second").inputs).to eq({ "bucket" => "arn:fake:first" })
    end
  end

  describe "secrets" do
    it "keeps secretness across the wire and through an apply" do
      result = described_class.run(Pulumi::Spec::EchoMocks.new) do
        bucket = Pulumi::CustomResource.new(
          "aws:s3/bucket:Bucket", "b", { token: Pulumi::Output.secret("shh") }
        )
        Pulumi.export "derived", bucket.output("token").apply(&:upcase)
      end

      expect(described_class.secret?(result.exports["derived"])).to be(true)
      expect(described_class.value(result.exports["derived"])).to eq("SHH")
    end
  end

  describe "components" do
    it "publishes outputs registered by a component" do
      component_class = Class.new(Pulumi::ComponentResource) do
        def initialize(name)
          super("demo:index:Thing", name)
          register_outputs(computed: "value-for-#{name}")
        end
      end

      result = described_class.run(Pulumi::Spec::EchoMocks.new) do
        component_class.new("thing")
      end

      expect(result.resource("thing").outputs).to eq({ "computed" => "value-for-thing" })
    end

    it "refuses a second register_outputs, which would silently discard the first" do
      expect do
        described_class.run(Pulumi::Spec::EchoMocks.new) do
          component = Pulumi::ComponentResource.new("demo:index:Thing", "t")
          component.register_outputs({})
          component.register_outputs({})
        end
      end.to raise_error(Pulumi::Error, /only be called once/)
    end
  end

  describe "config" do
    it "reads typed values from the stack's configuration" do
      config = { "proj:name" => "web", "proj:count" => "3", "proj:enabled" => "true" }

      described_class.run(Pulumi::Spec::EchoMocks.new, project: "proj", config: config) do
        c = Pulumi.config
        expect(c.require("name")).to eq("web")
        expect(c.get_integer("count")).to eq(3)
        expect(c.require_boolean("enabled")).to be(true)
        expect(c.get("missing")).to be_nil
      end
    end

    it "names the missing key in the error, with the command that would set it" do
      described_class.run(Pulumi::Spec::EchoMocks.new, project: "proj") do
        expect { Pulumi.config.require("apiKey") }
          .to raise_error(Pulumi::ConfigMissingError, /proj:apiKey/)
      end
    end

    it "reports a type mismatch rather than coercing" do
      described_class.run(Pulumi::Spec::EchoMocks.new, project: "proj", config: { "proj:n" => "abc" }) do
        expect { Pulumi.config.get_integer("n") }.to raise_error(Pulumi::ConfigTypeError, /integer/)
      end
    end

    it "marks required secrets secret" do
      described_class.run(Pulumi::Spec::EchoMocks.new, project: "proj", config: { "proj:key" => "v" }) do
        expect(described_class.secret?(Pulumi.config.require_secret("key"))).to be(true)
      end
    end
  end

  describe "resources declared inside an apply" do
    # Regression: apply continuations were not tracked, so the drain could conclude while
    # a block that declares a resource was still queued. The resource was then never
    # registered -- and a resource missing from the program is one the engine deletes.
    # This reproduced roughly one run in forty, which is the worst possible frequency.
    it "always registers, across repeated runs" do
      missing = 0

      40.times do
        result = described_class.run(Pulumi::Spec::EchoMocks.new) do
          first = Pulumi::CustomResource.new("test:mod:A", "a", { n: 1 })
          first.output("arn").apply do |arn|
            Pulumi::CustomResource.new("test:mod:B", "b", { from: arn })
          end
        end

        missing += 1 if result.resource("b").nil?
      end

      expect(missing).to eq(0)
    end

    it "passes the resolved value into the nested resource" do
      result = described_class.run(Pulumi::Spec::EchoMocks.new) do
        first = Pulumi::CustomResource.new("test:mod:A", "a", {})
        first.output("arn").apply do |arn|
          Pulumi::CustomResource.new("test:mod:B", "b", { from: arn })
        end
      end

      expect(result.resource("b").inputs).to eq({ "from" => "arn:fake:a" })
    end

    # Waiting for a continuation must not mean adopting its failure: an error the program
    # recovers from is not the program's error.
    it "does not fail the run when an apply error is recovered" do
      result = described_class.run(Pulumi::Spec::EchoMocks.new) do
        bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", {})
        Pulumi.export("recovered", bucket.output("arn").apply { raise "boom" }.rescue_apply { "fallback" })
      end

      expect(described_class.value(result.exports["recovered"])).to eq("fallback")
    end
  end

  describe "error reporting" do
    it "surfaces an error raised inside an apply as the run's failure" do
      expect do
        described_class.run(Pulumi::Spec::EchoMocks.new) do
          bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", {})
          Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "c",
                                     { name: bucket.output("arn").apply { raise "boom" } })
        end
      end.to raise_error(RuntimeError, "boom")
    end
  end

  describe "runtime metadata" do
    it "exposes the project, stack and dry-run state" do
      described_class.run(Pulumi::Spec::EchoMocks.new, project: "proj", stack: "dev", dry_run: true) do
        expect(Pulumi.project).to eq("proj")
        expect(Pulumi.stack).to eq("dev")
        expect(Pulumi.dry_run?).to be(true)
      end
    end
  end
end
