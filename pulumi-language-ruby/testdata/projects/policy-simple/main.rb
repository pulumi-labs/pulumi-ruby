# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

res1 = ::Pulumi::Simple::Resource.new("res1",
  value: true)
res2 = ::Pulumi::Simple::Resource.new("res2",
  value: res1["value"].apply { |value| !value })