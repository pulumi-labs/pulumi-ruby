# frozen_string_literal: true

require "pulumi"
require "pulumi/component"

component1 = ::Pulumi::Component::ComponentCustomRefOutput.new("component1",
  value: "foo-bar-baz")
custom1 = ::Pulumi::Component::Custom.new("custom1",
  value: component1["value"])
custom2 = ::Pulumi::Component::Custom.new("custom2",
  value: component1["ref"].apply { |ref| ref["value"] })