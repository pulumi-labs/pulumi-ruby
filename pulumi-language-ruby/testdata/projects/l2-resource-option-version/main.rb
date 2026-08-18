# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

with_v2 = ::Pulumi::Simple::Resource.new("withV2",
  value: true)
with_v26 = ::Pulumi::Simple::Resource.new("withV26",
  value: false)
with_default = ::Pulumi::Simple::Resource.new("withDefault",
  value: true)