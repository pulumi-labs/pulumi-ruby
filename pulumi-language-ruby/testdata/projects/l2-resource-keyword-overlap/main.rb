# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

class_ = ::Pulumi::Simple::Resource.new("class",
  value: true)
export = ::Pulumi::Simple::Resource.new("export",
  value: true)
mod = ::Pulumi::Simple::Resource.new("mod",
  value: true)
import = ::Pulumi::Simple::Resource.new("import",
  value: true)
object = ::Pulumi::Simple::Resource.new("object",
  value: true)
self_ = ::Pulumi::Simple::Resource.new("self",
  value: true)
this = ::Pulumi::Simple::Resource.new("this",
  value: true)
if_ = ::Pulumi::Simple::Resource.new("if",
  value: true)
Pulumi.export("class", class_)
Pulumi.export("export", export)
Pulumi.export("mod", mod)
Pulumi.export("object", object)
Pulumi.export("self", self_)
Pulumi.export("this", this)
Pulumi.export("if", if_)