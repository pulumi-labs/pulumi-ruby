# frozen_string_literal: true

require "pulumi"
require "pulumi/nestedobject"

container = ::Pulumi::Nestedobject::Container.new("container",
  inputs: [
    "alpha",
    "bravo",
  ])
map_container = ::Pulumi::Nestedobject::MapContainer.new("mapContainer",
  tags: {
    "k1" => "charlie",
    "k2" => "delta",
  })
list_output = ::Pulumi::Nestedobject::Target.new("listOutput",
  name: range["value"]["value"])
map_output = ::Pulumi::Nestedobject::Target.new("mapOutput",
  name: Pulumi::Output.format("%s=>%s", range["key"], range["value"]))