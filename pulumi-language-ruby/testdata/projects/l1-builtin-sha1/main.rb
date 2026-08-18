# frozen_string_literal: true

require "pulumi"
require "digest"

config = Pulumi.config

input = config.require("input")
hash = Digest::SHA1.hexdigest(input)
Pulumi.export("hash", hash)