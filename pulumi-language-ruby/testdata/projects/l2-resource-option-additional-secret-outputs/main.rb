# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

with_secret = ::Pulumi::Simple::Resource.new("withSecret",
  value: true)
without_secret = ::Pulumi::Simple::Resource.new("withoutSecret",
  value: true)