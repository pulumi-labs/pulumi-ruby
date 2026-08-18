# frozen_string_literal: true

require "pulumi"

Pulumi.export("zero", 0)
Pulumi.export("one", 1)
Pulumi.export("e", 2.718)
Pulumi.export("minInt32", -2147483648)
Pulumi.export("max", 1.7976931348623157e+308)
Pulumi.export("min", 5e-324)