# frozen_string_literal: true

require "pulumi"
require "pulumi/goodbye"

prov = ::Pulumi::Goodbye::Providers::Goodbye.new("prov",
  text: "World")
res = ::Pulumi::Goodbye::Goodbye.new("res",
  opts: Pulumi::ResourceOptions.new(provider: prov))
Pulumi.export("parameterValue", res["parameterValue"])