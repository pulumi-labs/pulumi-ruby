# frozen_string_literal: true

require "pulumi"
require "pulumi/subpackage"

example = ::Pulumi::Subpackage::HelloWorld.new("example")
example_component = ::Pulumi::Subpackage::HelloWorldComponent.new("exampleComponent")
Pulumi.export("parameterValue", example["parameterValue"])
Pulumi.export("parameterValueFromComponent", example_component["parameterValue"])