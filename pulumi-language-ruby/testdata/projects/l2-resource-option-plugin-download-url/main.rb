# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

with_default_url = ::Pulumi::Simple::Resource.new("withDefaultURL",
  value: true)
with_explicit_default_url = ::Pulumi::Simple::Resource.new("withExplicitDefaultURL",
  value: true)
with_custom_url1 = ::Pulumi::Simple::Resource.new("withCustomURL1",
  value: true)
with_custom_url2 = ::Pulumi::Simple::Resource.new("withCustomURL2",
  value: false)