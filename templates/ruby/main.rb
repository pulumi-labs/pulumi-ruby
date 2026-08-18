# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

# Providers are reached through their type token until SDK generation lands. With a
# generated SDK this reads `Pulumi::Random::RandomPet.new("pet", length: length)`.
pet = Pulumi::CustomResource.new(
  "random:index/randomPet:RandomPet", "pet",
  { length: config.get_integer("length") || 3 }
)

Pulumi.export "name", pet.output("id")
