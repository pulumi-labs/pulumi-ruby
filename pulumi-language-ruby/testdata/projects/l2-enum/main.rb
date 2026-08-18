# frozen_string_literal: true

require "pulumi"
require "pulumi/enum"

sink1 = ::Pulumi::Enum::Res.new("sink1",
  int_enum: 1,
  string_enum: "two")
sink2 = ::Pulumi::Enum::Mod::Res.new("sink2",
  int_enum: 1,
  string_enum: "two")
sink3 = ::Pulumi::Enum::Mod::Res.new("sink3",
  int_enum: 1,
  string_enum: "two")
sink4 = ::Pulumi::Enum::Deluxe.new("sink4",
  number_enum: 0.1,
  wordy_enum: "It's got apostrophes",
  array_of_enum: [
    "one",
    "two",
  ],
  map_of_enum: {
    "small" => 1,
    "large" => 2,
  },
  holder: {
    "size" => 2,
    "color" => "one",
  },
  union_enum: "A Value With Spaces.")