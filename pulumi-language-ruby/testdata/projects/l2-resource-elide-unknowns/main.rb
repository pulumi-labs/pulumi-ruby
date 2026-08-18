# frozen_string_literal: true

require "pulumi"
require "pulumi/output"
require "pulumi/simple"

prov = ::Pulumi::Output::Providers::Output.new("prov",
  elide_unknowns: true)
unknown = ::Pulumi::Output::Resource.new("unknown",
  value: 1,
  opts: Pulumi::ResourceOptions.new(provider: prov))
complex = ::Pulumi::Output::ComplexResource.new("complex",
  value: 1,
  opts: Pulumi::ResourceOptions.new(provider: prov))
res = ::Pulumi::Simple::Resource.new("res",
  value: unknown["output"].apply { |output| (output == "hello") })
res_array = ::Pulumi::Simple::Resource.new("resArray",
  value: complex["outputArray"].apply { |output_array| (output_array[0] == "hello") })
res_map = ::Pulumi::Simple::Resource.new("resMap",
  value: complex["outputMap"].apply { |output_map| (output_map["x"] == "hello") })
res_object = ::Pulumi::Simple::Resource.new("resObject",
  value: complex["outputObject"].apply { |output_object| (output_object["output"] == "hello") })
Pulumi.export("out", unknown["output"])
Pulumi.export("outArray", complex["outputArray"].apply { |output_array| output_array[0] })
Pulumi.export("outMap", complex["outputMap"].apply { |output_map| output_map["x"] })
Pulumi.export("outObject", complex["outputObject"].apply { |output_object| output_object["output"] })