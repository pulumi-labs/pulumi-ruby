# frozen_string_literal: true

require "pulumi"

Pulumi.export("empty", {})
Pulumi.export("strings", {
  "greeting" => "Hello, world!",
  "farewell" => "Goodbye, world!",
})
Pulumi.export("adversarialStrings", {
  "__type" => "dunder type",
  "__internal" => "dunder internal",
  "__provider" => "dunder provider",
  "__version" => "dunder version",
  "" => "empty key",
  "empty value" => "",
  "dunder value" => "__dunder",
  "Some ${common} \"characters\" 'that' need escaping: \\ (backslash), \t (tab), \u{1b} (escape), \u{7} (bell), \u{0} (null), 󠀡 (tag space)" => "Some ${common} \"characters\" 'that' need escaping: \\ (backslash), \t (tab), \u{1b} (escape), \u{7} (bell), \u{0} (null), 󠀡 (tag space)",
})
Pulumi.export("numbers", {
  "1" => 1,
  "2" => 2,
})
Pulumi.export("keys", {
  "my.key" => 1,
  "my-key" => 2,
  "my_key" => 3,
  "MY_KEY" => 4,
  "mykey" => 5,
  "MYKEY" => 6,
})