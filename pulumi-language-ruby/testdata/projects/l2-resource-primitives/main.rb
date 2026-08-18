# frozen_string_literal: true

require "pulumi"
require "pulumi/primitive"

res = ::Pulumi::Primitive::Resource.new("res",
  boolean: true,
  float: 3.14,
  integer: 42,
  string: "hello",
  number_array: [
    -1,
    0,
    1,
  ],
  boolean_map: {
    "t" => true,
    "f" => false,
  })