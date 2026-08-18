# frozen_string_literal: true

require "pulumi"
require "pulumi/large"

res = ::Pulumi::Large::String.new("res",
  value: "hello world")
Pulumi.export("output", res["value"])