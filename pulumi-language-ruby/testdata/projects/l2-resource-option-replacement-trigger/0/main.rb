# frozen_string_literal: true

require "pulumi"
require "pulumi/output"
require "pulumi/simple"

replacement_trigger = ::Pulumi::Simple::Resource.new("replacementTrigger",
  value: true)
unknown = ::Pulumi::Output::Resource.new("unknown",
  value: 1)
unknown_replacement_trigger = ::Pulumi::Simple::Resource.new("unknownReplacementTrigger",
  value: true)
not_replacement_trigger = ::Pulumi::Simple::Resource.new("notReplacementTrigger",
  value: true)
secret_replacement_trigger = ::Pulumi::Simple::Resource.new("secretReplacementTrigger",
  value: true)