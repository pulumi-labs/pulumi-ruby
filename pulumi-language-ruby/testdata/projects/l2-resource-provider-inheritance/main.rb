# frozen_string_literal: true

require "pulumi"
require "pulumi/primitive"
require "pulumi/simple"

provider = ::Pulumi::Simple::Providers::Simple.new("provider")
parent1 = ::Pulumi::Simple::Resource.new("parent1",
  value: true,
  opts: Pulumi::ResourceOptions.new(provider: provider))
child1 = ::Pulumi::Simple::Resource.new("child1",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: parent1))
parent2 = ::Pulumi::Primitive::Resource.new("parent2",
  boolean: false,
  float: 0,
  integer: 0,
  string: "",
  number_array: [],
  boolean_map: {})
child2 = ::Pulumi::Simple::Resource.new("child2",
  value: true,
  opts: Pulumi::ResourceOptions.new(parent: parent2))
child3 = ::Pulumi::Primitive::Resource.new("child3",
  boolean: false,
  float: 0,
  integer: 0,
  string: "",
  number_array: [],
  boolean_map: {},
  opts: Pulumi::ResourceOptions.new(parent: parent1))