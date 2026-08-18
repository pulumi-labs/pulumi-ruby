# frozen_string_literal: true

require "pulumi"

config = Pulumi.config

an_object = config.require_object("anObject")
any_object = config.require_object("anyObject")
l = Pulumi::Output.secret([
  1,
])
m = Pulumi::Output.secret({
  "key" => true,
})
c = Pulumi::Output.secret(an_object)
o = Pulumi::Output.secret({
  "property" => "value",
})
a = Pulumi::Output.secret(any_object)
Pulumi.export("l", l.apply { |l| l[0] })
Pulumi.export("m", m.apply { |m| m["key"] })
Pulumi.export("c", c.apply { |c| c["property"] })
Pulumi.export("o", o.apply { |o| o["property"] })
Pulumi.export("a", a.apply { |a| a["property"] })