# frozen_string_literal: true

require "pulumi"

Pulumi.export("cwdOutput", Dir.pwd)