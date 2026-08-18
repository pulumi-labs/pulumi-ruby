# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

res1 = ::Pulumi::Simple::Resource.new("res1",
  value: true)