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

require_relative "output"
require_relative "resource"

module Pulumi
  # Reads another stack's outputs.
  #
  #   network = Pulumi::StackReference.new("acme/network/prod")
  #   subnet  = network.output("subnetId")
  #
  # This is a resource rather than a plain lookup because the reference is part of the
  # dependency graph: the engine has to know this stack reads that one.
  class StackReference < CustomResource
    TYPE = "pulumi:pulumi:StackReference"

    # @return [Output<String>] the fully-qualified name of the referenced stack
    attr_reader :name

    # @return [Output<Hash>] every output the referenced stack exported
    attr_reader :outputs

    # @return [Output<Array<String>>] the names of outputs the other stack marked secret
    attr_reader :secret_output_names

    # @param name [String] this reference's logical name, and by default the stack to read
    # @param stack_name [String, nil] the stack to read, if different from `name`
    # @param opts [ResourceOptions, nil]
    def initialize(name, stack_name: nil, opts: nil)
      super(TYPE, name, { name: stack_name || name }, opts)

      @name = output("name")
      @outputs = output("outputs")
      @secret_output_names = output("secretOutputNames")
    end

    # Reads one output of the referenced stack.
    #
    # The result is always an Output, and it is marked secret when the other stack marked
    # it secret -- otherwise reading a value across a stack boundary would quietly launder
    # it into plaintext.
    #
    # @param name [String, Symbol]
    # @return [Output]
    def output(name)
      return super if RESERVED_OUTPUTS.include?(name.to_s)

      key = name.to_s
      per_key_outputs.apply do |(values, secret_names)|
        value = values.is_a?(Hash) ? values[key] : nil
        Array(secret_names).include?(key) ? Output.secret(value) : value
      end
    end

    # Like {#output}, but fails rather than returning nil when the other stack does not
    # export that name.
    #
    # @return [Output]
    def require_output(name)
      key = name.to_s
      Output.all(Output.unsecret(self.name), per_key_outputs).apply do |(stack, (values, secret_names))|
        unless values.is_a?(Hash) && values.key?(key)
          raise Error, "stack '#{stack}' does not have an output named '#{key}'"
        end

        Array(secret_names).include?(key) ? Output.secret(values[key]) : values[key]
      end
    end

    # The resource's own properties, which must not be shadowed by the referenced stack's
    # outputs of the same name.
    RESERVED_OUTPUTS = %w[name outputs secretOutputNames].freeze
    private_constant :RESERVED_OUTPUTS

    private

    # The referenced stack's outputs, with secrecy stripped, paired with the list of names
    # that actually are secret.
    #
    # The map arrives secret *as a whole* -- one secret member makes the containing value
    # secret, which is the right default everywhere else. Reading a single key out of it
    # would then mark every key secret, including plainly public ones. secretOutputNames is
    # the authority on which keys are secret, so secrecy is dropped here and re-applied per
    # key by the readers above.
    def per_key_outputs
      Output.all(Output.unsecret(outputs), Output.unsecret(secret_output_names))
    end
  end
end
