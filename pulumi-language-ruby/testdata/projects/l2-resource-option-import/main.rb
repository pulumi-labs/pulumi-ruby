# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

import = ::Pulumi::Simple::Resource.new("import",
  value: true)
not_import = ::Pulumi::Simple::Resource.new("notImport",
  value: true)