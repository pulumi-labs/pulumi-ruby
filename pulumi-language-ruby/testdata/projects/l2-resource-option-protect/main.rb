# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

protected = ::Pulumi::Simple::Resource.new("protected",
  value: true,
  opts: Pulumi::ResourceOptions.new(protect: true))
unprotected = ::Pulumi::Simple::Resource.new("unprotected",
  value: true,
  opts: Pulumi::ResourceOptions.new(protect: false))
defaulted = ::Pulumi::Simple::Resource.new("defaulted",
  value: true)