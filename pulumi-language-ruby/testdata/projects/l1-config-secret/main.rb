# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

a_number = config.require_secret_float("aNumber")
Pulumi.export("roundtrip", a_number)
Pulumi.export("theSecretNumber", a_number.apply { |a_number| (a_number + 1.25) })