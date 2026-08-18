# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

with_option = ::Pulumi::Simple::Resource.new("withOption",
  value: true)
without_option = ::Pulumi::Simple::Resource.new("withoutOption",
  value: true)