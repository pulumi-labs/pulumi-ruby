# frozen_string_literal: true

require "pulumi"
require "pulumi/extbase"
require "pulumi/myext"

greeting = ::Pulumi::Myext::Greeting.new("greeting")
base = ::Pulumi::Extbase::Base.new("base")
Pulumi.export("parameterValue", greeting["parameterValue"])
Pulumi.export("baseValue", base["baseValue"])