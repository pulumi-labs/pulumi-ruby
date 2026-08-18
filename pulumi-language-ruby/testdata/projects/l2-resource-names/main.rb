# frozen_string_literal: true

require "pulumi"
require "pulumi/names"

res1 = ::Pulumi::Names::ResMap.new("res1",
  value: true)
res2 = ::Pulumi::Names::ResArray.new("res2",
  value: true)
res3 = ::Pulumi::Names::ResList.new("res3",
  value: true)
res4 = ::Pulumi::Names::ResResource.new("res4",
  value: true)
res5 = ::Pulumi::Names::Mod::Res.new("res5",
  value: true)
res6 = ::Pulumi::Names::Mod::Res.new("res6",
  value: true)