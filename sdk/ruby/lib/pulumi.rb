# Copyright 2026, Pulumi Corporation.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# frozen_string_literal: true

require_relative "pulumi/version"
require_relative "pulumi/errors"
require_relative "pulumi/output"
require_relative "pulumi/asset"
require_relative "pulumi/dsl_proxy"
require_relative "pulumi/args"
require_relative "pulumi/resource_options"
require_relative "pulumi/resource"
require_relative "pulumi/invoke"
require_relative "pulumi/stack_reference"
require_relative "pulumi/config"
require_relative "pulumi/log"
require_relative "pulumi/runtime/proto"
require_relative "pulumi/runtime/rpc"
require_relative "pulumi/runtime/rpc_manager"
require_relative "pulumi/runtime/settings"
require_relative "pulumi/runtime/resource"
require_relative "pulumi/runtime/invoke"
require_relative "pulumi/runtime/stack"
require_relative "pulumi/runtime/main"
require_relative "pulumi/testing"

# Pulumi's infrastructure as code SDK for Ruby.
#
# A Pulumi program is an ordinary Ruby program. It declares resources by constructing
# objects; the engine works out what to create, update, or delete by diffing the
# resulting graph against the last known state.
#
#   require "pulumi"
#
#   config = Pulumi.config
#   pet = Pulumi::CustomResource.new(
#     "random:index/randomPet:RandomPet", "pet", { length: config.get_integer("length") || 2 })
#
#   Pulumi.export "name", pet.output("id")
#
# Values a provider computes are represented as {Pulumi::Output}. Reach inside one with
# {Pulumi::Output#apply}; there is no way to read it synchronously, because during a
# preview there may be nothing there to read.
module Pulumi
  class << self
    # @return [String] the name of the running project
    def project
      Runtime.settings.project
    end

    # @return [String] the name of the running stack
    def stack
      Runtime.settings.stack
    end

    # @return [String] the organization the stack belongs to
    def organization
      Runtime.settings.organization
    end

    # @return [Boolean] true during `pulumi preview`, false during `pulumi up`
    def dry_run?
      Runtime.settings.dry_run?
    end

    # @return [String, nil] the directory holding Pulumi.yaml, or nil outside a deployment
    def root_directory
      Runtime.settings.root_directory
    end

    # Asserts that the engine running this program satisfies a semver range.
    #
    # A program that needs a feature added in a particular CLI version says so here rather
    # than failing obscurely later on. The engine owns the comparison, so the range syntax
    # is whatever it accepts.
    #
    # @param range [String] a semver range, e.g. ">=3.100.0"
    # @raise [Error] if the engine is outside the range
    def require_version(range)
      Runtime.require_version(range)
    end
  end
end
