# frozen_string_literal: true

require "pulumi"
require "pulumi/optionalprimitive"
require "pulumi/primitive"

unset_a = ::Pulumi::Optionalprimitive::Resource.new("unsetA")
unset_b = ::Pulumi::Optionalprimitive::Resource.new("unsetB",
  boolean: unset_a["boolean"],
  float: unset_a["float"],
  integer: unset_a["integer"],
  string: unset_a["string"],
  number_array: unset_a["numberArray"],
  boolean_map: unset_a["booleanMap"])
set_a = ::Pulumi::Optionalprimitive::Resource.new("setA",
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
set_b = ::Pulumi::Optionalprimitive::Resource.new("setB",
  boolean: set_a["boolean"],
  float: set_a["float"],
  integer: set_a["integer"],
  string: set_a["string"],
  number_array: set_a["numberArray"],
  boolean_map: set_a["booleanMap"])
source_primitive = ::Pulumi::Primitive::Resource.new("sourcePrimitive",
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
from_primitive = ::Pulumi::Optionalprimitive::Resource.new("fromPrimitive",
  boolean: source_primitive["boolean"],
  float: source_primitive["float"],
  integer: source_primitive["integer"],
  string: source_primitive["string"],
  number_array: source_primitive["numberArray"],
  boolean_map: source_primitive["booleanMap"])
Pulumi.export("unsetBoolean", unset_b["boolean"].apply { |boolean| ((boolean == nil) ? "null" : "not null") })
Pulumi.export("unsetFloat", unset_b["float"].apply { |float| ((float == nil) ? "null" : "not null") })
Pulumi.export("unsetInteger", unset_b["integer"].apply { |integer| ((integer == nil) ? "null" : "not null") })
Pulumi.export("unsetString", unset_b["string"].apply { |string| ((string == nil) ? "null" : "not null") })
Pulumi.export("unsetNumberArray", unset_b["numberArray"].apply { |number_array| ((number_array == nil) ? "null" : "not null") })
Pulumi.export("unsetBooleanMap", unset_b["booleanMap"].apply { |boolean_map| ((boolean_map == nil) ? "null" : "not null") })
Pulumi.export("setBoolean", set_b["boolean"])
Pulumi.export("setFloat", set_b["float"])
Pulumi.export("setInteger", set_b["integer"])
Pulumi.export("setString", set_b["string"])
Pulumi.export("setNumberArray", set_b["numberArray"])
Pulumi.export("setBooleanMap", set_b["booleanMap"])