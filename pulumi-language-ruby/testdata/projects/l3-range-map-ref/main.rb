# frozen_string_literal: true

require "pulumi"
require "pulumi/nestedobject"

config = Pulumi.config

map_resource = ::Pulumi::Nestedobject::Target.new("mapResource",
  name: Pulumi::Output.format("%s=%s", range["key"], range["value"]))
map_target = ::Pulumi::Nestedobject::Target.new("mapTarget",
  name: map_resource["k1"]["name"].apply { |name| Pulumi::Output.format("%s+", name) })
item_map = config.require_object("itemMap")