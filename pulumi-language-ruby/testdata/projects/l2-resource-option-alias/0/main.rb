# frozen_string_literal: true

require "pulumi"
require "pulumi/component"
require "pulumi/simple"

parent = ::Pulumi::Simple::Resource.new("parent",
  value: true)
alias_urn = ::Pulumi::Simple::Resource.new("aliasURN",
  value: true)
alias_name = ::Pulumi::Simple::Resource.new("aliasName",
  value: true)
alias_no_parent = ::Pulumi::Simple::Resource.new("aliasNoParent",
  value: true)
alias_parent = ::Pulumi::Simple::Resource.new("aliasParent",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: alias_urn))
alias_type = ::Pulumi::Component::Custom.new("aliasType",
  value: "true")