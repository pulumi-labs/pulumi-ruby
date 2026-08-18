# frozen_string_literal: true

require "pulumi"
require "pulumi/optional_primitive_ref"

set_res = ::Pulumi::OptionalPrimitiveRef::Resource.new("setRes",
  data: {
    "boolean" => true,
    "float" => 3.14,
    "integer" => 42,
    "string" => "hello",
    "numberArray" => [
      -1,
      0,
      1,
    ],
    "booleanMap" => {
      "t" => true,
      "f" => false,
    },
  },
  optional_data: {
    "string" => "optional parent",
  })
unset_res = ::Pulumi::OptionalPrimitiveRef::Resource.new("unsetRes",
  data: {})
from_nested_optional = ::Pulumi::OptionalPrimitiveRef::Resource.new("fromNestedOptional",
  data: {
    "string" => set_res["optionalData"].apply { |optional_data| optional_data["string"] },
  })
Pulumi.export("setBoolean", set_res["data"].apply { |data| data["boolean"] })
Pulumi.export("setFloat", set_res["data"].apply { |data| data["float"] })
Pulumi.export("setInteger", set_res["data"].apply { |data| data["integer"] })
Pulumi.export("setString", set_res["data"].apply { |data| data["string"] })
Pulumi.export("setNumberArray", set_res["data"].apply { |data| data["numberArray"] })
Pulumi.export("setBooleanMap", set_res["data"].apply { |data| data["booleanMap"] })
Pulumi.export("unsetBoolean", unset_res["data"].apply { |data| ((data["boolean"] == nil) ? "null" : "not null") })
Pulumi.export("unsetFloat", unset_res["data"].apply { |data| ((data["float"] == nil) ? "null" : "not null") })
Pulumi.export("unsetInteger", unset_res["data"].apply { |data| ((data["integer"] == nil) ? "null" : "not null") })
Pulumi.export("unsetString", unset_res["data"].apply { |data| ((data["string"] == nil) ? "null" : "not null") })
Pulumi.export("unsetNumberArray", unset_res["data"].apply { |data| ((data["numberArray"] == nil) ? "null" : "not null") })
Pulumi.export("unsetBooleanMap", unset_res["data"].apply { |data| ((data["booleanMap"] == nil) ? "null" : "not null") })