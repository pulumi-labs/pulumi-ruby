# frozen_string_literal: true

require "pulumi"
require "pulumi/discriminated_union"

example1 = ::Pulumi::DiscriminatedUnion::Example.new("example1",
  union_of: {
    "discriminantKind" => "variant1",
    "field1" => "v1 union",
  },
  array_of_union_of: [
    {
      "discriminantKind" => "variant1",
      "field1" => "v1 array(union)",
    },
  ])
example2 = ::Pulumi::DiscriminatedUnion::Example.new("example2",
  union_of: {
    "discriminantKind" => "variant2",
    "field2" => "v2 union",
  },
  array_of_union_of: [
    {
      "discriminantKind" => "variant2",
      "field2" => "v2 array(union)",
    },
    {
      "discriminantKind" => "variant1",
      "field1" => "v1 array(union)",
    },
  ])