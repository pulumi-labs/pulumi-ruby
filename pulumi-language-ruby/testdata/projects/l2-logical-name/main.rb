# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

config = Pulumi.config

resource_lexical_name = ::Pulumi::Simple::Resource.new("aA-Alpha_alpha.🤯⁉️",
  value: config_lexical_name)
config_lexical_name = config.require_boolean("cC-Charlie_charlie.😃⁉️")
Pulumi.export("bB-Beta_beta.💜⁉", resource_lexical_name["value"])
Pulumi.export("dD-Delta_delta.🔥⁉", resource_lexical_name["value"])