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

require_relative "dsl_proxy"
require_relative "errors"

module Pulumi
  # The inputs to a resource, and the one place the three ways of supplying them are
  # reconciled.
  #
  #   # 1. Keyword arguments -- the canonical form.
  #   Bucket.new("assets", acl: "private", versioning: { enabled: true })
  #
  #   # 2. A block with an explicit receiver, Ruby's `yield self` idiom.
  #   Bucket.new("assets") { |b| b.acl = "private" }
  #
  #   # 3. A block without one, for those coming from Chef.
  #   Bucket.new("assets") { acl "private" }
  #
  # All three end up calling the same constructor with the same hash. Generated SDKs
  # declare their properties with {property} and get all three for free -- the block
  # handling lives here, once, rather than being emitted per resource.
  #
  # Declaring properties is also what buys typo detection, since an undeclared name has
  # nowhere to go:
  #
  #   Bucket.new("assets", acl: "private", verisoning: true)
  #   # => ArgumentError: unknown property :verisoning for BucketArgs
  class Args
    class << self
      # Declares a property, generating both an `acl = value` writer and an `acl value`
      # DSL writer.
      #
      # define_method rather than method_missing: it is an order of magnitude faster, the
      # methods are visible to `respond_to?`, ruby-lsp and YARD, and a misspelling raises
      # instead of being quietly accepted.
      def property(name)
        declared_properties << name.to_sym

        define_method(:"#{name}=") { |value| @values[name.to_sym] = value }
        define_method(name) do |*args|
          # Arity distinguishes read from write, which is what lets form 3 read as a DSL.
          # Unlike Chef's set_or_return this is generated from a declaration rather than
          # hand-written per property, so the two spellings cannot drift apart.
          return @values[name.to_sym] if args.empty?

          @values[name.to_sym] = args.first
          self
        end
      end

      # @return [Array<Symbol>] every property declared on this class and its ancestors
      def declared_properties
        @declared_properties ||= superclass.respond_to?(:declared_properties) ? superclass.declared_properties.dup : []
      end

      # Whether this class accepts properties it has not declared. Only {OpenArgs} does.
      def open?
        false
      end

      # Builds an args object from keyword arguments and/or a block.
      #
      # @param values [Hash] properties supplied as keyword arguments
      # @param block [Proc, nil] a configuration block in either supported form
      # @return [Args]
      def build(values = {}, &block)
        args = new(**values)
        return args unless block

        # A block that declares a parameter wants the object handed to it; one that takes
        # none wants to be run against it. Dispatching on arity is a long-standing Ruby
        # idiom (Rake, RSpec and ActiveSupport all do it).
        #
        # The test is `!= 0` rather than `> 0` so that a Symbol#to_proc block -- arity -2,
        # and with no binding to fall back to -- is handed the object rather than reaching
        # DSLProxy and failing with "Can't create Binding from C level Proc".
        return args.tap { |a| block.call(a) } unless block.arity.zero?

        DSLProxy.new(args, block.binding.receiver).__run(block)
      end
    end

    def initialize(**values)
      @values = {}
      values.each do |name, value|
        unless self.class.open? || self.class.declared_properties.include?(name.to_sym)
          raise ArgumentError, "unknown property #{name.inspect} for #{self.class.name || "Args"}"
        end

        @values[name.to_sym] = value
      end
    end

    # @return [Hash{Symbol => Object}] the properties set, ready to serialize
    def to_h
      @values.dup
    end

    def inspect
      "#<#{self.class.name || "Pulumi::Args"} #{@values.keys.join(", ")}>"
    end
  end

  # Args that accept any property name.
  #
  # This is what a resource constructed from a raw type token uses, since without a
  # generated SDK there is no schema saying which properties exist. It trades the typo
  # detection {Args} provides for the ability to work at all -- generated SDKs should
  # always declare their properties instead.
  class OpenArgs < Args
    def self.open?
      true
    end

    def method_missing(name, *args)
      key = name.to_s.chomp("=").to_sym
      return @values[key] if args.empty? && !name.to_s.end_with?("=")

      @values[key] = args.first
      name.to_s.end_with?("=") ? args.first : self
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end
end
