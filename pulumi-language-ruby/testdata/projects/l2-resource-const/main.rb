# frozen_string_literal: true

require "pulumi"
require "pulumi/constant"

first = ::Pulumi::Constant::Resource.new("first",
  kind: "Constant")
Pulumi.export("kind", first["kind"])