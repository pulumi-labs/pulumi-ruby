# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

with_v2 = ::Pulumi::Simple::Resource.new("withV2",
  value: true)