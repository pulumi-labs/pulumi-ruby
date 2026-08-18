# frozen_string_literal: true

require "pulumi"
require "pulumi/primitive"

config = Pulumi.config

plain = ::Pulumi::Primitive::Resource.new("plain",
  boolean: true,
  float: 3.5,
  integer: 3,
  string: "plain",
  number_array: plain_number_array,
  boolean_map: plain_boolean_map)
secret = ::Pulumi::Primitive::Resource.new("secret",
  boolean: true,
  float: 3.5,
  integer: 3,
  string: "secret",
  number_array: secret_number_array,
  boolean_map: secret_boolean_map)
plain_number_array = config.require_object("plainNumberArray")
plain_boolean_map = config.require_object("plainBooleanMap")
secret_number_array = config.require_secret_object("secretNumberArray")
secret_boolean_map = config.require_secret_object("secretBooleanMap")