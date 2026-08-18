# frozen_string_literal: true

require "pulumi"
require "pulumi/replaceonchanges"

schema_replace = ::Pulumi::Replaceonchanges::ResourceA.new("schemaReplace",
  value: true,
  replace_prop: false)
option_replace = ::Pulumi::Replaceonchanges::ResourceB.new("optionReplace",
  value: false)
both_replace_value = ::Pulumi::Replaceonchanges::ResourceA.new("bothReplaceValue",
  value: false,
  replace_prop: true)
both_replace_prop = ::Pulumi::Replaceonchanges::ResourceA.new("bothReplaceProp",
  value: true,
  replace_prop: false)
regular_update = ::Pulumi::Replaceonchanges::ResourceB.new("regularUpdate",
  value: false)
no_change = ::Pulumi::Replaceonchanges::ResourceB.new("noChange",
  value: true)
wrong_prop_change = ::Pulumi::Replaceonchanges::ResourceA.new("wrongPropChange",
  value: true,
  replace_prop: false)
multiple_prop_replace = ::Pulumi::Replaceonchanges::ResourceA.new("multiplePropReplace",
  value: false,
  replace_prop: true)