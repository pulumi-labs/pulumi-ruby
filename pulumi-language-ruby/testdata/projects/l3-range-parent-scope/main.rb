# frozen_string_literal: true

require "pulumi"
require "pulumi/nestedobject"

config = Pulumi.config

item = ::Pulumi::Nestedobject::Target.new("item",
  name: Pulumi::Output.format("%s-%s", prefix, range["value"]))
prefix = config.require("prefix")