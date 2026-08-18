# frozen_string_literal: true

require "pulumi"
require "pulumi/primitive"

source1 = ::Pulumi::Primitive::Resource.new("source1",
  boolean: false,
  float: 1,
  integer: 2,
  string: "1234",
  number_array: [
    3,
  ],
  boolean_map: {
    "source" => false,
  })
source2 = ::Pulumi::Primitive::Resource.new("source2",
  boolean: false,
  float: 1,
  integer: 2,
  string: "true",
  number_array: [
    3,
  ],
  boolean_map: {
    "source" => false,
  })
sink1 = ::Pulumi::Primitive::Resource.new("sink1",
  boolean: false,
  float: id_map["source1Token"],
  integer: id_map["source1Token"],
  string: id_map["source1Token"],
  number_array: [
    id_map["source1Token"],
  ],
  boolean_map: {
    "sink" => false,
  })
sink2 = ::Pulumi::Primitive::Resource.new("sink2",
  boolean: id_map["source2Token"],
  float: 1,
  integer: 2,
  string: "abc",
  number_array: [
    3,
  ],
  boolean_map: {
    "sink" => id_map["source2Token"],
  })
id_map = {
  "source1Token" => source1["id"],
  "source2Token" => source2["id"],
}
Pulumi.export("ids", id_map)
Pulumi.export("base64", sink2["id"].apply { |id| [id].pack("m0") })