# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

a_number = config.require_float("aNumber")
Pulumi.export("theNumber", (a_number + 1.25))
optional_number = config.get_float("optionalNumber") || 41.5
Pulumi.export("defaultNumber", (optional_number + 1.2))
an_int = config.require_integer("anInt")
Pulumi.export("theInteger", (an_int + 4))
optional_int = config.get_integer("optionalInt") || 1
Pulumi.export("defaultInteger", (optional_int + 2))
a_string = config.require("aString")
Pulumi.export("theString", Pulumi::Output.format("%s World", a_string))
optional_string = config.get("optionalString") || "defaultStringValue"
Pulumi.export("defaultString", optional_string)
a_bool = config.require_boolean("aBool")
Pulumi.export("theBool", (!a_bool && true))
optional_bool = config.get_boolean("optionalBool")
optional_bool = false if optional_bool.nil?
Pulumi.export("defaultBool", optional_bool)