# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

target = ::Pulumi::Simple::Resource.new("target",
  value: true)
other = ::Pulumi::Simple::Resource.new("other",
  value: true)