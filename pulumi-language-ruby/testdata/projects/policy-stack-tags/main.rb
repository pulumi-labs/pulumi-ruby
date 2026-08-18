# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

res = ::Pulumi::Simple::Resource.new("res",
  value: true)