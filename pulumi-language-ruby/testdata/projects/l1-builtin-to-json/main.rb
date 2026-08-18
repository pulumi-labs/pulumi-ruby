# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

a_string = config.require("aString")
a_number = config.require_float("aNumber")
a_list = config.require_object("aList")
a_secret = config.require_secret("aSecret")
Pulumi.export("stringOutput", Pulumi::Output.json_dump(a_string))
Pulumi.export("numberOutput", Pulumi::Output.json_dump(a_number))
Pulumi.export("boolOutput", Pulumi::Output.json_dump(true))
Pulumi.export("arrayOutput", Pulumi::Output.json_dump([
  "x",
  "y",
  "z",
]))
Pulumi.export("objectOutput", Pulumi::Output.json_dump({
  "key" => "value",
  "count" => 1,
}))
nested_object = {
  "anObject" => {
    "name" => a_string,
    "items" => a_list,
  },
  "a_secret" => a_secret,
}
Pulumi.export("nestedOutput", Pulumi::Output.json_dump(nested_object))