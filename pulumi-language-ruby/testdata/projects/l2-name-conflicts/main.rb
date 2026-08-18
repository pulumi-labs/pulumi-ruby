# frozen_string_literal: true

require "pulumi"
require "pulumi/module_format"
require "pulumi/names"

config = Pulumi.config

names_resource = ::Pulumi::Names::Mod::Res.new("namesResource",
  value: names)
mod_resource = ::Pulumi::ModuleFormat::ModResource::Resource.new("modResource",
  text: Pulumi::Output.format("%s-%s", mod, mod))
names = config.get_boolean("names")
names = true if names.nil?
names = config.get_boolean("Names")
names = true if names.nil?
mod = config.get("mod") || "module"
mod = config.get("Mod") || "format"
Pulumi.export("namesResourceVal", names_resource["value"])
Pulumi.export("modResourceText", mod_resource["text"])
Pulumi.export("nameVariables", (names && names))
Pulumi.export("modVariables", Pulumi::Output.format("%s-%s", mod, mod))