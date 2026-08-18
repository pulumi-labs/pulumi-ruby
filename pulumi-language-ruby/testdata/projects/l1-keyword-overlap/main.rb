# frozen_string_literal: true

require "pulumi"

class_ = "class_output_string"
export = "export_output_string"
import = "import_output_string"
mod = "mod_output_string"
object = {
  "object" => "object_output_string",
}
self_ = "self_output_string"
this = "this_output_string"
if_ = "if_output_string"
Pulumi.export("class", class_)
Pulumi.export("export", export)
Pulumi.export("import", import)
Pulumi.export("mod", mod)
Pulumi.export("object", object)
Pulumi.export("self", self_)
Pulumi.export("this", this)
Pulumi.export("if", if_)