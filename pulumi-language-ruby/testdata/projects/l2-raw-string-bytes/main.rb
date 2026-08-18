# frozen_string_literal: true

require "pulumi"
require "pulumi/bytesink"
require "pulumi/bytesource"

source = ::Pulumi::Bytesource::Resource.new("source",
  base64: "AGhlbGxvIID+/yB3b3JsZPAo")
sink = ::Pulumi::Bytesink::Resource.new("sink",
  bytes: source["bytes"],
  expect_base64: source["base64"])