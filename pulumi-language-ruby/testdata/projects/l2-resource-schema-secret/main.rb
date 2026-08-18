# frozen_string_literal: true

require "pulumi"
require "pulumi/output"

prov_elided = ::Pulumi::Output::Providers::Output.new("provElided",
  elide_unknowns: true)
prov_not_elided = ::Pulumi::Output::Providers::Output.new("provNotElided")
top_level_elided = ::Pulumi::Output::Resource.new("topLevelElided",
  value: 1,
  opts: Pulumi::ResourceOptions.new(provider: prov_elided))
top_level_not_elided = ::Pulumi::Output::Resource.new("topLevelNotElided",
  value: 1,
  opts: Pulumi::ResourceOptions.new(provider: prov_not_elided))
Pulumi.export("topLevelElided", top_level_elided["secretOutput"])
Pulumi.export("topLevelNotElided", top_level_not_elided["secretOutput"])