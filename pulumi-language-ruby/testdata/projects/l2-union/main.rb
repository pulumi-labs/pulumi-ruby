# frozen_string_literal: true

require "pulumi"
require "pulumi/union"

string_or_integer_example1 = ::Pulumi::Union::Example.new("stringOrIntegerExample1",
  string_or_integer_property: 42)
string_or_integer_example2 = ::Pulumi::Union::Example.new("stringOrIntegerExample2",
  string_or_integer_property: "forty two")
map_map_union_example = ::Pulumi::Union::Example.new("mapMapUnionExample",
  map_map_union_property: {
    "key1" => {
      "key1a" => "value1a",
    },
  })
string_enum_union_list_example = ::Pulumi::Union::Example.new("stringEnumUnionListExample",
  string_enum_union_list_property: [
    "Listen",
    "Send",
    "NotAnEnumValue",
  ])
safe_enum_example = ::Pulumi::Union::Example.new("safeEnumExample",
  typed_enum_property: "Block")
enum_output_example = ::Pulumi::Union::EnumOutput.new("enumOutputExample",
  name: "example")
output_enum_example = ::Pulumi::Union::Example.new("outputEnumExample",
  typed_enum_property: enum_output_example["type"])
Pulumi.export("mapMapUnionOutput", map_map_union_example["mapMapUnionProperty"])