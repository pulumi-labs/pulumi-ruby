# frozen_string_literal: true

require "pulumi"
require "pulumi/nestedobject"

config = Pulumi.config

num_resource = ::Pulumi::Nestedobject::Target.new("numResource",
  name: Pulumi::Output.format("num-%s", range["value"]))
num_target = ::Pulumi::Nestedobject::Target.new("numTarget",
  name: num_resource[0]["name"].apply { |name| Pulumi::Output.format("%s+", name) })
list_resource = ::Pulumi::Nestedobject::Target.new("listResource",
  name: Pulumi::Output.format("%s:%s", range["key"], range["value"]))
list_target = ::Pulumi::Nestedobject::Target.new("listTarget",
  name: list_resource[1]["name"].apply { |name| Pulumi::Output.format("%s+", name) })
list_dyn_target = ::Pulumi::Nestedobject::Target.new("listDynTarget",
  name: list_resource[range["key"]]["name"].apply { |name| Pulumi::Output.format("%s!", name) })
num_items = config.require_integer("numItems")
item_list = config.require_object("itemList")