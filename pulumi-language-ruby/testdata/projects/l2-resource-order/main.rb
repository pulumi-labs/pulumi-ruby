# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

res2 = ::Pulumi::Simple::Resource.new("res2",
  value: local_var)
res1 = ::Pulumi::Simple::Resource.new("res1",
  value: true)
Pulumi.export("out", res2["value"])
local_var = res1["value"]