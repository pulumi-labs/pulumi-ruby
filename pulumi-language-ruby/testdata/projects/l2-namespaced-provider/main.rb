# frozen_string_literal: true

require "pulumi"
require "pulumi/component"
require "pulumi/namespaced"

component_res = ::Pulumi::Component::ComponentCustomRefOutput.new("componentRes",
  value: "foo-bar-baz")
res = ::Pulumi::Namespaced::Resource.new("res",
  value: true,
  resource_ref: component_res["ref"])