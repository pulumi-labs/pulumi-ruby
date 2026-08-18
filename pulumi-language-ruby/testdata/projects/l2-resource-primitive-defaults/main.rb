# frozen_string_literal: true

require "pulumi"
require "pulumi/primitive_defaults"

res_explicit = ::Pulumi::PrimitiveDefaults::Resource.new("resExplicit",
  boolean: true,
  float: 3.14,
  integer: 42,
  string: "hello")
res_defaulted = ::Pulumi::PrimitiveDefaults::Resource.new("resDefaulted")