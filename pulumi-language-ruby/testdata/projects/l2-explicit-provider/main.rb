# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

prov = ::Pulumi::Simple::Providers::Simple.new("prov")
res = ::Pulumi::Simple::Resource.new("res",
  value: true,
  opts: Pulumi::ResourceOptions.new(provider: prov))