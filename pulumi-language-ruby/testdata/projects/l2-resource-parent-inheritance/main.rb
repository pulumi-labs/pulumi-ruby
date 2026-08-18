# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

provider = ::Pulumi::Simple::Providers::Simple.new("provider")
parent1 = ::Pulumi::Simple::Resource.new("parent1",
  value: true,
  opts: Pulumi::ResourceOptions.new(provider: provider))
child1 = ::Pulumi::Simple::Resource.new("child1",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: parent1))
orphan1 = ::Pulumi::Simple::Resource.new("orphan1",
  value: true)
parent2 = ::Pulumi::Simple::Resource.new("parent2",
  value: true,
  opts: Pulumi::ResourceOptions.new(protect: true, retain_on_delete: true))
child2 = ::Pulumi::Simple::Resource.new("child2",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: parent2))
child3 = ::Pulumi::Simple::Resource.new("child3",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: parent2, protect: false, retain_on_delete: false))
orphan2 = ::Pulumi::Simple::Resource.new("orphan2",
  value: true)