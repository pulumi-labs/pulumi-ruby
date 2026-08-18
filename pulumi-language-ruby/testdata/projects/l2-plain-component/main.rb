# frozen_string_literal: true

require "pulumi"
require "pulumi/plaincomponent"

my_component = ::Pulumi::Plaincomponent::Component.new("myComponent",
  name: "my-resource",
  settings: {
    "enabled" => true,
    "tags" => {
      "env" => "test",
    },
  })
Pulumi.export("label", my_component["label"])