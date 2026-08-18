# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

input = config.require("input")
bytes = input.unpack1("m")
Pulumi.export("data", bytes)
Pulumi.export("roundtrip", [bytes].pack("m0"))