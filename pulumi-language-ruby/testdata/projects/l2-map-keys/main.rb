# frozen_string_literal: true

require "pulumi"
require "pulumi/plain"
require "pulumi/primitive"
require "pulumi/primitive_ref"
require "pulumi/ref_ref"

prim = ::Pulumi::Primitive::Resource.new("prim",
  boolean: false,
  float: 2.17,
  integer: -12,
  string: "Goodbye",
  number_array: [
    0,
    1,
  ],
  boolean_map: {
    "my key" => false,
    "my.key" => true,
    "my-key" => false,
    "my_key" => true,
    "MY_KEY" => false,
    "myKey" => true,
  })
ref = ::Pulumi::PrimitiveRef::Resource.new("ref",
  data: {
    "boolean" => false,
    "float" => 2.17,
    "integer" => -12,
    "string" => "Goodbye",
    "boolArray" => [
      false,
      true,
    ],
    "stringMap" => {
      "my key" => "one",
      "my.key" => "two",
      "my-key" => "three",
      "my_key" => "four",
      "MY_KEY" => "five",
      "myKey" => "six",
    },
  })
rref = ::Pulumi::RefRef::Resource.new("rref",
  data: {
    "innerData" => {
      "boolean" => false,
      "float" => -2.17,
      "integer" => 123,
      "string" => "Goodbye",
      "boolArray" => [],
      "stringMap" => {
        "my key" => "one",
        "my.key" => "two",
        "my-key" => "three",
        "my_key" => "four",
        "MY_KEY" => "five",
        "myKey" => "six",
      },
    },
    "boolean" => true,
    "float" => 4.5,
    "integer" => 1024,
    "string" => "Hello",
    "boolArray" => [],
    "stringMap" => {
      "my key" => "one",
      "my.key" => "two",
      "my-key" => "three",
      "my_key" => "four",
      "MY_KEY" => "five",
      "myKey" => "six",
    },
  })
plains = ::Pulumi::Plain::Resource.new("plains",
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
        "my key" => "one",
        "my.key" => "two",
        "my-key" => "three",
        "my_key" => "four",
        "MY_KEY" => "five",
        "myKey" => "six",
      },
    },
    "boolean" => true,
    "float" => 4.5,
    "integer" => 1024,
    "string" => "Hello",
    "boolArray" => [
      true,
      false,
    ],
    "stringMap" => {
      "my key" => "one",
      "my.key" => "two",
      "my-key" => "three",
      "my_key" => "four",
      "MY_KEY" => "five",
      "myKey" => "six",
    },
  },
  non_plain_data: {
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
        "my key" => "one",
        "my.key" => "two",
        "my-key" => "three",
        "my_key" => "four",
        "MY_KEY" => "five",
        "myKey" => "six",
      },
    },
    "boolean" => true,
    "float" => 4.5,
    "integer" => 1024,
    "string" => "Hello",
    "boolArray" => [
      true,
      false,
    ],
    "stringMap" => {
      "my key" => "one",
      "my.key" => "two",
      "my-key" => "three",
      "my_key" => "four",
      "MY_KEY" => "five",
      "myKey" => "six",
    },
  })