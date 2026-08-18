# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

parent = ::Pulumi::Simple::Resource.new("parent",
  value: true)
alias_urn = ::Pulumi::Simple::Resource.new("aliasURN",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: parent, aliases: [
    "urn:pulumi:test::l2-resource-option-alias::simple:index:Resource::aliasURN",
  ]))
alias_new_name = ::Pulumi::Simple::Resource.new("aliasNewName",
  value: true,
  opts: Pulumi::ResourceOptions.new(aliases: [
    {
      "name" => "aliasName",
    },
  ]))
alias_no_parent = ::Pulumi::Simple::Resource.new("aliasNoParent",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: parent, aliases: [
    {
      "noParent" => true,
    },
  ]))
alias_parent = ::Pulumi::Simple::Resource.new("aliasParent",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: parent, aliases: [
    {
      "parent" => alias_urn,
    },
  ]))
alias_type = ::Pulumi::Simple::Resource.new("aliasType",
  value: true,
  opts: Pulumi::ResourceOptions.new(aliases: [
    {
      "type" => "component:index:Custom",
    },
  ]))