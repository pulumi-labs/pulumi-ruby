# frozen_string_literal: true

require "pulumi"
require "pulumi/byepackage"
require "pulumi/hipackage"

example1 = ::Pulumi::Hipackage::HelloWorld.new("example1")
example_component1 = ::Pulumi::Hipackage::HelloWorldComponent.new("exampleComponent1")
example2 = ::Pulumi::Byepackage::GoodbyeWorld.new("example2")
example_component2 = ::Pulumi::Byepackage::GoodbyeWorldComponent.new("exampleComponent2")
Pulumi.export("parameterValue1", example1["parameterValue"])
Pulumi.export("parameterValueFromComponent1", example_component1["parameterValue"])
Pulumi.export("parameterValue2", example2["parameterValue"])
Pulumi.export("parameterValueFromComponent2", example_component2["parameterValue"])