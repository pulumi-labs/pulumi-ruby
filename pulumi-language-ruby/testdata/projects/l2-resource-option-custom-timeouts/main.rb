# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

config = Pulumi.config

no_timeouts = ::Pulumi::Simple::Resource.new("noTimeouts",
  value: true)
create_only = ::Pulumi::Simple::Resource.new("createOnly",
  value: true)
update_only = ::Pulumi::Simple::Resource.new("updateOnly",
  value: true)
delete_only = ::Pulumi::Simple::Resource.new("deleteOnly",
  value: true)
read_only = ::Pulumi::Simple::Resource.new("readOnly",
  value: true)
all_timeouts = ::Pulumi::Simple::Resource.new("allTimeouts",
  value: true)
config_timeout = ::Pulumi::Simple::Resource.new("configTimeout",
  value: true)
create_timeout = config.require("createTimeout")