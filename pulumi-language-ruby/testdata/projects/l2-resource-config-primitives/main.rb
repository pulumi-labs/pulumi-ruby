# frozen_string_literal: true

require "pulumi"
require "pulumi/primitive"

config = Pulumi.config

plain = ::Pulumi::Primitive::Resource.new("plain",
  boolean: plain_bool,
  float: plain_number,
  integer: plain_integer,
  string: plain_string,
  number_array: [
    -1,
    0,
    1,
  ],
  boolean_map: {
    "t" => true,
    "f" => false,
  })
secret = ::Pulumi::Primitive::Resource.new("secret",
  boolean: secret_bool,
  float: secret_number,
  integer: secret_integer,
  string: secret_string,
  number_array: [
    -2,
    0,
    2,
  ],
  boolean_map: {
    "t" => true,
    "f" => false,
  })
plain_bool = config.require_boolean("plainBool")
plain_number = config.require_float("plainNumber")
plain_integer = config.require_integer("plainInteger")
plain_string = config.require("plainString")
secret_bool = config.require_secret_boolean("secretBool")
secret_number = config.require_secret_float("secretNumber")
secret_integer = config.require_secret_integer("secretInteger")
secret_string = config.require_secret("secretString")