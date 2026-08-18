# frozen_string_literal: true

require "pulumi"
require "pulumi/component"

explicit = ::Pulumi::Component::Providers::Component.new("explicit")
list = ::Pulumi::Component::ComponentCallable.new("list",
  value: "value",
  opts: Pulumi::ResourceOptions.new(providers: [
    explicit,
  ]))
map = ::Pulumi::Component::ComponentCallable.new("map",
  value: "value",
  opts: Pulumi::ResourceOptions.new(providers: {
    "component" => explicit,
  }))