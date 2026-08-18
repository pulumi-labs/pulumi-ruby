# frozen_string_literal: true

require "pulumi"
require "pulumi/config_enum"

prov = ::Pulumi::ConfigEnum::Providers::ConfigEnum.new("prov",
  a_string: "hello",
  a_enum: "two")
res = ::Pulumi::ConfigEnum::Resource.new("res",
  the_string: prov["aString"],
  the_enum: prov["aEnum"],
  opts: Pulumi::ResourceOptions.new(provider: prov))