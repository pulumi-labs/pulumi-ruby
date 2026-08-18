# frozen_string_literal: true

require "pulumi"
require "pulumi/nestedobject"

config = Pulumi.config

bool_resource = ::Pulumi::Nestedobject::Target.new("boolResource",
  name: "bool-resource")
bool_target = ::Pulumi::Nestedobject::Target.new("boolTarget",
  name: bool_resource["name"].apply { |name| Pulumi::Output.format("%s+", name) })
create_bool = config.require_boolean("createBool")