# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

target_only = ::Pulumi::Simple::Resource.new("targetOnly",
  value: true)
unrelated = ::Pulumi::Simple::Resource.new("unrelated",
  value: true)