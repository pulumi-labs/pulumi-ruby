# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

aresource = ::Pulumi::Simple::Resource.new("aresource",
  value: true)
other = ::Pulumi::Simple::Resource.new("other",
  value: true)