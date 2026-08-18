# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

target = ::Pulumi::Simple::Resource.new("target",
  value: true)
replace_with = ::Pulumi::Simple::Resource.new("replaceWith",
  value: true)
not_replace_with = ::Pulumi::Simple::Resource.new("notReplaceWith",
  value: true)