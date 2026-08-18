# frozen_string_literal: true

require "pulumi"
require "pulumi/component"

component1 = ::Pulumi::Component::ComponentCustomRefOutput.new("component1",
  value: "foo-bar-baz")
component2 = ::Pulumi::Component::ComponentCustomRefInputOutput.new("component2",
  input_ref: component1["ref"])
custom1 = ::Pulumi::Component::Custom.new("custom1",
  value: component2["inputRef"].apply { |input_ref| input_ref["value"] })
custom2 = ::Pulumi::Component::Custom.new("custom2",
  value: component2["outputRef"].apply { |output_ref| output_ref["value"] })