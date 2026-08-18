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

require_relative "../resource"
require_relative "resource"
require_relative "settings"

module Pulumi
  module Runtime
    # The implicit root of every stack.
    #
    # The engine expects one resource to parent everything a program creates, and to carry
    # the stack's exported outputs. A program never constructs this itself.
    #
    # @api private
    class Stack < ComponentResource
      ROOT_TYPE = "pulumi:pulumi:Stack"

      def initialize(project, stack)
        # The root's name encodes the project and stack so that its URN is stable across
        # runs; the engine relies on that to match it to prior state.
        super(ROOT_TYPE, "#{project}-#{stack}")
      end
    end

    class << self
      # Runs a program with a root stack resource around it, then publishes its exports.
      #
      # @api private
      # @yield the user's program
      # @return [Stack]
      def run_in_stack
        stack = Stack.new(settings.project, settings.stack)
        previous_root = @root_resource
        @root_resource = stack
        @exports = {}

        begin
          yield
          stack.register_outputs(@exports)
        ensure
          @root_resource = previous_root
        end

        stack
      end

      # The resource that parents anything not given an explicit parent.
      #
      # @api private
      attr_reader :root_resource

      # The stack outputs the running program has declared so far.
      #
      # @api private
      # @return [Hash{String => Object}, nil]
      attr_reader :exports

      # The parent a resource gets when it declares none: the root stack, which is what
      # nests every resource's URN under the stack.
      #
      # The root stack itself gets nil, but not because of the identity check -- during
      # `Stack.new` the root has not been installed yet, so root_resource is still nil and
      # the check never fires. It is kept as a guard for the case where a resource somehow
      # reaches here after being installed as the root, which would otherwise parent it to
      # itself.
      #
      # @api private
      def default_parent_for(resource)
        root_resource.equal?(resource) ? nil : root_resource
      end

      # Records a stack output.
      #
      # @api private
      def export(name, value)
        raise Error, "Pulumi.export may only be called while a program is running" if @exports.nil?

        @exports[name.to_s] = value
      end

      # @api private
      def reset_stack
        @root_resource = nil
        @exports = nil
      end
    end
  end

  class << self
    # Publishes a value as a stack output, visible in `pulumi stack output` and readable
    # from other stacks via a stack reference.
    #
    #   Pulumi.export "url", cdn.domain_name.apply { |d| "https://#{d}" }
    def export(name, value)
      Runtime.export(name, value)
    end
  end
end
