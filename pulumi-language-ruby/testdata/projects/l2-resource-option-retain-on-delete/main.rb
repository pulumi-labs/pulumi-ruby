# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

retain_on_delete = ::Pulumi::Simple::Resource.new("retainOnDelete",
  value: true,
  opts: Pulumi::ResourceOptions.new(retain_on_delete: true))
not_retain_on_delete = ::Pulumi::Simple::Resource.new("notRetainOnDelete",
  value: true,
  opts: Pulumi::ResourceOptions.new(retain_on_delete: false))
defaulted = ::Pulumi::Simple::Resource.new("defaulted",
  value: true)