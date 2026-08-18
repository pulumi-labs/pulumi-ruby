# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

prov = ::Pulumi::Simple::Providers::Simple.new("prov")