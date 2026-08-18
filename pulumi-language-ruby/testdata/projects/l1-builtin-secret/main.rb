# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

a_secret = config.require_secret("aSecret")
not_secret = config.require("notSecret")
Pulumi.export("roundtripSecret", a_secret)
Pulumi.export("roundtripNotSecret", not_secret)
Pulumi.export("double", Pulumi::Output.secret(a_secret))
Pulumi.export("open", Pulumi::Output.unsecret(a_secret))
Pulumi.export("close", Pulumi::Output.secret(not_secret))