# frozen_string_literal: true

require "pulumi"

Pulumi.export("rootDirectoryOutput", Pulumi.root_directory)