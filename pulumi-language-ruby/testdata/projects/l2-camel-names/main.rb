# frozen_string_literal: true

require "pulumi"
require "pulumi/camel_names"

first_resource = ::Pulumi::CamelNames::CoolModule::SomeResource.new("firstResource",
  the_input: true)
second_resource = ::Pulumi::CamelNames::CoolModule::SomeResource.new("secondResource",
  the_input: first_resource["theOutput"])
third_resource = ::Pulumi::CamelNames::CoolModule::SomeResource.new("thirdResource",
  the_input: true,
  resource_name: "my-cluster")