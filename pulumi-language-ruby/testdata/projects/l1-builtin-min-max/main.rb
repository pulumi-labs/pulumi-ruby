# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

a = config.require_float("a")
b = config.require_float("b")
c = config.require_integer("c")
d = config.require_integer("d")
Pulumi.export("maxResult", [a, b].max)
Pulumi.export("minResult", [a, b].min)
Pulumi.export("intMaxResult", [c, d].max)
Pulumi.export("intMinResult", [c, d].min)