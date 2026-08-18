# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

no_depends_on = ::Pulumi::Simple::Resource.new("noDependsOn",
  value: true)
with_depends_on = ::Pulumi::Simple::Resource.new("withDependsOn",
  value: false,
  opts: Pulumi::ResourceOptions.new(depends_on: [
    no_depends_on,
  ]))