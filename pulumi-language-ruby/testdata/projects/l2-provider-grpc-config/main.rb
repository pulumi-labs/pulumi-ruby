# frozen_string_literal: true

require "pulumi"
require "pulumi/config_grpc"

config_grpc_provider = ::Pulumi::ConfigGrpc::Providers::ConfigGrpc.new("config_grpc_provider",
  string1: "",
  string2: "x",
  string3: "{}",
  int1: 0,
  int2: 42,
  num1: 0,
  num2: 42.42,
  bool1: true,
  bool2: false,
  list_string1: [],
  list_string2: [
    "",
    "foo",
  ],
  list_int1: [
    1,
    2,
  ],
  map_string1: {},
  map_string2: {
    "key1" => "value1",
    "key2" => "value2",
  },
  map_int1: {
    "key1" => 0,
    "key2" => 42,
  },
  obj_string1: {},
  obj_string2: {
    "x" => "x-value",
  },
  obj_int1: {
    "x" => 42,
  })
config = ::Pulumi::ConfigGrpc::ConfigFetcher.new("config",
  opts: Pulumi::ResourceOptions.new(provider: config_grpc_provider))