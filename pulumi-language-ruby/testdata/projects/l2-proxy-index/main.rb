# frozen_string_literal: true

require "pulumi"
require "pulumi/ref_ref"

res = ::Pulumi::RefRef::Resource.new("res",
  data: {
    "innerData" => {
      "boolean" => false,
      "float" => 2.17,
      "integer" => -12,
      "string" => "Goodbye",
      "boolArray" => [
        false,
        true,
      ],
      "stringMap" => {
        "two" => "turtle doves",
        "three" => "french hens",
      },
    },
    "boolean" => true,
    "float" => 4.5,
    "integer" => 1024,
    "string" => "Hello",
    "boolArray" => [
      true,
    ],
    "stringMap" => {
      "x" => "100",
      "y" => "200",
    },
    "innerDataList" => [
      {
        "boolean" => false,
        "float" => 3.14,
        "integer" => 42,
        "string" => "Partridge",
        "boolArray" => [
          true,
        ],
        "stringMap" => {
          "one" => "in a pear tree",
        },
      },
    ],
  })
Pulumi.export("bool", res["data"].apply { |data| data["boolean"] })
Pulumi.export("array", res["data"].apply { |data| data["boolArray"][0] })
Pulumi.export("map", res["data"].apply { |data| data["stringMap"]["x"] })
Pulumi.export("nested", res["data"].apply { |data| data["innerData"]["stringMap"]["three"] })
Pulumi.export("listIndex", res["data"].apply { |data| data["innerDataList"][0]["string"] })