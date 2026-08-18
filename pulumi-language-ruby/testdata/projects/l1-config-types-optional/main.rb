# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

names = config.get_object("names") || [
  nil,
  "hello",
  nil,
]
Pulumi.export("namesLength", names.length)