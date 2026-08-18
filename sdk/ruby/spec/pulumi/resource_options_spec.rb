# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pulumi::ResourceOptions do
  # The mock monitor records what the SDK actually sent, so these assert on the wire
  # rather than on the option object -- which is where the previous gap was: options were
  # accepted, stored, and never transmitted.
  def registration_for(name, &block)
    Pulumi::Testing.run(Pulumi::Spec::EchoMocks.new, &block)
    Pulumi::Spec::RecordingMonitor.last_requests.find { |r| r.name == name }
  end

  describe "dependencies" do
    # Regression: a component is not something a provider creates, so ordering against its
    # own registration orders against nothing. Both Go and Python expand a component into
    # its children; the engine does no expansion of its own.
    it "expands a component into the children that do the work" do
      request = registration_for("after") do
        component = Pulumi::ComponentResource.new("demo:index:Group", "g")
        child_opts = described_class.new(parent: component)
        Pulumi::CustomResource.new("test:mod:A", "child-1", {}, child_opts)
        Pulumi::CustomResource.new("test:mod:A", "child-2", {}, child_opts)

        Pulumi::CustomResource.new("test:mod:B", "after", {},
                                   described_class.new(depends_on: [component]))
      end

      expect(request.dependencies.to_a).to contain_exactly(
        "urn:pulumi:stack::project::test:mod:A::child-1",
        "urn:pulumi:stack::project::test:mod:A::child-2"
      )
    end

    it "passes a custom resource dependency through unchanged" do
      request = registration_for("after") do
        first = Pulumi::CustomResource.new("test:mod:A", "first", {})
        Pulumi::CustomResource.new("test:mod:B", "after", {},
                                   described_class.new(depends_on: [first]))
      end

      expect(request.dependencies.to_a).to eq(["urn:pulumi:stack::project::test:mod:A::first"])
    end

    it "expands components nested inside components" do
      request = registration_for("after") do
        outer = Pulumi::ComponentResource.new("demo:index:Outer", "outer")
        inner = Pulumi::ComponentResource.new("demo:index:Inner", "inner", {},
                                              described_class.new(parent: outer))
        Pulumi::CustomResource.new("test:mod:A", "leaf", {},
                                   described_class.new(parent: inner))

        Pulumi::CustomResource.new("test:mod:B", "after", {},
                                   described_class.new(depends_on: [outer]))
      end

      expect(request.dependencies.to_a).to eq(["urn:pulumi:stack::project::test:mod:A::leaf"])
    end
  end

  describe "lifecycle options" do
    # Regression: aliases were accepted, merged, and never sent -- so a user renaming a
    # resource and adding an alias to preserve it would watch it be destroyed anyway.
    it "sends aliases" do
      request = registration_for("b") do
        Pulumi::CustomResource.new(
          "test:mod:B", "b", {},
          described_class.new(aliases: ["urn:pulumi:stack::project::test:mod:B::old"])
        )
      end

      expect(request.aliasURNs.to_a).to eq(["urn:pulumi:stack::project::test:mod:B::old"])
    end

    it "sends protect, retain_on_delete and ignore_changes" do
      request = registration_for("b") do
        Pulumi::CustomResource.new(
          "test:mod:B", "b", {},
          described_class.new(protect: true, retain_on_delete: true,
                              ignore_changes: ["tags"])
        )
      end

      expect(request.protect).to be(true)
      expect(request.retainOnDelete).to be(true)
      expect(request.ignoreChanges.to_a).to eq(["tags"])
    end

    # An unset option must be absent rather than sent as its zero value, or the engine
    # cannot tell "leave this alone" from "set it to false".
    it "leaves delete_before_replace unspecified when not given" do
      request = registration_for("b") { Pulumi::CustomResource.new("test:mod:B", "b", {}) }

      expect(request.deleteBeforeReplaceDefined).to be(false)
    end

    it "marks delete_before_replace as explicitly defined when given" do
      request = registration_for("b") do
        Pulumi::CustomResource.new("test:mod:B", "b", {},
                                   described_class.new(delete_before_replace: false))
      end

      expect(request.deleteBeforeReplaceDefined).to be(true)
      expect(request.deleteBeforeReplace).to be(false)
    end
  end

  describe ".merge" do
    it "lets overrides win for scalar options" do
      merged = described_class.merge(
        described_class.new(protect: true, version: "1.0.0"),
        described_class.new(version: "2.0.0")
      )

      expect(merged.protect).to be(true)
      expect(merged.version).to eq("2.0.0")
    end

    # Dependencies are additive: a child declaring its own does not stop it inheriting
    # whatever its parent depended on.
    it "concatenates dependencies rather than replacing them" do
      merged = described_class.merge(
        described_class.new(depends_on: [:a]),
        described_class.new(depends_on: [:b])
      )

      expect(merged.depends_on).to eq(%i[a b])
    end

    it "does not modify either input" do
      base = described_class.new(protect: true)
      overrides = described_class.new(protect: false)

      described_class.merge(base, overrides)

      expect(base.protect).to be(true)
      expect(overrides.protect).to be(false)
    end
  end
end
