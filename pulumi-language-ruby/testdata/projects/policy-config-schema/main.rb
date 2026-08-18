# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

res_y = ::Pulumi::Simple::Resource.new("resY",
  value: true)
res_n = ::Pulumi::Simple::Resource.new("resN",
  value: false)