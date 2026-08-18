# frozen_string_literal: true

require "pulumi"
require "pulumi/enum"
require "pulumi/extenumref"

my_res = ::Pulumi::Enum::Res.new("myRes",
  int_enum: 1,
  string_enum: "one")
my_sink = ::Pulumi::Extenumref::Sink.new("mySink",
  string_enum: "two")