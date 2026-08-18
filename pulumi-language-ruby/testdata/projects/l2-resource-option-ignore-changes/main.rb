# frozen_string_literal: true

require "pulumi"
require "pulumi/nestedobject"

receiver_ignore = ::Pulumi::Nestedobject::Receiver.new("receiverIgnore",
  details: [
    {
      "key" => "a",
      "value" => "b",
    },
  ])
map_ignore = ::Pulumi::Nestedobject::MapContainer.new("mapIgnore",
  tags: {
    "env" => "prod",
  })
no_ignore = ::Pulumi::Nestedobject::Target.new("noIgnore",
  name: "nothing")