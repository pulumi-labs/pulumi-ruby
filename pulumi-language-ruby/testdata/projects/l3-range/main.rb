# frozen_string_literal: true

require "pulumi"
require "pulumi/nestedobject"

config = Pulumi.config

num_resource = ::Pulumi::Nestedobject::Target.new("numResource",
  name: Pulumi::Output.format("num-%s", range["value"]))
list_resource = ::Pulumi::Nestedobject::Target.new("listResource",
  name: Pulumi::Output.format("%s:%s", range["key"], range["value"]))
map_resource = ::Pulumi::Nestedobject::Target.new("mapResource",
  name: Pulumi::Output.format("%s=%s", range["key"], range["value"]))
bool_resource = ::Pulumi::Nestedobject::Target.new("boolResource",
  name: "bool-resource")
num_items = config.require_integer("numItems")
item_list = config.require_object("itemList")
item_map = config.require_object("itemMap")
create_bool = config.require_boolean("createBool")