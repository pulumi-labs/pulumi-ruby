# frozen_string_literal: true

require "pulumi"

config = Pulumi.config
size = config.get_integer("length") || 3

# Providers are reached through their type token until SDK generation lands; with a
# generated SDK this reads `Pulumi::Random::RandomPet.new("pet", length: size)`.
PET_TYPE = "random:index/randomPet:RandomPet"

# Three ways to say the same thing. The first is canonical; the others exist because
# Ruby offers them and the block forms read well for anyone coming from Chef.
plain = Pulumi::CustomResource.new(PET_TYPE, "plain", { length: size })

receiver = Pulumi::CustomResource.new(PET_TYPE, "receiver") do |pet|
  pet.length = size
end

block = Pulumi::CustomResource.new(PET_TYPE, "block") do
  length size
end

# A component packages resources into a reusable unit, the way a Chef custom resource did.
class PetPair < Pulumi::ComponentResource
  attr_reader :names

  def initialize(name, length:, opts: nil)
    super("example:pets:PetPair", name, {}, opts)
    child = Pulumi::ResourceOptions.new(parent: self)

    @names = (1..2).map do |i|
      Pulumi::CustomResource.new(PET_TYPE, "#{name}-#{i}", { length: length }, child).output("id")
    end

    register_outputs(names: @names)
  end
end

pair = PetPair.new("pair", length: size)

Pulumi.export "name", plain.output("id")
Pulumi.export "receiver", receiver.output("id")
Pulumi.export "block", block.output("id")

# Outputs are not values yet, so they are combined and formatted rather than interpolated.
Pulumi.export "pair", Pulumi::Output.all(*pair.names)
Pulumi.export "greeting", Pulumi::Output.format("hello, %s and %s!", *pair.names)
