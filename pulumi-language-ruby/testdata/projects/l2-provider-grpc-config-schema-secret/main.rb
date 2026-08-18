# frozen_string_literal: true

require "pulumi"
require "pulumi/config_grpc"

config_grpc_provider = ::Pulumi::ConfigGrpc::Providers::ConfigGrpc.new("config_grpc_provider",
  secret_string1: "SECRET",
  secret_int1: 16,
  secret_num1: 123456.789,
  secret_bool1: true,
  list_secret_string1: [
    "SECRET",
    "SECRET2",
  ],
  map_secret_string1: {
    "key1" => "SECRET",
    "key2" => "SECRET2",
  },
  obj_secret_string1: {
    "secretX" => "SECRET",
  })
config = ::Pulumi::ConfigGrpc::ConfigFetcher.new("config",
  opts: Pulumi::ResourceOptions.new(provider: config_grpc_provider))