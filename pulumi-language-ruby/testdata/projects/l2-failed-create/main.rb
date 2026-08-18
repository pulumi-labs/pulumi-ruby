# frozen_string_literal: true

require "pulumi"
require "pulumi/fail_on_create"
require "pulumi/simple"

failing = ::Pulumi::FailOnCreate::Resource.new("failing",
  value: false)
dependent = ::Pulumi::Simple::Resource.new("dependent",
  value: true,
  opts: Pulumi::ResourceOptions.new(depends_on: [
    failing,
  ]))
dependent_on_output = ::Pulumi::Simple::Resource.new("dependent_on_output",
  value: failing["value"])
independent = ::Pulumi::Simple::Resource.new("independent",
  value: true)
double_dependency = ::Pulumi::Simple::Resource.new("double_dependency",
  value: true,
  opts: Pulumi::ResourceOptions.new(depends_on: [
    independent,
    dependent_on_output,
  ]))