# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

a_map = config.require_object("aMap")
Pulumi.export("theMap", {
  "a" => (a_map["a"] + 1),
  "b" => (a_map["b"] + 1),
})
an_object = config.require_object("anObject")
Pulumi.export("theObject", an_object["prop"][0])
any_object = config.require_object("anyObject")
Pulumi.export("theThing", (any_object["a"] + any_object["b"]))
optional_untyped_object = config.get_object("optionalUntypedObject") || {
  "key" => "value",
}
Pulumi.export("defaultUntypedObject", optional_untyped_object)
optional_list = config.get_object("optionalList") || nil
optional_map = config.get_object("optionalMap") || nil
optional_object = config.get_object("optionalObject") || nil
Pulumi.export("optionalList", ((optional_list == nil) ? "null" : Pulumi::Output.json_dump(optional_list)))
Pulumi.export("optionalMap", ((optional_map == nil) ? "null" : Pulumi::Output.json_dump(optional_map)))
Pulumi.export("optionalObject", ((optional_object == nil) ? "null" : Pulumi::Output.json_dump(optional_object)))