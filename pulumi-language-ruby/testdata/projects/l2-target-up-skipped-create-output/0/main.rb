# frozen_string_literal: true

require "pulumi"
require "pulumi/nestedobject"
require "pulumi/simple"

target = ::Pulumi::Simple::Resource.new("target",
  value: true)
other = ::Pulumi::Nestedobject::Container.new("other",
  inputs: [
    "a",
  ])